import 'dart:async';

import 'package:magic/magic.dart';

import '../controllers/guide_controller.dart';
import '../controllers/library_controller.dart';
import '../controllers/playback_controller.dart';
import '../controllers/provider_setup_controller.dart';
import '../playback/mpv_playback_engine.dart';
import '../protocol/xtream/xtream_client.dart';
import '../provider/provider_session.dart';

/// Application Service Provider.
///
/// Use this provider to bind your own services to the IoC container and
/// to perform any bootstrap logic that requires other services to be ready.
class AppServiceProvider extends ServiceProvider {
  /// Binds this provider to [app], the container it registers services into.
  AppServiceProvider(super.app);

  @override
  void register() {
    // The line-up controller is a singleton so the four competing layouts share
    // one set of filters and favourites: comparing two layouts on different
    // data compares the data. Registered here rather than in `boot()` because
    // the router pre-builds during `Magic.init()`, and a view that resolves its
    // controller in `initState` needs the binding to exist by then.
    //
    // `Magic.put` rather than `app.singleton`: the container's string-keyed
    // bindings and the controller registry are separate maps, and
    // `MagicStatefulViewState` resolves through `Magic.find<T>()`, which reads
    // the registry.
    Magic.put(GuideController());
    Magic.put(LibraryController());

    // The provider session performs I/O in `start()`, which is why it is
    // bound here (synchronous) and started from `boot()` (async) rather than
    // built lazily on first read: nothing else in the app loads the stored
    // credential or the cached catalogue, so this is the one place that has
    // to.
    //
    // The connection gate, closed here and nowhere else. This is the whole
    // reason the predicate is injectable: the protocol layer must not depend on
    // the playback layer, and the playback layer must not ask the protocol
    // layer for permission, because a recovery load competing with a refresh
    // for the single connection slot is the deadlock the gate exists to
    // prevent. Only the composition root is allowed to know both.
    //
    // A closure, so the read happens at `refresh()` time rather than now. That
    // is what makes the binding order below irrelevant: `PlaybackController` is
    // bound after this line and does not exist yet.
    //
    // The predicate itself is `PlaybackController.holdsConnection` rather than
    // an expression written out here, and that is load-bearing: this directory
    // is outside the CI coverage denominator, so logic living in it is asserted
    // only by whatever a test file transcribes. Two transcriptions of this one
    // existed and had drifted apart from each other and from the original, so
    // deleting a clause of the real gate turned nothing red. One expression,
    // one place, and the test reads the same member the app does.
    Magic.put(ProviderSession(isPlaying: () => Magic.find<PlaybackController>().holdsConnection));

    // Bound after the session, and the order IS load-bearing rather than
    // tidiness, which an earlier version of this comment got wrong.
    // `PlaybackController`'s constructor subscribes to the session eagerly, and
    // it resolves one through `Magic.findOrPut`, which **creates** an instance
    // when none is registered (`magic.dart:262-267`). So binding the controller
    // first would build a second `ProviderSession` carrying the default
    // never-playing gate, and the controller would then listen to an orphan
    // while the app used the one bound above.
    //
    // This is the only place that knows HOW to build the engine, which is the
    // composition root doing its job: the controller takes a factory so it can
    // be bound here without touching a platform, and a test passes one that
    // returns the fake. The redactor is the one provider concept an engine may
    // hold, and passing the session's method rather than the credential is what
    // keeps `lib/app/playback/` free of Xtream entirely.
    //
    // A factory rather than an instance because `MpvPlaybackEngine`'s
    // constructor subscribes to the plugin's `EventChannel`. Building one here
    // threw `Binding has not yet been initialized` in every test that boots the
    // providers, the provider driver's own security test included.
    final ProviderSession session = Magic.find<ProviderSession>();

    Magic.put(PlaybackController(engine: () => MpvPlaybackEngine(redact: session.redactProviderSecrets)));

    // The other half of the same rule as the gate above, from the other
    // direction: a sign-out has to stop the core BEFORE the session forgets the
    // credential, because the core holds one of the account's connection slots
    // (measured limit: 1) from a URL carrying that credential in its path.
    // `ProviderSetupController` must not import the playback layer to do that,
    // so it takes the stop as a closure and this line is where the two layers
    // are allowed to meet.
    //
    // A closure again, so `PlaybackController` is resolved when a sign-out
    // happens rather than now, and `stop()` rather than a predicate plus a
    // stop: an expression written out here is asserted only by whatever a test
    // file transcribes, which is the drift the gate's own comment records.
    Magic.put(ProviderSetupController(stopPlayback: () => Magic.find<PlaybackController>().stop()));

    // Provider traffic gets its own driver, and this is a security boundary
    // rather than tidiness. The shared `network` driver carries magic's
    // `AuthInterceptor` (added in `magic/lib/src/auth/auth_service_provider.
    // dart`), which attaches the watchools bearer token to every request with
    // no host, scheme or origin test, and reads a 401 as a signal to refresh
    // the token, re-attach the fresh one and replay the request. Aimed at a
    // stranger's IPTV panel over plaintext HTTP that hands our token to a
    // third party twice and logs the user out when the refresh fails. There is
    // no config route to a second driver: `NetworkServiceProvider` reads
    // `network.drivers.api` and binds the single `network` key, so this
    // registration is the route.
    //
    // Empty base URL because the client addresses one absolute panel URL, and
    // `defaultHeaders` left at its empty default because `Options(headers:)`
    // merges over `BaseOptions.headers` rather than replacing them: a header
    // declared here would ship on provider traffic no matter what the client
    // sends, and the client sends exactly `User-Agent`. No interceptor is
    // added, now or later.
    app.singleton(XtreamClient.driverKey, () {
      final DioNetworkDriver driver = DioNetworkDriver(baseUrl: '');

      // A 3xx off a panel is a fault to surface rather than a hop to take. The
      // target host is the panel's choice, and a stream URL carries the user's
      // credentials in its path.
      driver.configureDriver((dio) => dio.options.followRedirects = false);

      return driver;
    });
  }

  @override
  Future<void> boot() async {
    // Perform async bootstrap logic here.
    //
    // IMPORTANT: Call setUserFactory() so Auth.user<T>() returns your model:
    //   Auth.manager.setUserFactory((data) => User.fromMap(data));

    // Two phases, and the split is why the app paints promptly. `start()` is
    // local only (schema, vault, cached catalogue) and is awaited, so the
    // first frame has a catalogue to render. `refresh()` is the network half
    // and is NOT awaited: `boot()` runs inside `Magic.init()`, which `main()`
    // awaits before `runApp()`, and a real refresh is 41,000 rows plus up to
    // twenty EPG round trips over an account whose measured connection limit
    // is one. Awaiting it here would hold a blank window open for all of it.
    //
    // The future is deliberately not caught. A transport failure is already a
    // value rather than a throw (`statusCode: 0` classifies as
    // `ProviderFault.unreachable`), so anything that does throw out of here is
    // a programming or disk error, and `CLAUDE.md` says let that propagate
    // rather than swallow it.
    final ProviderSession session = Magic.find<ProviderSession>();
    await session.start();
    unawaited(session.refresh());
  }
}
