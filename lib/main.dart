import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluttersdk_dusk/dusk.dart';
import 'package:fluttersdk_telescope/telescope.dart';
import 'package:magic/magic.dart';
import 'package:magic_devtools/dusk.dart';
import 'package:magic_devtools/telescope.dart';

import 'config/app.dart';
import 'config/auth.dart';
import 'config/broadcasting.dart';
import 'config/cache.dart';
import 'config/database.dart';
import 'config/logging.dart';
import 'config/network.dart';
import 'config/routing.dart';
import 'config/view.dart';
import 'config/watchools_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    DuskPlugin.install();
  }
  if (kDebugMode) {
    TelescopePlugin.install();
    TelescopePlugin.registerWatcher(ExceptionWatcher());
    TelescopePlugin.registerWatcher(DumpWatcher());
  }
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => routingConfig,
      () => viewConfig,
      () => authConfig,
      () => databaseConfig,
      () => networkConfig,
      () => cacheConfig,
      () => loggingConfig,
      () => broadcastingConfig,
    ],
  );
  if (kDebugMode) {
    MagicTelescopeIntegration.install();
  }
  if (kDebugMode) {
    MagicDuskIntegration.install();
  }

  // Dark-first, not dark-only: the light palette exists and clears AA, but
  // nothing exposes a switch yet, so pinning the mode keeps the app off a
  // half-designed daytime theme rather than leaving it to the OS.
  runApp(MagicApplication(title: 'Watchools', windTheme: buildWatchoolsWindTheme(), themeMode: ThemeMode.dark));
}
