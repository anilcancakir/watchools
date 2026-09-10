import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/programme.dart';
import '../models/provider_fault.dart';
import '../models/title_item.dart';
import '../protocol/xtream/xtream_account.dart';
import '../protocol/xtream/xtream_client.dart';
import '../protocol/xtream/xtream_credentials.dart';
import '../protocol/xtream/xtream_json.dart';
import '../protocol/xtream/xtream_stream_url.dart';
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
/// The gate is consulted at the door **and twice more inside**, and the
/// difference is the case that happens on every launch rather than an edge:
/// `AppServiceProvider.boot()` fires `refresh()` unawaited at cold start, so a
/// user who taps a channel a few seconds in is playing while a handshake, four
/// list fetches and up to [epgFetchLimit] sequential EPG calls are still in
/// flight. A door-only gate says nothing about a refresh already running.
/// The two inner checks sit between the channel and the VOD halves and between
/// EPG round trips, never inside one: each half ends in a `replace*` that runs
/// a `DB.transaction`, and abandoning mid-transaction would leave the
/// catalogue half written.
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
/// ## Why this notifies
///
/// A refresh lands **after** the first frame, by design: `boot()` awaits only
/// [start] and fires [refresh] unawaited, so the app paints the cached
/// catalogue rather than a blank window. That makes notification load-bearing
/// rather than convenient. A consumer that polled this object from a getter
/// would only ever observe it during a build, and the value it is waiting for
/// arrives between builds, so the arriving catalogue, the anchored clock and
/// the [ProviderFault] would all sit invisible until an unrelated gesture
/// happened to rebuild the screen.
class ProviderSession extends ChangeNotifier {
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

  /// What [start] falls back to when `Vault` holds no credential.
  ///
  /// A seam for the same reason [_isPlaying] is one: the real default reads
  /// compile-time defines, a `flutter test` run has none, and without this
  /// there is no way to exercise the fallback at all. A test passes a closure
  /// returning a credential it built; the app passes nothing.
  final XtreamCredentials? Function() _developmentCredential;

  /// Whether a caller may not invoke [refresh] right now.
  ///
  /// An injectable predicate rather than a direct read of the engine, and it
  /// stays one now that `PlaybackEngine` exists: this layer must not depend on
  /// the playback layer, and the playback layer must not ask this one for
  /// permission, because a recovery load competing with a refresh for the
  /// single connection slot is the deadlock the predicate exists to prevent.
  /// The composition root is what closes the loop, so neither side imports the
  /// other. Defaults to "not playing", which is what the fixture path wants.
  ///
  /// What was measured, and what was not, because the gate's strength should
  /// not be read as stronger than its evidence. The measured account's
  /// `max_connections` is **1**, and a second concurrent stream killed the
  /// first at 5.79 s (`.ac/research/player-layer.md:224-230`) with a `.ts`
  /// request on **both** sides. Whether a `player_api.php` call occupies the
  /// slot at all is **unmeasured**, and the mock panel never enforces the cap
  /// (it reports `active_cons` and admits the request anyway,
  /// `tool/xtream-mock/server.mjs:171`), so nothing here has been proven to be
  /// necessary. The gate stays because it is cheap and errs in the direction
  /// that cannot cost a viewer their stream.
  ///
  /// [refresh] consults this at its door **and twice more inside**, which is
  /// the correction that matters: the door alone stops a refresh starting
  /// during playback and does nothing about one already running, and the
  /// cold-start refresh racing the user's first tap is the case that happens on
  /// every launch.
  final bool Function() _isPlaying;

  XtreamCredentials? _credentials;
  XtreamClient? _client;
  XtreamAccount? _account;
  ProviderFault? _fault;
  GuideClock? _clock;
  DateTime? _midnight;
  List<Channel> _channels = const <Channel>[];
  List<TitleItem> _titles = const <TitleItem>[];

  /// The refresh currently in flight, or null. See [refresh].
  Future<void>? _inFlight;

  /// Creates a session. [store] defaults to a fresh, stateless
  /// [CatalogueStore]; [isPlaying] defaults to "never playing".
  ProviderSession({
    this._store = const CatalogueStore(),
    bool Function()? isPlaying,
    XtreamCredentials? Function()? developmentCredential,
    this.epgFetchLimit = 20,
  }) : _isPlaying = isPlaying ?? _neverPlaying,
       _developmentCredential = developmentCredential ?? XtreamCredentials.fromEnvironment;

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

  /// [text] with every spelling of this provider's secrets replaced.
  ///
  /// The session's answer to "who can clean a log line", and the reason the
  /// playback engine needs no credential of its own: it takes this method as a
  /// function and cannot tell what is behind it. mpv forwards FFmpeg's log
  /// verbatim, a stream URL carries the password in its path, and that channel
  /// is the only signal a subscription token is lapsing, so it has to be
  /// cleaned rather than switched off.
  ///
  /// Returns [text] unchanged when no credential is loaded. That is not a
  /// swallowed failure: with no credential there is no secret in the text to
  /// find, and the fixture path never builds a URL at all.
  String redactProviderSecrets(String text) => _credentials?.redact(text) ?? text;

  /// The `User-Agent` this provider is addressed with, or null before a
  /// credential is loaded.
  ///
  /// Public where the credential is not, because it is not a secret and the
  /// playback engine has to send it: resellers key access control to the header,
  /// and `CLAUDE.md` records that ExoPlayer's lookup is case sensitive, so
  /// whatever builds the request must spell the name exactly `User-Agent`.
  String? get playbackUserAgent => _credentials?.userAgent;

  /// The playable URL for [channel], or null when this session cannot produce
  /// one.
  ///
  /// Derived here rather than by handing the credential out, and that is a
  /// security decision rather than a convenience. The URL carries the
  /// subscription password in its **path**, so every caller that can read
  /// `XtreamCredentials` is another place the secret can reach a log, and the
  /// point of this shape is that the playback layer receives a `Uri` and never
  /// sees the fields it was built from. [redactProviderSecrets] remains the
  /// only sanctioned way to name one of these in a diagnostic.
  ///
  /// Null in four cases, which callers must treat alike because none of them is
  /// a fault: no credential is loaded, no handshake has answered yet, the
  /// channel carries no `streamId` (a fixture-built channel has none by
  /// design), or no container satisfies both the account and [channelFormats].
  /// The last of those is `XtreamStreamUrl.live`'s own answer and the reason it
  /// returns null rather than guessing an extension.
  ///
  /// [channelFormats] is what THIS channel serves, from its live entry.
  /// `Channel` carries no format field, so the empty default is the ordinary
  /// case (any channel read back from the store) and means "unknown": the
  /// account's list then decides alone.
  Uri? streamUrlFor(Channel channel, {List<String> channelFormats = const <String>[]}) {
    final XtreamCredentials? credentials = _credentials;
    final XtreamAccount? account = _account;

    if (credentials == null || account == null) return null;

    return XtreamStreamUrl.live(
      credentials: credentials,
      account: account,
      channel: channel,
      channelFormats: channelFormats,
    );
  }

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
  ///
  /// An unreadable stored payload becomes [ProviderFault.expired] rather than
  /// a throw. `XtreamCredentials.load` throws [FormatException] on a payload
  /// that is not this record (an older build's shape, a partial write), and
  /// this method is awaited inside `Magic.init()`, which `main()` awaits
  /// before `runApp()`: letting it propagate aborts the boot with no UI at
  /// all, and with no onboarding screen the user has no way to clear the bad
  /// value. `expired` is the honest reading, because an unusable credential is
  /// exactly a credential that needs replacing, and it is the fault whose
  /// button goes to the provider settings.
  Future<void> start() async {
    _store.migrate();

    final XtreamCredentials? credentials = await _loadCredentials();
    _credentials = credentials;

    if (credentials == null) {
      notifyListeners();

      return;
    }

    _client = XtreamClient(credentials);

    final String account = CatalogueStore.accountKey(credentials);
    _channels = _store.channelsFor(account);
    _titles = _store.titlesFor(account);

    notifyListeners();
  }

  /// The stored credential, or null when there is none or it cannot be read.
  ///
  /// Sets [fault] on an unreadable payload rather than swallowing it: the
  /// exception is handled deliberately, into the vocabulary the UI already
  /// renders, which is the opposite of a silent catch.
  Future<XtreamCredentials?> _loadCredentials() async {
    try {
      final XtreamCredentials? stored = await XtreamCredentials.load();

      if (stored != null) return stored;

      // The compile-time credential, and only in a debug build. It is the
      // development way in and currently the ONLY way in on macOS, where
      // `Vault` is the Keychain and a sandboxed build cannot write to it at
      // all (OSStatus -34018); see [XtreamCredentials.fromEnvironment].
      //
      // After the vault rather than before it, so a real stored credential
      // always wins and a define left in a shell profile can never silently
      // replace the one a user configured. `kDebugMode` on top of that,
      // because a release build has no business reading one even if somebody
      // passes it.
      return kDebugMode ? _developmentCredential() : null;
    } on FormatException {
      _fault = ProviderFault.expired;

      return null;
    }
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
  ///
  /// **Not re-entrant, and it enforces that itself.** A second call while one
  /// is in flight returns the first one's future rather than starting another,
  /// because `DB.transaction` issues a literal `BEGIN TRANSACTION` on the one
  /// shared connection (`magic/lib/src/facades/db.dart:183-193`): two
  /// overlapping refreshes nest a `BEGIN`, sqlite3 rejects it, and the inner
  /// `rollback()` then discards the outer transaction's rows as well. Reachable
  /// by double-tapping the fault panel's retry, which cannot repaint into a
  /// disabled state because the controller's `reload()` only notifies after
  /// this returns.
  Future<void> refresh() {
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<void> _refresh() async {
    if (_isPlaying()) return;

    final XtreamCredentials? credentials = _credentials;
    final XtreamClient? client = _client;
    if (credentials == null || client == null) return;

    final XtreamResponse<Map<String, dynamic>> handshake = await client.handshake();
    final XtreamAccount? parsed = handshake.data == null ? null : XtreamAccount.fromHandshake(handshake.data!);

    _fault = classifyProviderFault(account: parsed ?? _account, statusCode: handshake.statusCode, body: handshake.body);
    if (parsed != null) _account = parsed;

    if (_fault != null) {
      notifyListeners();

      return;
    }

    _anchorClock();

    final String account = CatalogueStore.accountKey(credentials);

    // Re-checked between the two halves, not only at the door. The gate at the
    // top of this method stops a refresh from STARTING during playback and
    // does nothing about one already running, and that is the case which
    // happens on every launch: `AppServiceProvider.boot()` fires
    // `unawaited(session.refresh())` at cold start, so a user who taps a
    // channel five seconds in plays straight through an in-flight batch of a
    // handshake, four list fetches and up to [epgFetchLimit] sequential EPG
    // calls, against an account whose measured `max_connections` is 1.
    //
    // Between the halves rather than inside one: each half ends in a
    // `replace*` that runs a `DB.transaction`, and abandoning mid-transaction
    // would leave the catalogue half written. The EPG loop has its own check
    // for the same reason, placed between round trips.
    await _refreshChannels(client: client, account: account);

    if (_isPlaying()) {
      notifyListeners();

      return;
    }

    await _refreshTitles(client: client, account: account);

    notifyListeners();
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

    notifyListeners();
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

    notifyListeners();
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

    notifyListeners();
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

    // Filter to candidates BEFORE applying the bound, which is the whole
    // difference between this pass working and not. Bounding an index over the
    // unfiltered line-up spends a slot on every channel it then skips, and
    // **91% of a real provider's channels carry no `epg_channel_id` at all**
    // (`.ac/research/player-layer.md:286`), so a limit of twenty over 2,976
    // entries buys about two schedules instead of twenty. Two of the four
    // screens are built around a schedule, so that is the difference between
    // this step delivering what it exists for and delivering nothing
    // measurable.
    final List<int> candidates = <int>[
      for (int index = 0; index < built.length; index++)
        if (readNullableString(rawChannels[index], 'epg_channel_id') != null && built[index].streamId != null) index,
    ];

    for (final int index in candidates.take(epgFetchLimit)) {
      // The longest stretch of requests in the app: up to [epgFetchLimit]
      // sequential round trips, one per channel. Abandoning it mid-way is safe
      // and the schedules already merged are kept, because the `replaceChannels`
      // below writes whatever `built` holds at that point; a channel whose EPG
      // was not reached restores with an empty schedule, which is the ordinary
      // state of 91 percent of them anyway.
      if (_isPlaying()) break;

      final int streamId = built[index].streamId!;

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

    // Dispose the outgoing clock before dropping the reference.
    // `TickingGuideClock._scheduleNext` re-arms unconditionally
    // (`guide_clock.dart:104-107`), so a detached instance keeps a live
    // one-minute timer for the life of the process: one leaked timer per
    // calendar day the app stays open. `removeListener` stays safe after
    // dispose, so `GuideController._followSessionClock` can still detach.
    _clock?.dispose();

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
