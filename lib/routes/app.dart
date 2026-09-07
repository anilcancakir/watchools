import 'package:magic/magic.dart';

import '../resources/views/guide_view.dart';

/// Application Route Definitions.
///
/// Register all application routes here. This function is called by
/// [RouteServiceProvider.boot()] during the Magic bootstrap lifecycle.
///
/// See also: `lib/app/kernel.dart` for middleware registration.
void registerAppRoutes() {
  MagicRoute.page('/', () => const GuideView()).title('Rehber');
}
