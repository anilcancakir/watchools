import 'package:magic/magic.dart';

import 'middleware/ensure_provider.dart';

/// The HTTP Kernel.
///
/// Register all middleware here, similar to Laravel's `app/Http/Kernel.php`.
///
/// ## Usage
///
/// This function is called automatically by `RouteServiceProvider.register()`.
/// You do not need to call it manually.
///
/// ## Global Middleware
///
/// Global middleware runs on EVERY route:
///
/// ```dart
/// Kernel.global([
///   () => LoggingMiddleware(),
/// ]);
/// ```
///
/// ## Route Middleware
///
/// Route middleware are named aliases you use in route definitions:
///
/// ```dart
/// Kernel.registerAll({
///   'auth': () => EnsureAuthenticated(),
///   'guest': () => RedirectIfAuthenticated(),
/// });
/// ```
void registerKernel() {
  // ---------------------------------------------------------------------------
  // Global Middleware
  // ---------------------------------------------------------------------------
  // None yet.

  // ---------------------------------------------------------------------------
  // Route Middleware
  // ---------------------------------------------------------------------------
  // `'provider'` guards every route that needs a real catalogue, so a
  // credential-less user lands on `/saglayici` rather than the fixture. See
  // `lib/app/middleware/ensure_provider.dart` and `lib/routes/app.dart`.
  Kernel.registerAll({'provider': () => EnsureProvider()});
}
