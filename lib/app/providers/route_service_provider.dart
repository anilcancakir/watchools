import 'package:magic/magic.dart';

import '../../routes/app.dart';
import '../kernel.dart';

/// Route Service Provider.
///
/// Registers the HTTP kernel and application routes.
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
  }
}
