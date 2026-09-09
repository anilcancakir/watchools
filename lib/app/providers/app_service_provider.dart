import 'dart:async';

import 'package:magic/magic.dart';

import '../controllers/guide_controller.dart';
import '../controllers/library_controller.dart';
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
    Magic.put(ProviderSession());

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
