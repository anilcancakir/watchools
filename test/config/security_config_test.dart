import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:watchools/config/security.dart';

/// Tests for the one config domain whose absence is silent.
///
/// `Config.get<bool>(...) ?? true` inside magic's `VaultServiceProvider` reads
/// a key that was never registered exactly like a key set to `true`, so every
/// way of getting this wrong produces a macOS build that fails every
/// `Vault.put` with OSStatus -34018 and says nothing about why. Two of those
/// ways were found in magic's own documentation across two review rounds: a
/// config file that is never handed to `Magic.init`, and a map without its
/// domain key. Both are asserted here rather than trusted.
void main() {
  MagicTest.init();

  tearDown(() {
    Config.set('security', <String, dynamic>{});
  });

  test('merged verbatim, it lands on the dotted path magic reads', () {
    // Verbatim, with no wrapper added here: `MagicApp.init` merges each
    // `configFactories` entry as given and derives no domain name from
    // anywhere, so a test that supplies the `'security'` key itself asserts
    // the dotted lookup, which was never in doubt, instead of this map's
    // shape. That mistake is what magic#153's third review round was about.
    Config.merge(securityConfig);

    expect(Config.get<bool>('security.vault.macos_data_protection_keychain'), isNotNull);
  });

  test('a debug or profile run takes the legacy keychain, which needs no entitlement', () {
    // `flutter test` is a debug run, so `kReleaseMode` is false here and this
    // asserts the branch a contributor with no signing certificate actually
    // gets. The release branch is the package default and cannot be reached
    // from a test.
    Config.merge(securityConfig);

    expect(Config.get<bool>('security.vault.macos_data_protection_keychain'), isFalse);
  });

  test('main.dart hands it to Magic.init, because the file does nothing by existing', () {
    // Reading the source is the only seam there is: `Magic.init` is called
    // once, from `main()`, before any test can observe it, and a config
    // domain that is never registered is indistinguishable from one whose
    // value happens to match the default. The alternative to this assertion
    // is no assertion, and the failure it guards against is a macOS build
    // that cannot store a credential with nothing anywhere saying why.
    final String main = File('lib/main.dart').readAsStringSync();

    expect(main, contains("import 'config/security.dart';"));
    expect(main, contains('() => securityConfig,'));
  });
}
