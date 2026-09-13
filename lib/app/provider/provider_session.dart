import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../models/background_playback.dart';
import '../models/channel.dart';
import '../models/programme.dart';
import '../models/provider_fault.dart';
import '../models/title_item.dart';
import '../network/resolver_setting.dart';
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

  /// Where a loaded credential's resolver choice goes.
  ///
  /// An injected sink rather than a `HostResolver` this class holds, the same
  /// shape and for the same reason as [_isPlaying]: the composition root is what
  /// knows there is exactly ONE resolver in the process, and it has to stay one,
  /// because the process-wide `HttpOverrides` and the provider settings screen
  /// read the same instance's cache. Pushing a setting rather than handing over
  /// the object is what keeps a second one from ever being constructible here.
  ///
  /// Defaults to doing nothing, which is the fixture and test path.
  final void Function(ResolverSetting) _applyResolverSetting;

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
    void Function(ResolverSetting)? applyResolverSetting,
    this.epgFetchLimit = 20,
  }) : _isPlaying = isPlaying ?? _neverPlaying,
       _applyResolverSetting = applyResolverSetting ?? _ignoreResolverSetting,
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

  /// The panel host this session addresses and the resolver the user chose for
  /// it, or null before a credential is loaded.
  ///
  /// Public where the credential is not, for the reason [playbackUserAgent] is:
  /// neither field is a secret, and the process-wide `HttpOverrides` cannot do
  /// its job without both. The host is what it matches a request against, so
  /// that it pins the user's own panel and leaves every other host in the
  /// process alone; the setting is what `HostResolver` escalates to.
  ///
  /// The host is derived from [XtreamCredentials.baseUrl] rather than stored
  /// beside it: the credential's constructor has already rejected a panel URL
  /// with no scheme or no host, so there is exactly one spelling to read.
  ({String host, ResolverSetting setting})? get providerResolution {
    final XtreamCredentials? credentials = _credentials;

    if (credentials == null) return null;

    return (host: Uri.parse(credentials.baseUrl).host, setting: ResolverSetting.parse(credentials.resolver));
  }

  /// What a playing stream does when the app leaves the foreground, read from
  /// the loaded credential, or [BackgroundPlayback.stop] before one is loaded.
  ///
  /// Public where the credential is not, for the reason [providerResolution]
  /// is: the field is not a secret and the playback engine has to read it.
  ///
  /// Derived here on every read rather than cached, which is what makes
  /// [signOut] (nulling [_credentials]) return this to [BackgroundPlayback.stop]
  /// with no push of any kind: unlike [providerResolution], there is no
  /// `HostResolver`-shaped cache elsewhere in the process for this value to go
  /// stale in.
  BackgroundPlayback get backgroundPlayback => BackgroundPlayback.parse(_credentials?.backgroundPlayback);

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
    _pushResolverSetting();

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

  /// Accepts [credentials] as this session's provider at runtime, replacing
  /// whatever was loaded before. **Local only, like [start]: this does not
  /// touch the network.**
  ///
  /// 1. Persist to `Vault`, so the credential survives the next launch.
  /// 2. Swap in a fresh [XtreamClient]: the old one still addresses the
  ///    previous panel, and nothing here may keep using it.
  /// 3. Drop [_account] and [_fault]. Neither one has been established
  ///    against the new panel, and carrying the old panel's account into
  ///    [classifyProviderFault] would compare a denial from the new panel
  ///    against a handshake from the old one.
  /// 4. Push the new credential's resolver choice into the one registered
  ///    `HostResolver`. Without this a user who changes their resolver keeps
  ///    resolving through the previous one until the process restarts, and the
  ///    cache would still hold an address looked up for the previous panel.
  /// 5. Restore the cached catalogue for the new [CatalogueStore.accountKey],
  ///    the same shape [start] uses, so a screen has something to render
  ///    before the caller decides to [refresh].
  ///
  /// **Does not call [refresh] and does not call [start].** The connection
  /// gate exists so a network round trip only ever happens on the caller's
  /// decision, and `start()` also runs [CatalogueStore.migrate], which is
  /// schema work this method has no reason to repeat. The caller that decides
  /// is [ProviderSetupController.submit], and it has to: a first credential's
  /// account key has never existed, so step 4 restores an empty catalogue and
  /// the screen the user lands on would say there are no results to a user who
  /// has just signed in and searched for nothing.
  ///
  /// [_inFlight] is dropped rather than awaited, which is what makes that
  /// caller's refresh reach the network at all. A refresh already running
  /// belongs to the previous credential and stops writing the moment it sees
  /// this one, so handing its future back to the next `refresh()` caller, as
  /// the re-entry guard otherwise would, would report a pass that fetched
  /// nothing for this account.
  Future<void> adopt(XtreamCredentials credentials) async {
    await credentials.save();

    _credentials = credentials;
    _client = XtreamClient(credentials);
    _account = null;
    _fault = null;
    _inFlight = null;

    _pushResolverSetting();

    final String account = CatalogueStore.accountKey(credentials);
    _channels = _store.channelsFor(account);
    _titles = _store.titlesFor(account);

    notifyListeners();
  }

  /// Changes what a playing stream does when the app leaves the foreground,
  /// for the currently loaded credential. A no-op with no credential loaded:
  /// there is no record to write it onto.
  ///
  /// **Deliberately not [adopt].** The only caller of [adopt] is
  /// [ProviderSetupController.submit], reached after a live panel handshake
  /// succeeds, and the three credential fields start empty on every open of
  /// the settings screen. Routing this setting through it would mean a user
  /// can only change what happens on backgrounding by retyping their base
  /// URL, username and password and having a reachable, unexpired panel at
  /// that moment, re-sending their password over what is usually plaintext
  /// HTTP. A user whose subscription had lapsed could not turn off the thing
  /// holding their connection.
  ///
  /// No handshake, no [adopt], no [refresh], no resolver push: none of them
  /// depends on this field, and [adopt]'s own doc block lists five things it
  /// does that this write has no business repeating.
  /// The session can move under the `save()` below, and this is the only
  /// writer here that has already touched the vault by the time it notices.
  /// [signOut] deletes the key and nulls the record; [adopt] writes a different
  /// account's record and assigns it. Either one landing first leaves the
  /// Keychain holding what this call wrote rather than what the session now
  /// believes, so the guard is followed by a repair rather than a bare return.
  ///
  /// Both orderings were reproduced before this existed
  /// (`provider_session_test.dart`, the two cases naming "inside the write",
  /// through `StallingVaultService`). Unguarded, a sign-out arriving here left
  /// `hasCredentials` true with the user's password written back to the device
  /// behind the delete, and an adopt arriving here left the session on the
  /// PREVIOUS account, which is the one the next launch would have signed the
  /// user in as.
  ///
  /// The `identical` check is this file's existing idiom for a session that
  /// moved under an await (`:618`, `:669`, `:807`, `:853`, `:892`); what is new
  /// is that those five can simply stop and this one has a write to undo.
  Future<void> setBackgroundPlayback(BackgroundPlayback choice) async {
    final XtreamCredentials? credentials = _credentials;
    if (credentials == null) return;

    final XtreamCredentials updated = credentials.withBackgroundPlayback(choice.storedValue);
    await updated.save();

    if (!identical(_credentials, credentials)) {
      final XtreamCredentials? current = _credentials;

      // Make the vault agree with the session again. Null means a sign-out
      // won, so the key this call re-created goes; anything else means an
      // adopt won, so its record is written back over the stale one.
      if (current == null) {
        await XtreamCredentials.clear();
      } else {
        await current.save();
      }

      return;
    }

    _credentials = updated;
    notifyListeners();
  }

  /// Hands the loaded credential's resolver choice to the one `HostResolver`
  /// the composition root registered.
  ///
  /// Called from the two places a credential arrives, and both are load-bearing.
  /// [adopt] is where a user who just changed their resolver would otherwise
  /// keep resolving through the previous one for the life of the process.
  /// [start] is where a STORED choice first becomes known at all: the
  /// composition root builds the resolver synchronously in `register()`, long
  /// before any vault read, so without this call a restart would silently drop
  /// the user back to the system resolver.
  ///
  /// [ResolverSetting.system] with no credential, which is what the fixture path
  /// and a signed-out session are entitled to.
  void _pushResolverSetting() => _applyResolverSetting(providerResolution?.setting ?? ResolverSetting.system);

  /// Forgets the current provider: the vault entry, the handshake, the
  /// clock, and the held catalogue.
  ///
  /// **Order matters twice here.**
  ///
  /// [XtreamCredentials.clear] runs FIRST, because it is a `Vault.delete`
  /// and every `Vault` operation can throw [MagicVaultException] (see
  /// [_loadCredentials]'s own read arm): clearing before touching any field
  /// means a failed delete leaves this session exactly as it was, rather
  /// than having already discarded the credential it could not remove from
  /// storage.
  ///
  /// [_clock] is disposed before it is nulled, not after: a
  /// [TickingGuideClock] re-arms its timer unconditionally
  /// (`guide_clock.dart:104-107`), so a detached instance keeps firing for
  /// the life of the process if it is dropped without disposing first.
  ///
  /// **`catalogue_channels` and `catalogue_titles` are left untouched.**
  /// [CatalogueStore.accountKey] excludes the password on purpose
  /// (`catalogue_store.dart:118-121`), so a user who signs out to correct a
  /// rotated password returns under the same key, and `replaceChannels`
  /// reads the starred rows back before its own `DELETE`
  /// (`catalogue_store.dart:182-184`). Deleting the rows here would throw
  /// away every favourite and every watch progress in exactly the situation
  /// most likely to cause a sign-out.
  Future<void> signOut() async {
    await XtreamCredentials.clear();

    _credentials = null;
    _client = null;
    _account = null;
    _fault = null;

    // Dropped for the reason [adopt] drops it, and it matters here even
    // though nothing signed out will refresh: the future left standing would
    // be handed to the next `refresh()` after the NEXT credential is adopted,
    // and it belongs to the account this call is leaving.
    _inFlight = null;

    // Back to the system resolver, and the point is the cache rather than the
    // choice. Nothing pins anything once [providerResolution] is null, so the
    // setting alone is inert here; what this drops is the address resolved for
    // the panel the user just left, which is exactly what every other line in
    // this method is doing for its own piece of that account's state.
    _pushResolverSetting();

    _clock?.dispose();
    _clock = null;
    _midnight = null;

    _channels = const <Channel>[];
    _titles = const <TitleItem>[];

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
    } on MagicVaultException {
      // The keychain read itself failed rather than the stored payload
      // parsing badly: `MagicVaultService.get` wraps every `PlatformException`
      // as this exception on reads (`magic_vault_service.dart:48-54`), and the
      // darwin plugin turns every non-success `OSStatus` into one. `start()`
      // is awaited inside `Magic.init()`, which `main()` awaits before
      // `runApp()`, so letting this propagate boots the app to nothing.
      // `unreachable`, not `expired`: the credential itself is not known bad,
      // the store that holds it is, and `expired` is the one fault whose
      // panel withholds the retry and sends the user to settings instead.
      _fault = ProviderFault.unreachable;

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
  ///
  /// The completion handler clears [_inFlight] only if it is still this pass's
  /// own future. [adopt] and [signOut] drop it while a pass may still be
  /// running, so a plain `_inFlight = null` here would let a finishing old
  /// pass clear the new one's guard and admit a third overlapping refresh.
  Future<void> refresh() {
    final Future<void>? running = _inFlight;
    if (running != null) return running;

    late final Future<void> started;
    started = _refresh().whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    });
    _inFlight = started;

    return started;
  }

  Future<void> _refresh() async {
    if (_isPlaying()) return;

    final XtreamCredentials? credentials = _credentials;
    final XtreamClient? client = _client;
    if (credentials == null || client == null) return;

    final XtreamResponse<Map<String, dynamic>> handshake = await client.handshake();

    // Nothing below this line is true of the session any more if the
    // credential moved while the handshake was out, and everything below it
    // writes to the session: the fault, the account, the clock. A sign-out in
    // that window would otherwise leave a fault and an account standing on a
    // session with no credential, which `GuideController` and
    // `LibraryController` both read, and `_anchorClock` would build a fresh
    // `TickingGuideClock` on the session that has just disposed and nulled
    // one, leaving a one-minute timer nothing will ever dispose.
    if (!identical(_credentials, credentials)) return;

    final XtreamAccount? parsed = handshake.data == null ? null : XtreamAccount.fromHandshake(handshake.data!);

    _fault = classifyProviderFault(account: parsed ?? _account, statusCode: handshake.statusCode, body: handshake.body);
    if (parsed != null) _account = parsed;

    if (_fault != null) {
      notifyListeners();

      return;
    }

    _anchorClock();

    // Read here, where `_anchorClock()` has just assigned them and no await
    // stands between, then passed down rather than read again. Both fields are
    // nulled by `signOut`, and every read of one through `!` below an await is
    // a crash into the future `boot()` fires unawaited; taking them once at
    // the only point they are certainly present is what removes the window
    // rather than narrowing it.
    final GuideClock clock = _clock!;
    final DateTime referenceMidnight = _midnight!;

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
    await _refreshChannels(
      client: client,
      account: account,
      credentials: credentials,
      clock: clock,
      referenceMidnight: referenceMidnight,
    );

    // The credential is re-checked here beside the playback gate, and for the
    // adjacent reason: the VOD half is four more requests, the largest half by
    // request count, and after a sign-out or a new credential every one of
    // them is spent on an account nobody is looking at.
    if (_isPlaying() || !identical(_credentials, credentials)) {
      notifyListeners();

      return;
    }

    await _refreshTitles(client: client, account: account, credentials: credentials);

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
  ///
  /// [clock] and [referenceMidnight] arrive as arguments rather than being
  /// read off the fields, and [credentials] arrives so the write-back can name
  /// which credential this pass was for. Every one of the three would
  /// otherwise be read across one of the two awaits below, and
  /// `client.liveStreams()` is the longest response in a refresh: 2,976 rows
  /// on a real subscription. A sign-out inside it nulls the clock and the
  /// midnight, and a `!` read at that point crashes into the future `boot()`
  /// fires unawaited. Two earlier attempts narrowed that window rather than
  /// closing it, first by extending the EPG loop's own break, then by
  /// capturing before the loop but still after these awaits.
  Future<void> _refreshChannels({
    required XtreamClient client,
    required String account,
    required XtreamCredentials credentials,
    required GuideClock clock,
    required DateTime referenceMidnight,
  }) async {
    final Map<int, bool> previousFavourites = <int, bool>{
      for (final Channel channel in _channels)
        if (channel.streamId != null) channel.streamId!: channel.favourite,
    };

    final Map<String, String> categoryNames = await _categoryNames(client.liveCategories);
    final List<Map<String, dynamic>> rawChannels = (await client.liveStreams()).data ?? const <Map<String, dynamic>>[];

    final List<Channel> built = <Channel>[
      for (final Map<String, dynamic> entry in rawChannels)
        Channel.fromXtream(entry, categoryName: categoryNames[_categoryId(entry)] ?? '', clock: clock),
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
      // The second clause is a sign-out or a new credential landing mid-loop.
      // The schedule build below can no longer crash on it, since
      // [referenceMidnight] is an argument, so this is now about work rather
      // than safety: up to [epgFetchLimit] further round trips against an
      // account nobody is looking at, on a subscription whose measured
      // connection limit is 1.
      if (_isPlaying() || !identical(_credentials, credentials)) break;

      final int streamId = built[index].streamId!;

      final List<Map<String, dynamic>> listings =
          (await client.shortEpg(streamId)).data ?? const <Map<String, dynamic>>[];
      final List<Programme> schedule = <Programme>[
        for (final Map<String, dynamic> listing in listings)
          if (Programme.fromXtream(listing, referenceMidnight: referenceMidnight) case final Programme programme)
            programme,
      ];
      if (schedule.isEmpty) continue;

      built[index] = Channel.fromXtream(
        rawChannels[index],
        categoryName: built[index].group,
        clock: clock,
        schedule: schedule,
      );
    }

    final List<Channel> withFavourites = <Channel>[
      for (final Channel channel in built)
        _applyChannelFavourite(channel, previousFavourites[channel.streamId] ?? false),
    ];

    // Abandoned entirely, store included, if the session's credential moved
    // while the fetch was in flight. `boot()` fires `refresh()` unawaited at
    // cold start, so a user who signs out or submits a different credential a
    // few seconds in leaves a batch of requests still running against the
    // account they just left.
    //
    // Identity rather than a null check, which is the case a null check misses
    // and the sharper of the two: submitting a second credential on
    // `/saglayici` within those seconds leaves `_credentials` non-null, so a
    // null check passes and `/` then shows the PREVIOUS account's channels
    // under the new one, none of them playable because `adopt` nulled
    // `_account`.
    //
    // BEFORE the write, not after it, and that placement is what makes
    // [adopt] safe to drop [_inFlight]: `replaceChannels` runs a
    // `DB.transaction`, which issues a literal `BEGIN TRANSACTION` on the one
    // shared connection, so an abandoned pass reaching it while the new pass
    // is inside its own nests a `BEGIN`, sqlite3 rejects it, and the inner
    // `rollback()` discards the new account's rows as well. The fetch's work
    // is lost, which is the cheaper of the two costs by a wide margin.
    if (!identical(_credentials, credentials)) return;

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
  Future<void> _refreshTitles({
    required XtreamClient client,
    required String account,
    required XtreamCredentials credentials,
  }) async {
    final List<TitleItem> built = <TitleItem>[
      ...await _titlesOf(kind: TitleKind.movie, categories: client.vodCategories, entries: client.vodStreams),
      ...await _titlesOf(kind: TitleKind.series, categories: client.seriesCategories, entries: client.series),
    ];

    // Same guard as the channel half, in the same position and for the same
    // two reasons: the previous account's catalogue must not be written back
    // over the new one, and `replaceTitles` is the other `DB.transaction` an
    // abandoned pass could nest inside the new pass's.
    if (!identical(_credentials, credentials)) return;

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

  static void _ignoreResolverSetting(ResolverSetting setting) {}
}
