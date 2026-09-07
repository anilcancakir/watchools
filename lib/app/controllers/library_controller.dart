import 'package:magic/magic.dart';

import '../models/title_item.dart';
import '../support/vod_fixture.dart';

/// The three catalogue directions on offer while the design language is chosen.
///
/// Each descends from a different reference, and they disagree about who the
/// screen belongs to: the editor who arranged it, the owner who wants to sort
/// their own shelf, or the browser who has not decided what they want yet.
enum LibraryDirection {
  /// A hero over editorial rails. Netflix, and the arrival screen: it decides
  /// what you watch rather than helping you find it.
  showcase,

  /// A sidebar over a poster grid with the user's own controls: card size,
  /// sort order, grid or table. Plex, and the direction that survives the five
  /// thousand title dump a provider actually sends.
  shelf,

  /// Editorially grouped tiles at mixed sizes, plus a rail of provider tiles.
  /// Apple TV's composition, and the only one where the layout itself says
  /// which titles matter.
  collection,
}

/// The three detail directions.
///
/// Kept on this controller rather than on one of their own, because the detail
/// screen has no state that is not already here: it shows [selected] and
/// [season], and a second source of truth for those is a second thing to keep
/// in step.
enum DetailDirection {
  /// Plex's record card: poster left, stacked facts right, one amber verb and
  /// a row of ghost icons, seasons and cast below.
  record,

  /// Netflix's television detail: full-bleed artwork, display type, and the
  /// season list as a sibling column of the episode list rather than a
  /// dropdown.
  curtain,

  /// Plex on Android, scaled up: overlapping poster, a circular play button on
  /// the seam, and the technical spec table as a first-class section.
  sheet,
}

/// How large the cards are on [LibraryDirection.shelf].
///
/// Plex gives the user a zoom slider and it is not a gimmick: a library of
/// forty wants big artwork and a library of five thousand wants small, and only
/// the user knows which one they have.
enum ShelfDensity {
  /// Small cards, most titles per screen.
  compact,

  /// The default.
  regular,

  /// Large artwork, fewest per screen.
  roomy,
}

/// What [LibraryDirection.shelf] orders by.
enum ShelfSort {
  /// The provider's own order, which is the order it sent them in.
  provider,

  /// Alphabetical.
  name,

  /// Newest first.
  year,

  /// Highest rated first, unrated last.
  rating,
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

  LibraryDirection _direction = LibraryDirection.showcase;
  DetailDirection _detail = DetailDirection.record;
  ShelfDensity _density = ShelfDensity.regular;
  ShelfSort _sort = ShelfSort.provider;
  bool _asTable = false;
  LibraryScope _scope = LibraryScope.all;
  String _category = 'Tümü';
  String _query = '';
  late TitleItem _selected = titles.first;
  int _season = 1;

  /// Cached until a mutation drops it, for the same reason the line-up caches: one build
  /// asks for [matches] from the toolbar, the body and the shelves.
  List<TitleItem>? _matchCache;
  List<(String, List<TitleItem>)>? _sectionCache;
  List<TitleItem>? _sortCache;
  List<(String, List<TitleItem>)>? _collectionCache;

  /// Which catalogue direction is on show.
  LibraryDirection get direction => _direction;

  /// Which detail direction the title screen is drawing.
  DetailDirection get detail => _detail;

  /// How large the shelf's cards are.
  ShelfDensity get density => _density;

  /// What the shelf orders by.
  ShelfSort get sort => _sort;

  /// Whether the shelf is drawing a table instead of a grid.
  bool get asTable => _asTable;

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

  /// [matches] in the order the shelf's sort control asks for.
  ///
  /// `provider` is the default and is not a lazy one. A playlist arrives in an
  /// order the provider chose, which groups related titles together, and
  /// alphabetising by default throws away the only structure the feed shipped
  /// with. The other three orders exist because the user asked for them.
  /// Cached like [matches], because it is read from the grid's builder, the
  /// table's builder AND the title screen's previous/next arrows within one
  /// frame, and every read re-copied and re-sorted the whole catalogue.
  List<TitleItem> get sorted {
    final List<TitleItem>? cached = _sortCache;
    if (cached != null) return cached;

    final List<TitleItem> result = List<TitleItem>.of(matches);

    switch (_sort) {
      case ShelfSort.provider:
        return _sortCache = result;
      case ShelfSort.name:
        // Turkish collation, not `compareTo`. Dart compares UTF-16 code units,
        // which puts every dotted and accented letter after `z`: `Çınar` sorts
        // below `Zeynep` and the user reads it as a bug in the sort.
        result.sort((TitleItem a, TitleItem b) => _fold(a.name).compareTo(_fold(b.name)));
      case ShelfSort.year:
        result.sort((TitleItem a, TitleItem b) => b.year.compareTo(a.year));
      case ShelfSort.rating:
        // Unrated last rather than first. A provider omits a rating far more
        // often than it sends a zero, so treating null as zero would bury the
        // rated titles under everything it said nothing about.
        result.sort((TitleItem a, TitleItem b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
    }

    return _sortCache = result;
  }

  /// The Turkish alphabet in order, for collation.
  static const String _alphabet = 'aâbcçdefgğhıiîjklmnoöprsştuüûvyz';

  /// The two case mappings Dart's locale-independent `toLowerCase` gets wrong
  /// for Turkish, applied before it.
  ///
  /// `I` lowercases to `i` rather than `ı`, so `Irmak` sorted after `İnce`.
  /// `İ` lowercases to `i` plus a combining dot above, and the combining mark
  /// then landed past every letter in the key. Both have to be replaced first,
  /// because after `toLowerCase` neither is distinguishable from a correctly
  /// cased one.
  static const Map<String, String> _turkishLower = <String, String>{'I': 'ı', 'İ': 'i'};

  /// Maps a name onto a sortable key in Turkish alphabetical order.
  static String _fold(String value) {
    final StringBuffer out = StringBuffer();
    String folded = value;
    for (final MapEntry<String, String> entry in _turkishLower.entries) {
      folded = folded.replaceAll(entry.key, entry.value);
    }

    for (final int rune in folded.toLowerCase().runes) {
      final int index = _alphabet.indexOf(String.fromCharCode(rune));
      // Anything outside the alphabet (a digit, a space, punctuation) keeps its
      // own code point offset past the letters, so it sorts consistently
      // without colliding with a letter's index.
      out.writeCharCode(index == -1 ? 100 + rune : 32 + index);
    }

    return out.toString();
  }

  /// Everything the viewer started and did not finish, movies and episodes
  /// alike. The one shelf a returning viewer actually opens the app for.
  List<TitleItem> get continueWatching => matches.where((TitleItem t) => t.inProgress).toList();

  /// The editorial groups the collection direction composes its tiles from.
  ///
  /// Four rows with a point of view rather than the provider's categories,
  /// which the shelf already exposes. Netflix titles its rows with sentences
  /// and this is the direction that leans on that hardest, because its tile
  /// sizes are the argument: the first title in a collection gets the large
  /// tile, so the layout itself says which one matters.
  ///
  /// A group with fewer than two entries is dropped. A bento composition needs
  /// a feature and at least one supporting tile, and one tile alone reads as a
  /// broken grid rather than as a short row.
  ///
  /// No title features twice. The groups overlap by design (a favourite is
  /// often also half-watched), so without this the same artwork appears at
  /// hero scale two or three times down one screen and the composition's whole
  /// claim, that size means importance, stops being true.
  /// Cached, because it is the only derived getter here that is O(n·m): the
  /// `featured` membership test runs inside the group loop, and the whole thing
  /// is recomputed on every build of the direction that reads it. Invisible at
  /// fifteen titles and not at five thousand.
  List<(String, List<TitleItem>)> get collections {
    final List<(String, List<TitleItem>)>? cached = _collectionCache;
    if (cached != null) return cached;

    final List<TitleItem> pool = matches;

    final List<(String, List<TitleItem>)> groups = <(String, List<TitleItem>)>[
      ('Yarım kalanlar', pool.where((TitleItem t) => t.inProgress).toList()),
      ('Yıldızladıkların', pool.where((TitleItem t) => t.favourite).toList()),
      ('Bu yılın dizileri', pool.where((TitleItem t) => t.isSeries && t.year >= 2022).toList()),
      ('Yüksek puanlı filmler', pool.where((TitleItem t) => !t.isSeries && (t.rating ?? 0) >= 7.5).toList()),
      ('Afişi gelmeyenler', pool.where((TitleItem t) => t.posterUrl == null).toList()),
    ];

    final List<TitleItem> featured = <TitleItem>[];
    final List<(String, List<TitleItem>)> result = <(String, List<TitleItem>)>[];

    for (final (String name, List<TitleItem> members) in groups) {
      if (members.length < 2) continue;

      // Rotate the first unfeatured entry to the front rather than dropping the
      // group. Everything in it still belongs there; only the choice of which
      // one gets the large tile moves.
      final int index = members.indexWhere((TitleItem t) => !featured.contains(t));
      if (index == -1) continue;

      final TitleItem lead = members.removeAt(index);
      featured.add(lead);
      result.add((name, <TitleItem>[lead, ...members]));
    }

    // A narrowed catalogue still has to show its results.
    //
    // Every group needs two entries to compose, so a search that matches one
    // title fills none of them and the screen said "no collections formed"
    // while holding a perfectly good result. That is this direction failing the
    // doctrine's sixth rule outright: search is a peer of navigation, and a
    // browse surface that answers a query with an explanation of its own
    // internals is not one.
    //
    // The fallback is a single unnamed group, so the composition still applies
    // (first tile large, rest supporting) and nothing about the direction
    // changes except that it answers.
    if (result.isEmpty && pool.isNotEmpty) {
      return _collectionCache = <(String, List<TitleItem>)>[('Sonuçlar', List<TitleItem>.of(pool))];
    }

    return _collectionCache = result;
  }

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

  /// Switches direction, keeping every filter.
  void showDirection(LibraryDirection direction) {
    _direction = direction;
    refreshUI();
  }

  /// Switches which detail direction the title screen draws.
  void showDetail(DetailDirection detail) {
    _detail = detail;
    refreshUI();
  }

  /// Sets the shelf's card size.
  void showDensity(ShelfDensity density) {
    _density = density;
    refreshUI();
  }

  /// Sets the shelf's order.
  void showSort(ShelfSort sort) {
    _sort = sort;
    _invalidate();
    refreshUI();
  }

  /// Swaps the shelf between a poster grid and a table.
  void showTable({required bool asTable}) {
    _asTable = asTable;
    refreshUI();
  }

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
  /// alone: narrowing by CATEGORY left the detail on a title the grid no longer
  /// held, so the previous/next arrows walked a list the selection was not in.
  ///
  /// Search is deliberately not a caller. A query is transient and often
  /// mistyped, and re-pointing on every keystroke would drag the detail screen
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

  /// Points the detail surface at [title], opening the season its next episode
  /// is in rather than season one.
  void select(TitleItem title) {
    _selected = title;
    _season = title.upNext?.season ?? 1;
    refreshUI();
  }

  /// Selects [title] and navigates to the detail screen.
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
    _sortCache = null;
    _collectionCache = null;
  }
}
