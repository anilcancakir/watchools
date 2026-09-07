import 'package:magic/magic.dart';

import '../models/title_item.dart';
import '../support/vod_fixture.dart';

/// The three catalogue layouts on offer while the design language is chosen.
///
/// They differ on what a catalogue entry IS: a poster to recognise, a row of
/// facts to compare, or a shelf item to be sold. Same three questions as the
/// line-up, different answers, because a VOD library has artwork where a
/// channel line-up has none.
enum LibraryLayout {
  /// A uniform 2:3 poster grid with a detail sheet. Plex and the tvOS TV app.
  wall,

  /// A dense sortable table. What a library nobody curated actually needs.
  ledger,

  /// A hero over horizontal shelves, split by kind. Netflix.
  showcase,
}

/// Which half of the catalogue is on show.
enum LibraryScope {
  /// Movies and series together, which is how a viewer thinks about a library.
  all,

  /// Movies only.
  movies,

  /// Series only.
  series,
}

/// Everything the catalogue screen knows.
///
/// A [SimpleMagicController] for the same reason [GuideController] is one: the
/// data is a fixture, so there is no request to be loading or failing.
class LibraryController extends SimpleMagicController {
  /// Resolved once and shared by every layout, so switching between them keeps
  /// the query, the scope and the favourites the user just set.
  static LibraryController get instance => Magic.findOrPut(LibraryController.new);

  /// The catalogue, in provider order. Mutable only through [toggleFavourite].
  final List<TitleItem> titles = List<TitleItem>.of(vodFixture);

  LibraryLayout _layout = LibraryLayout.wall;
  LibraryScope _scope = LibraryScope.all;
  String _category = 'Tümü';
  String _query = '';
  late TitleItem _selected = titles.first;
  int _season = 1;
  bool _detailOpen = false;

  /// Cached for the frame, for the same reason the line-up caches: one build
  /// asks for [matches] from the toolbar, the body and the shelves.
  List<TitleItem>? _matchCache;
  List<(String, List<TitleItem>)>? _sectionCache;

  /// Which layout is on show.
  LibraryLayout get layout => _layout;

  /// Which half of the catalogue is on show.
  LibraryScope get scope => _scope;

  /// The selected category, `Tümü` and the two synthetic ones included.
  String get category => _category;

  /// The current search term, unnormalised.
  String get query => _query;

  /// The title the detail surface is showing.
  TitleItem get selected => _selected;

  /// Which season of [selected] is expanded. Meaningless for a movie.
  int get season => _season;

  /// Whether the detail surface is showing as a screen of its own.
  ///
  /// Only two of the three layouts can host the detail beside their body, and
  /// only above `xl`. Everywhere else it has to be a screen you go into and
  /// come back from, which is also the right answer for the shelf layout at any
  /// width: a hero is a promotion, and a promotion cannot hold nine seasons.
  bool get detailOpen => _detailOpen;

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
  /// order, for the layouts that draw shelves.
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

  /// Switches layout, keeping every filter.
  void showLayout(LibraryLayout layout) {
    _layout = layout;
    refreshUI();
  }

  /// Switches between the whole catalogue, movies only and series only.
  void showScope(LibraryScope scope) {
    _scope = scope;
    _invalidate();
    // The selection has to follow the scope or the detail surface keeps showing
    // a series while the grid behind it shows films.
    final List<TitleItem> visible = matches;
    if (visible.isNotEmpty && !visible.contains(_selected)) select(visible.first);
    refreshUI();
  }

  /// Applies a category from the strip.
  void selectCategory(String category) {
    _category = category;
    _invalidate();
    refreshUI();
  }

  /// Applies a search term.
  void search(String query) {
    _query = query;
    _invalidate();
    refreshUI();
  }

  /// Points the detail surface at [title], opening the season its next episode
  /// is in rather than season one.
  void select(TitleItem title) {
    _selected = title;
    _season = title.upNext?.season ?? 1;
    refreshUI();
  }

  /// Selects [title] and shows the detail as a screen.
  void openDetail(TitleItem title) {
    _selected = title;
    _season = title.upNext?.season ?? 1;
    _detailOpen = true;
    refreshUI();
  }

  /// Returns from the detail screen to the body behind it.
  void closeDetail() {
    _detailOpen = false;
    refreshUI();
  }

  /// Expands one season of the selected series.
  void selectSeason(int season) {
    _season = season;
    refreshUI();
  }

  /// Stars or unstars [title], keeping the selection pointed at the new
  /// instance so the detail surface does not fall back to the first title.
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
