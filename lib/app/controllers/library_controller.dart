import 'package:magic/magic.dart';

import '../models/title_item.dart';
import '../support/vod_fixture.dart';

/// Which half of the catalogue is on show.
enum LibraryScope {
  /// Movies and series together, which is how a viewer thinks about a library.
  all,

  /// Movies only.
  movies,

  /// Series only.
  series,
}

/// Everything the catalogue screen knows, and everything the title screen
/// behind it reads.
///
/// One controller for two routes, because the title screen has no state that is
/// not already here: it shows [selected] and [season], and a second source of
/// truth for those is a second thing to keep in step.
///
/// A [SimpleMagicController] for the same reason [GuideController] is one: the
/// data is a fixture, so there is no request to be loading or failing.
class LibraryController extends SimpleMagicController {
  /// Resolved once and shared by the catalogue and the title screen, so opening
  /// a title and coming back lands on the same query, scope and favourites.
  static LibraryController get instance => Magic.findOrPut(LibraryController.new);

  /// The catalogue, in provider order. Mutable only through [toggleFavourite].
  final List<TitleItem> titles = List<TitleItem>.of(vodFixture);

  LibraryScope _scope = LibraryScope.all;
  String _category = 'Tümü';
  String _query = '';
  late TitleItem _selected = titles.first;
  int _season = 1;

  /// Cached until a mutation drops it, for the same reason the line-up caches:
  /// one build asks for [matches] from the toolbar, the hero and every rail.
  List<TitleItem>? _matchCache;
  List<(String, List<TitleItem>)>? _sectionCache;

  /// Which half of the catalogue is on show.
  LibraryScope get scope => _scope;

  /// The selected category, `Tümü` and the two synthetic ones included.
  String get category => _category;

  /// The current search term, unnormalised.
  String get query => _query;

  /// The title the title screen is showing.
  TitleItem get selected => _selected;

  /// Which season of [selected] is expanded. Meaningless for a movie.
  int get season => _season;

  /// Everything matching the current scope, category and query, in order.
  List<TitleItem> get matches {
    final List<TitleItem>? cached = _matchCache;
    if (cached != null) return cached;

    final String needle = _query.trim().toLowerCase();

    final List<TitleItem> result = titles.where((TitleItem title) {
      if (_scope == LibraryScope.movies && title.isSeries) return false;
      if (_scope == LibraryScope.series && !title.isSeries) return false;

      switch (_category) {
        case 'Tümü':
          break;
        case 'Favoriler':
          if (!title.favourite) return false;
        case 'İzlemeye devam et':
          if (!title.inProgress) return false;
        default:
          // Matched against the provider's category AND the genre list, because
          // a provider's `category_name` is one string while its `genre` field
          // carries several, and a viewer who taps Dram means either.
          final bool byCategory = title.category == _category;
          final bool byGenre = title.genres.contains(_category);
          if (!byCategory && !byGenre) return false;
      }

      if (needle.isEmpty) return true;

      // Name, year, and for a series the episode titles. Searching episodes
      // matters: people remember the episode, not the season number.
      if (title.name.toLowerCase().contains(needle)) return true;
      if (title.year.toString().contains(needle)) return true;

      return title.episodes.any((Episode e) => e.title.toLowerCase().contains(needle));
    }).toList();

    _matchCache = result;

    return result;
  }

  /// [matches] cut into the provider's own categories, in first-appearance
  /// order, which is what `Vitrin` cuts its poster rails on.
  List<(String, List<TitleItem>)> get sections {
    final List<(String, List<TitleItem>)>? cached = _sectionCache;
    if (cached != null) return cached;

    final Map<String, List<TitleItem>> grouped = <String, List<TitleItem>>{};

    for (final TitleItem title in matches) {
      grouped.putIfAbsent(title.category, () => <TitleItem>[]).add(title);
    }

    _sectionCache = grouped.entries.map((MapEntry<String, List<TitleItem>> e) => (e.key, e.value)).toList();

    return _sectionCache!;
  }

  /// Everything the viewer started and did not finish, movies and episodes
  /// alike. The one shelf a returning viewer actually opens the app for.
  List<TitleItem> get continueWatching => matches.where((TitleItem t) => t.inProgress).toList();

  /// How many titles the current filter left, worded for whether a search is
  /// active. Same discipline as the line-up's: one number, one spelling.
  String get countLabel {
    final int total = matches.length;

    return query.trim().isEmpty ? '$total başlık' : '$total sonuç';
  }

  /// How many of [matches] arrived with no poster.
  ///
  /// Stated on screen for the same reason the line-up states its missing-EPG
  /// count: it is a fact about the user's provider rather than a fault in the
  /// app, and a poster wall is the layout it decides.
  String? get noArtworkNote {
    final int count = matches.where((TitleItem t) => t.posterUrl == null).length;

    return count == 0 ? null : '$count başlıkta afiş yok';
  }

  /// The catalogue category tabs.
  List<String> get categories => vodCategories;

  /// Switches between the whole catalogue, movies only and series only.
  void showScope(LibraryScope scope) {
    _scope = scope;
    _invalidate();
    _followFilter();
    refreshUI();
  }

  /// Applies a category from the strip.
  void selectCategory(String category) {
    _category = category;
    _invalidate();
    _followFilter();
    refreshUI();
  }

  /// Re-points the selection when the filter has moved it out of view.
  ///
  /// The invariant is that the title screen shows something the catalogue
  /// behind it is also showing, and it used to be enforced by the scope switch
  /// alone: narrowing by CATEGORY left the selection on a title the catalogue
  /// no longer held, so pressing back landed on a screen that did not contain
  /// what had just been on it.
  ///
  /// Search is deliberately not a caller. A query is transient and often
  /// mistyped, and re-pointing on every keystroke would drag the title screen
  /// through whatever half-typed prefix matched.
  void _followFilter() {
    final List<TitleItem> visible = matches;
    if (visible.isEmpty) return;
    if (visible.contains(_selected)) return;

    select(visible.first);
  }

  /// Applies a search term.
  void search(String query) {
    _query = query;
    _invalidate();
    refreshUI();
  }

  /// Points the title screen at [title], opening the season its next episode
  /// is in rather than season one.
  void select(TitleItem title) {
    _selected = title;
    _season = title.upNext?.season ?? 1;
    refreshUI();
  }

  /// Selects [title] and navigates to the title screen.
  ///
  /// A route rather than an overlay, which the previous pass got wrong. All
  /// three references treat a title's page as a page: the browser back button
  /// and a remote's back key both have to land somewhere, and an overlay held
  /// in controller state gives them nowhere to land.
  void openDetail(TitleItem title) {
    select(title);
    MagicRoute.to('/baslik');
  }

  /// Expands one season of the selected series.
  void selectSeason(int season) {
    _season = season;
    refreshUI();
  }

  /// Stars or unstars [title], keeping the selection pointed at the new
  /// instance so the title screen does not fall back to the first title.
  void toggleFavourite(TitleItem title) {
    final int index = titles.indexOf(title);
    titles[index] = title.toggleFavourite();
    if (identical(_selected, title)) _selected = titles[index];
    _invalidate();
    refreshUI();
  }

  void _invalidate() {
    _matchCache = null;
    _sectionCache = null;
  }
}
