import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:magic/magic.dart';
import 'package:magic_devtools/preview.dart';

import '../../_previews.g.dart';
import '../../routes/app.dart';
import '../kernel.dart';

/// Route Service Provider.
///
/// Registers the HTTP kernel, the application routes and, outside release, the
/// component preview catalogue.
class RouteServiceProvider extends ServiceProvider {
  /// Binds this provider to [app], the container the router is registered on.
  RouteServiceProvider(super.app);

  @override
  void register() {
    // Register middleware kernel — runs synchronously during bootstrap.
    registerKernel();
  }

  @override
  Future<void> boot() async {
    // Register application route definitions.
    registerAppRoutes();

    // The preview catalogue, which was generated and never reachable.
    //
    // `previews:refresh` has been writing `lib/_previews.g.dart` since the
    // component folders existed and nothing consumed it, so `/preview` fell
    // through to `/` and rendered the live screen: the route resolved, the page
    // title said `Canlı`, and `dusk:navigate --route /preview` reported success
    // over the top of it. Every component preview in this app has been
    // unreachable for that whole time.
    //
    // `MagicDevtools.installPre` and `installPost` in `main.dart` do NOT do
    // this. They wire the devtools overlay and the perf integration; the
    // catalogue is a separate, explicit two-call registration.
    //
    // It has to be here rather than anywhere later. `MagicRouter` locks its
    // table the first time `routerConfig` is read, which is when `MaterialApp`
    // builds, and `addRoute` throws after that. A provider `boot()` runs before
    // it, which is why the application routes above work from the same place.
    //
    // Guarded, even though `registerRoutes` guards itself on `kReleaseMode`.
    // `register` parks the entries in a static, and `_previews.g.dart` imports
    // every preview file, so without this the release tree-shaker cannot prove
    // the chain unreachable. Same reason `main.dart` guards the devtools calls.
    if (!kReleaseMode) {
      MagicPreview.register(previewEntries());
      MagicPreview.registerRoutes();
    }
  }
}
