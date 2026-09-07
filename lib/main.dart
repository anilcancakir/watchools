import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';
import 'package:magic_devtools/magic_devtools.dart';

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

  // `MagicDevtools`'s own two halves rather than the five calls this used to
  // hand-roll. The hand-rolled version was missing `MagicPerfIntegration`, the
  // one thing that assigns dusk's `framePerfReader`, so `dusk:perf_end` refused
  // every session with `liveness advanced 0` and blamed a backgrounded page:
  // the app rendered, screenshots came back full, and the counter the refusal
  // is computed from had never been wired.
  //
  // The split is not cosmetic. `installPre` has to run BEFORE `Magic.init`,
  // because the perf integration registers a `NavigatorObserver` and
  // `MagicRouter.addObserver` throws a `StateError` once the router is built.
  // `installPost` has to run after, because both integrations resolve through
  // the container.
  if (!kReleaseMode) {
    MagicDevtools.installPre();
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
  if (!kReleaseMode) {
    MagicDevtools.installPost();
  }

  // Dark-first, not dark-only: the light palette exists and clears AA, but
  // nothing exposes a switch yet, so pinning the mode keeps the app off a
  // half-designed daytime theme rather than leaving it to the OS.
  runApp(MagicApplication(title: 'Watchools', windTheme: buildWatchoolsWindTheme(), themeMode: ThemeMode.dark));
}
