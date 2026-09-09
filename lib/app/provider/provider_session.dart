import '../models/channel.dart';
import '../models/programme.dart';
import '../models/provider_fault.dart';
import '../models/title_item.dart';
import '../protocol/xtream/xtream_account.dart';
import '../protocol/xtream/xtream_client.dart';
import '../protocol/xtream/xtream_credentials.dart';
import '../protocol/xtream/xtream_json.dart';
import '../support/guide_clock.dart';
import 'catalogue_store.dart';

/// The app's single handle on "which provider, is it healthy, what is
/// cached".
///
/// ## Why this exists and what binds it
///
/// Everything below the widget belongs to Magic (`CLAUDE.md`), and this is
/// that layer's entry point for the Xtream client: it loads
/// [XtreamCredentials] from `Vault`, holds the last [XtreamAccount] and the
/// current [ProviderFault], and exposes the catalogue the two controllers
/// read. Nothing else in the app performs this I/O, so [AppServiceProvider]
/// binds an instance in `register()` (synchronous, before `Magic.init()`
/// completes) and kicks [start] from `boot()`, which is where
/// `RouteServiceProvider` already does its own deferred work
/// (`route_service_provider.dart:24-54`). Until [start] finishes, every
/// getter here reports "no provider configured", which is the state the
/// fixture fallback reads.
///
/// ## Classification lives here, not in the client
///
/// A single response cannot say why a provider is failing: the same
/// HTTP-200-plus-non-JSON shape is a blocked address, a blocked user agent,
/// an HTML error page, a rate limit and an expired stream request alike
/// (`tool/xtream-mock/README.md:126-129`). Telling them apart needs the
/// handshake as context, which is [_account]: the last one this session
/// parsed, carried forward across a denial that carries none of its own.
/// [classifyProviderFault] is called from the handshake on every
/// [refresh], never from whether a catalogue action's body happened to
/// parse: a non-active account still returns its whole line-up and fails
/// only at the stream, so reading a successful list fetch as health would
/// show a complete, entirely unplayable catalogue for a dead subscription.
///
/// ## The playback gate
///
/// Whether a `player_api.php` call costs one of the account's connection
/// slots is unmeasured, and the one eviction this app has measured had a
/// `.ts` request on both sides. [refresh] therefore refuses to find out at
/// the viewer's expense: while [_isPlaying] answers true, it returns having
/// sent nothing, provable on a faked driver by `assertSentCount(0)`.
///
/// ## What a refresh persists, and what it deliberately does not read back
///
/// [CatalogueStore] does not persist a channel's schedule
/// (`catalogue_store.dart:68-85`), so [channelsFor] restores one with an
/// empty schedule; reading it back after [_store]'s replace would erase the
/// short-EPG merge a refresh just did. Channels are therefore held from what
/// this session built rather than read back, and favourites are carried
/// forward from what the session already knew rather than re-queried.
/// Titles carry no such state: nothing here needs a title's schedule, so
/// [_refreshTitles] reads the replaced rows straight back, and the store's
/// own carry-over (by `(kind, provider_id)`) is what keeps a favourite and a
/// progress value across the replace.
///
/// ## The clock
///
/// [clock] is a [TickingGuideClock] anchored to today's local midnight, and
/// every [Programme] a refresh builds is computed from that SAME
/// [DateTime], which is the whole reason the two stay in agreement while the
/// app runs (`CLAUDE.md`, "The clock, and the decision already taken"). A
/// calendar day crossed while the app is open makes that midnight stale;
/// [_anchorClock] re-anchors on the next [refresh] rather than mid-session,
/// which is the cheap answer taken here and the reason [clock] can hand back
/// a different instance across two refreshes. Any listener attached to the
/// previous instance must detach before that happens: this class does not
/// track them. The 180px "now line" teleport a fresh anchor causes on the
/// grid is `CLAUDE.md`'s own tracked follow-up (a sticky window), out of
/// scope here.
class ProviderSession {
  /// The on-screen minimum, bounded.
  ///
  /// A real catalogue can hold thousands of channels and only about one in
  /// eleven carries an `epg_channel_id` at all, so this is a conservative,
  /// revisitable guess: which channels are actually on screen is the
  /// controllers' question, and asking them here would invert the
  /// dependency the session exists to break. Public and set only at
  /// construction, so a test can exercise the bound itself without building
  /// thousands of fixtures; nothing reads it as a mutable setting.
  final int epgFetchLimit;

  /// Where the cached and the replaced catalogue live.
  final CatalogueStore _store;

  /// Whether a caller may not invoke [refresh] right now. Modelled as an
  /// injectable predicate rather than a real player check, because there is
  /// no `PlaybackEngine` in this repository yet (`CLAUDE.md`): defaulting to
  /// "not playing" keeps the rule expressed and testable now, ready to be
  /// wired to the real thing once that interface exists.
  final bool Function() _isPlaying;

  XtreamCredentials? _credentials;
  XtreamClient? _client;
  XtreamAccount? _account;
  ProviderFault? _fault;
  GuideClock? _clock;
  DateTime? _midnight;
  List<Channel> _channels = const <Channel>[];
  List<TitleItem> _titles = const <TitleItem>[];

  /// Creates a session. [store] defaults to a fresh, stateless
  /// [CatalogueStore]; [isPlaying] defaults to "never playing".
  ProviderSession({this._store = const CatalogueStore(), bool Function()? isPlaying, this.epgFetchLimit = 20})
    : _isPlaying = isPlaying ?? _neverPlaying;

  /// Whether the user has a provider configured at all.
  ///
  /// False until [start] finishes loading, and false forever when `Vault`
  /// holds nothing: that is not a fault, it is the state the fixture
  /// fallback reads.
  bool get hasCredentials => _credentials != null;

  /// Why the provider is not delivering a working catalogue, or null when
  /// the last handshake was healthy (or none has run yet).
  ProviderFault? get fault => _fault;

  /// The clock a refresh anchored, for the provider path only. Null until
  /// the first successful [refresh]; the fixture path keeps its own
  /// `FixedGuideClock`.
  GuideClock? get clock => _clock;

  /// The line-up, in provider order. Empty until [start] has loaded
  /// something, from the cache or from a refresh.
  List<Channel> get channels => _channels;

  /// The VOD catalogue, in provider order.
  List<TitleItem> get titles => _titles;

  /// Loads the stored credential and the cached catalogue. **Local only: this
  /// does not touch the network.** Call once, from
  /// `AppServiceProvider.boot()`, and await it there.
  ///
  /// 1. [CatalogueStore.migrate] first: the store has no lazy schema
  ///    creation, so a read before this fails loudly rather than
  ///    re-checking the schema on every one (`catalogue_store.dart:129`).
  /// 2. No stored credential is not a fault: every getter stays at its
  ///    empty default and nothing here performs any I/O beyond the vault
  ///    read.
  /// 3. Restore the cached catalogue, so a screen has something to render on
  ///    the first frame.
  ///
  /// **[refresh] is deliberately NOT called from here**, and the split is
  /// load-bearing rather than tidy. `boot()` runs inside `Magic.init()`,
  /// which `main()` awaits before `runApp()`, so anything awaited in that
  /// window delays the first frame by exactly its own duration. A real
  /// refresh is a handshake plus 2,976 channels plus 38,247 titles plus up
  /// to [epgFetchLimit] sequential EPG round trips, over an account whose
  /// measured `max_connections` is 1: seconds at best, and a blank window
  /// for all of them. So the caller awaits this, gets the cached catalogue
  /// on screen, and lets [refresh] land afterwards.
  ///
  /// A test that wants the fetched catalogue awaits both in turn.
  Future<void> start() async {
    _store.migrate();

    final XtreamCredentials? credentials = await XtreamCredentials.load();
    _credentials = credentials;

    if (credentials == null) return;

    _client = XtreamClient(credentials);

    final String account = CatalogueStore.accountKey(credentials);
    _channels = _store.channelsFor(account);
    _titles = _store.titlesFor(account);
  }

  /// Refreshes the handshake, the classification and, when healthy, the
  /// catalogue. A no-op, never a throw, when playback is active or no
  /// credential is loaded.
  ///
  /// 1. The playback gate: [_isPlaying] true means no request leaves at
  ///    all.
  /// 2. The handshake, and only the handshake, decides [fault].
  /// 3. [classifyProviderFault] needs an account to compare a denial
  ///    against: this call's own, when the body parsed, or the session's
  ///    last known one otherwise. A throttled or evicted denial carries no
  ///    account of its own; only a previously-established one lets the
  ///    classifier tell it apart from a fresh `expired`.
  /// 4. A fault stops here: the line-up and the catalogue keep whatever
  ///    they already held, rather than racing ahead to fetch one for a
  ///    subscription already known dead.
  /// 5. Healthy: re-anchor the clock, then rebuild the channel and the VOD
  ///    catalogue in turn.
  Future<void> refresh() async {
    if (_isPlaying()) return;

    final XtreamCredentials? credentials = _credentials;
    final XtreamClient? client = _client;
    if (credentials == null || client == null) return;

    final XtreamResponse<Map<String, dynamic>> handshake = await client.handshake();
    final XtreamAccount? parsed = handshake.data == null ? null : XtreamAccount.fromHandshake(handshake.data!);

    _fault = classifyProviderFault(account: parsed ?? _account, statusCode: handshake.statusCode, body: handshake.body);
    if (parsed != null) _account = parsed;

    if (_fault != null) return;

    _anchorClock();

    final String account = CatalogueStore.accountKey(credentials);
    await _refreshChannels(client: client, account: account);
    await _refreshTitles(client: client, account: account);
  }

  /// Stars or unstars a channel, in the store and in the held line-up.
  /// A no-op with no credential loaded: there is no account key to write
  /// under.
  void setChannelFavourite({required int streamId, required bool favourite}) {
    final XtreamCredentials? credentials = _credentials;
    if (credentials == null) return;

    _store.setChannelFavourite(
      account: CatalogueStore.accountKey(credentials),
      streamId: streamId,
      favourite: favourite,
    );

    _channels = <Channel>[
      for (final Channel channel in _channels)
        channel.streamId == streamId ? _applyChannelFavourite(channel, favourite) : channel,
    ];
  }

  /// Stars or unstars a title, in the store and in the held catalogue.
  void setTitleFavourite({required TitleKind kind, required int providerId, required bool favourite}) {
    final XtreamCredentials? credentials = _credentials;
    if (credentials == null) return;

    _store.setTitleFavourite(
      account: CatalogueStore.accountKey(credentials),
      kind: kind,
      providerId: providerId,
      favourite: favourite,
    );

    _titles = <TitleItem>[
      for (final TitleItem title in _titles)
        (title.kind == kind && title.providerId == providerId) ? _applyTitleFavourite(title, favourite) : title,
    ];
  }

  /// Records how far through a title the viewer got, in the store and in
  /// the held catalogue.
  void setTitleProgress({required TitleKind kind, required int providerId, required double progress}) {
    final XtreamCredentials? credentials = _credentials;
    if (credentials == null) return;

    _store.setTitleProgress(
      account: CatalogueStore.accountKey(credentials),
      kind: kind,
      providerId: providerId,
      progress: progress,
    );

    _titles = <TitleItem>[
      for (final TitleItem title in _titles)
        (title.kind == kind && title.providerId == providerId) ? _withProgress(title, progress) : title,
    ];
  }

  /// Rebuilds the line-up from `get_live_categories` and `get_live_streams`,
  /// merges the on-screen minimum of `get_short_epg`, carries every
  /// favourite the session already knew, and replaces the store.
  ///
  /// The built list is held directly rather than read back from
  /// [CatalogueStore.channelsFor]: that method restores an empty schedule by
  /// design, which would erase the merge this method just did.
  Future<void> _refreshChannels({required XtreamClient client, required String account}) async {
    final Map<int, bool> previousFavourites = <int, bool>{
      for (final Channel channel in _channels)
        if (channel.streamId != null) channel.streamId!: channel.favourite,
    };

    final Map<String, String> categoryNames = await _categoryNames(client.liveCategories);
    final List<Map<String, dynamic>> rawChannels = (await client.liveStreams()).data ?? const <Map<String, dynamic>>[];
    final GuideClock guideClock = _clock!;

    final List<Channel> built = <Channel>[
      for (final Map<String, dynamic> entry in rawChannels)
        Channel.fromXtream(entry, categoryName: categoryNames[_categoryId(entry)] ?? '', clock: guideClock),
    ];

    for (int index = 0; index < built.length && index < epgFetchLimit; index++) {
      final String? epgChannelId = readNullableString(rawChannels[index], 'epg_channel_id');
      final int? streamId = built[index].streamId;
      if (epgChannelId == null || streamId == null) continue;

      final List<Map<String, dynamic>> listings =
          (await client.shortEpg(streamId)).data ?? const <Map<String, dynamic>>[];
      final List<Programme> schedule = <Programme>[
        for (final Map<String, dynamic> listing in listings)
          if (Programme.fromXtream(listing, referenceMidnight: _midnight!) case final Programme programme) programme,
      ];
      if (schedule.isEmpty) continue;

      built[index] = Channel.fromXtream(
        rawChannels[index],
        categoryName: built[index].group,
        clock: guideClock,
        schedule: schedule,
      );
    }

    final List<Channel> withFavourites = <Channel>[
      for (final Channel channel in built)
        _applyChannelFavourite(channel, previousFavourites[channel.streamId] ?? false),
    ];

    await _store.replaceChannels(account: account, channels: withFavourites);
    _channels = withFavourites;
  }

  /// Rebuilds the VOD catalogue from both ID spaces, then replaces the store
  /// and reads the replaced rows straight back: unlike a channel, a title
  /// carries no per-refresh state this layer needs to hold outside the store,
  /// so [CatalogueStore]'s own favourite/progress carry-over is the only
  /// reconciliation needed.
  ///
  /// **Both spaces, deliberately.** `get_vod_streams` keys a movie on
  /// `stream_id` and `get_series` keys a series on `series_id`, and the two
  /// numbers collide, which is why [TitleItem.providerId] is only meaningful
  /// beside its [TitleItem.kind]. Fetching only movies would fix the title
  /// screen to one space, and the retrofit would then be a route change plus a
  /// store migration rather than a route change alone. `get_series_info`, the
  /// per-series detail, stays deferred: this pass takes the list only, which is
  /// what makes the ID space known without paying for the depth.
  ///
  /// A panel answering `get_series` with `[]` is a real answer rather than a
  /// gap; one of the four captured panels does exactly that, so the series half
  /// contributing nothing is an expected shape and not an error.
  Future<void> _refreshTitles({required XtreamClient client, required String account}) async {
    final List<TitleItem> built = <TitleItem>[
      ...await _titlesOf(kind: TitleKind.movie, categories: client.vodCategories, entries: client.vodStreams),
      ...await _titlesOf(kind: TitleKind.series, categories: client.seriesCategories, entries: client.series),
    ];

    await _store.replaceTitles(account: account, titles: built);
    _titles = _store.titlesFor(account);
  }

  /// One ID space's worth of titles: its category names resolved, then its
  /// entries mapped as [kind].
  static Future<List<TitleItem>> _titlesOf({
    required TitleKind kind,
    required Future<XtreamResponse<List<Map<String, dynamic>>>> Function() categories,
    required Future<XtreamResponse<List<Map<String, dynamic>>>> Function() entries,
  }) async {
    final Map<String, String> categoryNames = await _categoryNames(categories);
    final List<Map<String, dynamic>> raw = (await entries()).data ?? const <Map<String, dynamic>>[];

    return <TitleItem>[
      for (final Map<String, dynamic> entry in raw)
        TitleItem.fromXtream(entry, kind: kind, categoryName: categoryNames[_categoryId(entry)] ?? ''),
    ];
  }

  /// A category id to `category_name` map, from whichever `*Categories`
  /// action [fetch] is.
  static Future<Map<String, String>> _categoryNames(
    Future<XtreamResponse<List<Map<String, dynamic>>>> Function() fetch,
  ) async {
    final List<Map<String, dynamic>> categories = (await fetch()).data ?? const <Map<String, dynamic>>[];

    return <String, String>{
      for (final Map<String, dynamic> category in categories)
        _categoryId(category): readNullableString(category, 'category_name') ?? '',
    };
  }

  /// A live or VOD entry's `category_id`, normalised to a string so it
  /// matches the same field read off the category list, whatever shape
  /// either side sent it in.
  static String _categoryId(Map<String, dynamic> entry) =>
      readInt(entry, 'category_id')?.toString() ?? readNullableString(entry, 'category_id') ?? '';

  /// (Re)builds [_clock], anchored to today's local midnight, when the
  /// calendar day has moved since the last anchor. See the class doc block,
  /// "The clock".
  void _anchorClock() {
    final DateTime now = DateTime.now();
    final DateTime midnight = DateTime(now.year, now.month, now.day);

    if (_midnight == midnight) return;

    _clock = TickingGuideClock(anchor: now.difference(midnight).inMinutes);
    _midnight = midnight;
  }

  static Channel _applyChannelFavourite(Channel channel, bool favourite) =>
      channel.favourite == favourite ? channel : channel.toggleFavourite();

  static TitleItem _applyTitleFavourite(TitleItem title, bool favourite) =>
      title.favourite == favourite ? title : title.toggleFavourite();

  /// A copy of [title] with [progress] replaced. [TitleItem] carries no
  /// `copyWith` of its own beyond [TitleItem.toggleFavourite], and adding
  /// one is outside this step's Files list, so this reconstructs the value
  /// through its public constructor and public fields instead.
  static TitleItem _withProgress(TitleItem title, double progress) => TitleItem(
    kind: title.kind,
    name: title.name,
    category: title.category,
    year: title.year,
    posterUrl: title.posterUrl,
    backdropUrl: title.backdropUrl,
    minutes: title.minutes,
    rating: title.rating,
    genres: title.genres,
    synopsis: title.synopsis,
    facts: title.facts,
    cast: title.cast,
    episodes: title.episodes,
    progress: progress,
    favourite: title.favourite,
    providerId: title.providerId,
  );

  static bool _neverPlaying() => false;
}
