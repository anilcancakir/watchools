import 'package:magic/magic.dart';

import '../app/providers/app_service_provider.dart';
import '../app/providers/route_service_provider.dart';

/// Application configuration: identity, environment, and the service providers
/// Magic boots in order.
///
/// The provider closures carry an explicit [MagicApp] parameter type. The list
/// literal sits inside a `Map<String, dynamic>`, so nothing upstream constrains
/// the closure and `strict-inference` rejects a bare `(app) =>`.
Map<String, dynamic> get appConfig => {
  'app': {
    'name': env('APP_NAME', 'Watchools'),
    'title_separator': ' - ',
    'env': env('APP_ENV', 'production'),
    'debug': env('APP_DEBUG', false),
    // Explicit type argument: `env` has no default here to infer from, and the
    // encryption key is a string or it is missing.
    'key': env<String>('APP_KEY'),
    'providers': [
      (MagicApp app) => RouteServiceProvider(app),
      (MagicApp app) => CacheServiceProvider(app),
      (MagicApp app) => DatabaseServiceProvider(app),
      (MagicApp app) => LaunchServiceProvider(app),
      (MagicApp app) => LocalizationServiceProvider(app),
      (MagicApp app) => NetworkServiceProvider(app),
      (MagicApp app) => VaultServiceProvider(app),
      (MagicApp app) => BroadcastServiceProvider(app),
      (MagicApp app) => AppServiceProvider(app),
      (MagicApp app) => AuthServiceProvider(app),
    ],
  },
};
