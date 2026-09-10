import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/middleware/ensure_provider.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/provider_session.dart';

/// Tests for [EnsureProvider], the guard that sends a user with no stored
/// provider to `/saglayici` rather than the fixture-backed `/`.
///
/// A credential-less or a credentialed [ProviderSession] is built the same
/// way step 1's own tests build one: via `developmentCredential`, which is
/// the only seam `flutter test` has, since there is no compile-time define in
/// a test run and `Vault` here is always empty. That is also why only two
/// distinct closures ever appear below: `() => null` is what a define's
/// *absence* looks like, `() => credentials` is what
/// `tool/dev/run_with_provider.sh` looks like, and every assertion the step
/// asks for reduces to one of those two.
void main() {
  MagicTest.init();

  final XtreamCredentials credentials = XtreamCredentials(
    baseUrl: 'http://panel.example:8080',
    username: 'demo',
    password: 'demo',
    userAgent: 'watchools/test',
  );

  setUp(() {
    DatabaseManager().setConnection(sqlite3.openInMemory());
  });

  tearDown(() {
    DatabaseManager().dispose();
    Vault.unfake();
    Magic.flush();
  });

  test('redirects a credential-less session (development seam neutralised) from / to /saglayici', () async {
    Vault.fake();
    final ProviderSession session = ProviderSession(developmentCredential: () => null);
    await session.start();
    Magic.put(session);

    expect(EnsureProvider().redirectTarget('/'), '/saglayici');
  });

  test('returns null for /saglayici itself, the loop guard against an infinite redirect', () async {
    Vault.fake();
    final ProviderSession session = ProviderSession(developmentCredential: () => null);
    await session.start();
    Magic.put(session);

    expect(EnsureProvider().redirectTarget('/saglayici'), isNull);
  });

  test('returns null once the session has a credential (development seam supplies one)', () async {
    Vault.fake();
    final ProviderSession session = ProviderSession(developmentCredential: () => credentials);
    await session.start();
    Magic.put(session);

    expect(EnsureProvider().redirectTarget('/'), isNull);
  });
}
