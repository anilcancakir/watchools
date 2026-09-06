import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/config/app.dart';

/// Covers `lib/config/app.dart`, the provider list Magic boots in order.
///
/// This file is easy to break silently: it is a `Map<String, dynamic>`, so the
/// analyzer cannot check the shape of what goes in it, and a provider dropped
/// from the list produces a missing binding at runtime rather than a compile
/// error.
void main() {
  // `Env.load` cannot read the `.env` asset from a plain test, so it falls
  // through to its fallback map. That is the documented testing path, and it
  // means these values are the whole environment for the assertions below.
  setUp(() async {
    Env.reset();
    await Env.load(mergeWith: <String, String>{'APP_NAME': 'Watchools', 'APP_ENV': 'testing', 'APP_DEBUG': 'true'});
  });

  tearDown(Env.reset);

  group('appConfig', () {
    test('carries the application identity under the `app` key', () {
      final Map<String, dynamic> app = appConfig['app'] as Map<String, dynamic>;

      expect(app['name'], 'Watchools');
      expect(app['env'], 'testing');
      expect(app['title_separator'], ' - ');
    });

    test('reads the name from the environment rather than hardcoding it', () async {
      Env.reset();
      await Env.load(mergeWith: <String, String>{'APP_NAME': 'Watchools Staging'});

      final Map<String, dynamic> app = appConfig['app'] as Map<String, dynamic>;

      // Asserting an overridden value, not the default. `.env` is a real asset
      // during `flutter test`, so a test that expects the fallback passes
      // because `.env` supplies the same string, never because the fallback ran.
      expect(app['name'], 'Watchools Staging');
    });

    test('registers every provider the app boots', () {
      final Map<String, dynamic> app = appConfig['app'] as Map<String, dynamic>;
      final List<Object?> providers = app['providers'] as List<Object?>;

      // Ten providers, and the count is asserted deliberately: one silently
      // dropped from the list surfaces as an unresolved binding deep in a
      // screen, not as a failure here, unless this test says how many there are.
      expect(providers, hasLength(10));
      expect(
        providers.every((Object? factory) => factory is Function),
        isTrue,
        reason: 'every entry must be a MagicApp factory closure',
      );
    });
  });
}
