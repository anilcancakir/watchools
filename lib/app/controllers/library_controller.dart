import 'package:magic/magic.dart';

import '../models/provider_fault.dart';
import '../models/title_item.dart';
import '../provider/provider_session.dart';
import '../support/fixture_scale.dart';

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
/// A [SimpleMagicController] for the same reason [GuideController] is one:
/// reading a [ProviderFault] off [ProviderSession] is a plain getter, not a
/// request this controller itself makes.
class LibraryController extends SimpleMagicController {
  /// Resolved once and shared by the catalogue and the title screen, so opening
  /// a title and coming back lands on the same query, scope and favourites.
  static LibraryController get instance => Magic.findOrPut(LibraryController.new);

  /// The provider handle passed in, or null to resolve one from the
  /// container. See [_session].
  final ProviderSession? _sessionOverride;

  /// Creates the controller.
  ///
  /// [session] is what [titles], [categories] and [fault] read on the
  /// provider path; pass one in a test, leave it null in the app.
  LibraryController({ProviderSession? session}) : _sessionOverride = session;

  /// The provider handle, resolved on every read rather than captured once.
  ///
  /// `AppServiceProvider.register()` binds `LibraryController` before it
  /// binds `ProviderSession` (`app_service_provider.dart:31-38`), so
  /// capturing the container's instance in the constructor would freeze this
  /// controller on whatever [Magic.findOrPut] auto-vivified at that earlier
  /// moment, a throwaway session `AppServiceProvider`'s own `Magic.put` then
  /// discards. `Magic.findOrPut` rather than `Magic.find` for the same reason
  /// [LibraryController.instance] uses it: a test or a preview that never
  /// bound a [ProviderSession] gets an unstarted one back (no credentials, no
  /// fault, empty catalogue) instead of an exception.
  ProviderSession get _session => _sessionOverride ?? Magic.findOrPut(ProviderSession.new);

  /// The fixture catalogue, mutated in place by [toggleFavourite] while no
  /// provider is configured.
  ///
  /// [FixtureScale] hands back the hand-written fixture unless a measurement
  /// run asked for a generated one through `WATCHOOLS_SCALE` /
  /// `WATCHOOLS_TITLE_SCALE`. Kept alive unconditionally, not only while a
  /// session lacks credentials, so `tool/dusk/perf.sh` keeps measuring the
  /// requested size regardless of what `Vault` holds on the machine it runs
  /// on.
  final List<TitleItem> _fixtureTitles = FixtureScale.titleList;

  /// The reference [_session]'s title list held the last time any cached
  /// getter below ran. See `GuideController._lastSeenChannels` for why this
  /// is a poll rather than a push: [ProviderSession] does not notify.
  List<TitleItem>? _lastSeenTitles;

  /// Drops every cache below when [_session]'s title list has moved since it
  /// was last observed.
  void _syncWithSession() {
    if (!_session.hasCredentials) return;

    final List<TitleItem> current = _session.titles;
    if (identical(current, _lastSeenTitles)) return;

    _lastSeenTitles = current;
    _invalidate();
    _categoriesCache = null;
  }

  /// The catalogue, in provider order. Mutable only through [toggleFavourite].
  ///
  /// [ProviderSession.titles] while a credential is configured, the fixture
  /// otherwise: a session with nothing in `Vault` is not a fault, it is the
  /// state the fixture fallback reads.
  List<TitleItem> get titles {
    _syncWithSession();

    return _session.hasCredentials ? _session.titles : _fixtureTitles;
  }

  /// Why the user's provider is not delivering a working catalogue, or null
  /// when the last handshake was healthy, none has run, or the fixture path
  /// is in use.
  ProviderFault? get fault => _session.fault;

  LibraryScope _scope = LibraryScope.all;
  String _category = 'Tümü';
  String _query = '';

  /// The title the title screen is showing, or null when nothing has ever
  /// been explicitly selected and [titles] is empty.
  TitleItem? _selected;
  int _season = 1;

  /// Cached until a mutation drops it, for the same reason the line-up caches:
  /// one build asks for [matches] from the toolbar, the hero and every rail.
  List<TitleItem>? _matchCache;
  List<(String, List<TitleItem>)>? _sectionCache;
  List<TitleItem>? _resumeCache;
  int? _noArtworkCache;
  List<String>? _categoriesCache;

  /// Which half of the catalogue is on show.
  LibraryScope get scope => _scope;

  /// The selected category, `Tümü` and the two synthetic ones included.
  String get category => _category;

  /// The current search term, unnormalised.
  String get query => _query;

  /// The title the title screen is showing, or null when the catalogue is
  /// empty (the normal state during a provider's first refresh).
  ///
  /// Falls back to the first entry in [titles] until an explicit [select] has
  /// run, which is what lets [_selected] start out unset instead of throwing
  /// the moment a `late` initialiser read an empty list.
  TitleItem? get selected => _selected ?? (titles.isEmpty ? null : titles.first);

  /// Which season of [selected] is expanded. Meaningless for a movie.
  int get season => _season;

  /// Everything matching the current scope, category and query, in order.
  List<TitleItem> get matches {
    _syncWithSession();

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
    _syncWithSession();

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
  ///
  /// Cached like [matches], because `Vitrin` asks for it three times in one
  /// build: once to decide whether the resume rail exists, once for the hero's
  /// fallback, once for the rail's own contents. Each ask walked the whole
  /// catalogue and, for a series, walked its episode list too.
  List<TitleItem> get continueWatching {
    _syncWithSession();

    return _resumeCache ??= matches.where((TitleItem t) => t.inProgress).toList();
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
    _syncWithSession();

    final int? cached = _noArtworkCache;
    final int count = cached ?? (_noArtworkCache = matches.where((TitleItem t) => t.posterUrl == null).length);

    return count == 0 ? null : '$count başlıkta afiş yok';
  }

  /// The catalogue category tabs.
  ///
  /// On the fixture path this stays [FixtureScale.categoryList]. On the
  /// provider path there is no such curated list, so it is derived from
  /// whatever [titles] actually holds.
  List<String> get categories {
    _syncWithSession();

    return _categoriesCache ??= _session.hasCredentials ? _providerCategories(titles) : FixtureScale.categoryList;
  }

  /// `Tümü`, `İzlemeye devam et` and `Favoriler`, then every distinct
  /// [TitleItem.category] in [titles], in first-appearance order.
  static List<String> _providerCategories(List<TitleItem> titles) {
    final List<String> seen = <String>[];
    for (final TitleItem title in titles) {
      if (!seen.contains(title.category)) seen.add(title.category);
    }

    return <String>['Tümü', 'İzlemeye devam et', 'Favoriler', ...seen];
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
  ///
  /// Routes through [ProviderSession.setTitleFavourite] while a credential is
  /// configured, which is what makes the star survive a restart; a fixture
  /// title carries no `providerId` (`title_item.dart:194`) for that call to
  /// key on, so the fixture path keeps mutating [_fixtureTitles] in place,
  /// same as before this controller read a session at all.
  void toggleFavourite(TitleItem title) {
    final int index = titles.indexOf(title);

    if (_session.hasCredentials) {
      final int? providerId = title.providerId;
      if (providerId != null) {
        _session.setTitleFavourite(kind: title.kind, providerId: providerId, favourite: !title.favourite);
      }
    } else {
      _fixtureTitles[index] = title.toggleFavourite();
    }

    if (identical(_selected, title)) _selected = titles[index];
    _invalidate();
    refreshUI();
  }

  void _invalidate() {
    _matchCache = null;
    _sectionCache = null;
    _resumeCache = null;
    _noArtworkCache = null;
  }

  /// Asks the provider for a fresh catalogue, then repaints.
  ///
  /// What `ProviderNotice`'s retry button calls. It lives here rather than
  /// being reached from a layout because the screens read their state from
  /// this controller, and a widget calling [ProviderSession] directly would
  /// give the same screen two sources of truth.
  ///
  /// With no credentials, or during playback, the session's own
  /// [ProviderSession.refresh] returns without sending anything, so no guard
  /// is needed here for either case.
  Future<void> reload() async {
    await _session.refresh();

    _invalidate();
    _categoriesCache = null;
    refreshUI();
  }
}
