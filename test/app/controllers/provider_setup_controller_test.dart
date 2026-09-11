import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/controllers/provider_setup_controller.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/protocol/xtream/xtream_client.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/provider_session.dart';

import '../../support/throwing_vault.dart';

/// A scriptable stand-in for the panel's handshake, which is the only call
/// [ProviderSetupController.submit] makes.
///
/// [handshakeCalls] counts the no-action call specifically rather than every
/// request, so a test asserting "one handshake" cannot be satisfied by a
/// catalogue action this controller has no business sending.
class _FakePanel {
  Object? handshakeBody = const <String, dynamic>{'auth': 0};
  int handshakeStatusCode = 200;
  int handshakeCalls = 0;

  /// Every `action` asked for, in order. What proves a catalogue fetch
  /// happened at all, which is the one thing a handshake count cannot say.
  final List<String> actions = <String>[];

  /// Served for `get_live_streams`, so a test can tell an empty catalogue
  /// caused by nothing fetching from an empty catalogue the panel returned.
  List<Map<String, dynamic>> liveStreams = const <Map<String, dynamic>>[];

  MagicResponse handle(MagicRequest request) {
    final String action = request.queryParameters?['action'] as String? ?? '';

    if (action.isEmpty) {
      handshakeCalls++;

      return MagicResponse(data: handshakeBody, statusCode: handshakeStatusCode);
    }

    actions.add(action);

    if (action == 'get_live_streams') {
      return MagicResponse(data: liveStreams, statusCode: 200);
    }

    return MagicResponse(data: const <dynamic>[], statusCode: 200);
  }
}

/// A handshake body in the wire's own drifted shape: `auth` bare, the rest
/// quoted, the same helper `provider_session_test.dart` uses.
Map<String, dynamic> _handshake({required int auth, String? status, int maxConnections = 1}) => <String, dynamic>{
  'user_info': <String, dynamic>{
    'auth': auth,
    'status': status,
    'exp_date': null,
    'max_connections': '$maxConnections',
    'active_cons': '0',
    'allowed_output_formats': <String>['m3u8', 'ts'],
  },
  'server_info': <String, dynamic>{'timestamp_now': 1700000000, 'time_now': '2023-11-14 00:00:00'},
};

void main() {
  MagicTest.init();

  final XtreamCredentials stored = XtreamCredentials(
    baseUrl: 'http://panel.example:8080',
    username: 'demo',
    password: 'demo',
    userAgent: 'watchools/test',
  );

  late _FakePanel panel;
  late FakeNetworkDriver driver;

  setUp(() {
    DatabaseManager().setConnection(sqlite3.openInMemory());
    Vault.fake();

    panel = _FakePanel();
    driver = FakeNetworkDriver(stubs: panel.handle);
    Magic.singleton(XtreamClient.driverKey, () => driver);
  });

  tearDown(() {
    DatabaseManager().dispose();
    Vault.unfake();
  });

  /// A started session with no provider configured, which is the state the
  /// onboarding screen is reached in.
  ///
  /// `start()` is what runs `CatalogueStore.migrate`, and `adopt` reads the
  /// cached catalogue for the new account key, so a session that never started
  /// fails on the schema rather than on anything this controller did.
  /// `developmentCredential` is closed off so a `--dart-define` left in a shell
  /// profile cannot make this session start out configured.
  /// [playing] closes the connection gate, which is how a test isolates the
  /// submit path: [ProviderSetupController.submit] fires an unawaited
  /// `refresh()` after it adopts, and that refresh handshakes again, so a
  /// request count taken over an open gate counts both.
  Future<ProviderSession> emptySession({bool playing = false}) async {
    final ProviderSession session = ProviderSession(developmentCredential: () => null, isPlaying: () => playing);
    await session.start();

    return session;
  }

  /// A session that already holds [stored], the state a sign-out starts from.
  Future<ProviderSession> configuredSession() async {
    await stored.save();

    final ProviderSession session = ProviderSession(developmentCredential: () => null);
    await session.start();

    return session;
  }

  /// The controller over [session], with the playback seam appending to [order]
  /// instead of reaching an engine.
  ProviderSetupController controllerFor(ProviderSession session, {List<String>? order}) => ProviderSetupController(
    stopPlayback: () async {
      order?.add('playback stopped');
    },
    session: session,
  );

  group('submit(), the moment a typed credential becomes a stored one', () {
    test('stores the credential the panel accepted, and sends the user agent it was given', () async {
      panel.handshakeBody = _handshake(auth: 1, status: 'Active', maxConnections: 2);

      final ProviderSession session = await emptySession(playing: true);
      final ProviderSetupController controller = controllerFor(session);

      await controller.submit(
        baseUrl: 'http://panel.example:8080/',
        username: 'demo',
        password: 's3cret',
        userAgent: 'watchools/test',
      );

      expect(controller.fault, isNull);
      expect(controller.fieldError, isNull);
      expect(controller.busy, isFalse);
      expect(session.hasCredentials, isTrue);

      // Read back out of the vault rather than trusted from the session, which
      // is what "the credential reached the vault" actually means: the whole
      // record, with the trailing slash already normalised off the base URL.
      final XtreamCredentials? persisted = await XtreamCredentials.load();
      expect(persisted, isNotNull);
      expect(persisted!.baseUrl, 'http://panel.example:8080');
      expect(persisted.username, 'demo');
      expect(persisted.password, 's3cret');
      expect(persisted.userAgent, 'watchools/test');

      // The header is what the form typed, never a default this controller
      // invented: a reseller keys access control to it, and a silently
      // defaulted one makes their rejection unexplainable.
      driver.assertSent((MagicRequest request) => request.headers['User-Agent'] == 'watchools/test');
    });

    test(
      'a stored credential is followed by a catalogue fetch, so the user does not land on an empty screen',
      () async {
        // The happy path on every first run, and it was a dead end. `adopt` is
        // local and restores the cache for an account key that has never
        // existed, `boot()`'s refresh already ran and returned at the door
        // because there was no credential then, and `GuideController.reload` is
        // reachable only from a fault panel that `adopt` has just cleared. So
        // the user typed a working credential, landed on `/`, and read "Sonuç
        // yok. Arama terimini değiştirin" having searched for nothing, with no
        // control anywhere that fetches a catalogue.
        //
        // The gate is left open here, unlike the three tests around this one:
        // the fetch is the subject.
        panel.handshakeBody = _handshake(auth: 1, status: 'Active', maxConnections: 2);
        panel.liveStreams = <Map<String, dynamic>>[
          <String, dynamic>{'stream_id': 41, 'name': 'Kanal D', 'category_id': '1', 'stream_icon': ''},
        ];

        final ProviderSession session = await emptySession();
        final ProviderSetupController controller = controllerFor(session);

        await controller.submit(
          baseUrl: 'http://panel.example:8080',
          username: 'demo',
          password: 'demo',
          userAgent: 'watchools/test',
        );

        // Drained rather than awaited, and this is the whole difference between
        // a test and a decoration. The first version of this called
        // `session.refresh()` here, reasoning that the re-entry guard would
        // hand back the pass `submit` fired: it does, but with the fix commented
        // out there is no pass to hand back and the call STARTS one, so the test
        // passed either way. Proved by commenting out
        // `unawaited(_session.refresh())` and watching it stay green.
        //
        // `FakeNetworkDriver` answers without I/O, so the unawaited pass runs to
        // completion in microtasks and this drains them without asking for
        // anything.
        await pumpEventQueue();

        expect(panel.actions, contains('get_live_streams'));
        expect(session.channels, isNotEmpty);
        expect(session.channels.single.name, 'Kanal D');
      },
    );

    test('a rejected credential arrives as HTTP 200 auth 0, reports expired, and is not stored', () async {
      // The wrong-password case, and it is valid JSON: `xtream_account.dart:219`
      // reads a body that decoded plus an inactive account as a real credential
      // rejection. The user hears it now rather than on some later launch.
      panel.handshakeBody = const <String, dynamic>{'auth': 0};

      final ProviderSession session = await emptySession();
      final ProviderSetupController controller = controllerFor(session);

      await controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'wrong',
        userAgent: 'watchools/test',
      );

      expect(controller.fault, ProviderFault.expired);
      expect(controller.busy, isFalse);
      // First of the three, deliberately: it is the assertion that the store
      // did not happen, and it is proven to discriminate by moving
      // `session.adopt` above the fault check and watching THIS line fail
      // (`evidence/04-setup-controller.txt`). Behind `hasCredentials` it would
      // never have been reached in that run.
      expect(await Vault.get(XtreamCredentials.vaultKey), isNull);
      expect(session.hasCredentials, isFalse);
    });

    test('a transport failure reports unreachable, and is not stored', () async {
      panel.handshakeStatusCode = 0;
      panel.handshakeBody = null;

      final ProviderSession session = await emptySession();
      final ProviderSetupController controller = controllerFor(session);

      await controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      expect(controller.fault, ProviderFault.unreachable);
      expect(await Vault.get(XtreamCredentials.vaultKey), isNull);
      expect(session.hasCredentials, isFalse);
    });

    test('a scheme-less panel URL is a field error, and no request leaves at all', () async {
      // `XtreamCredentials` rejects it (`xtream_credentials.dart:88`) because
      // Dio would prepend the driver's base URL to a scheme-less path and
      // silently address the wrong server. That is the user's typo rather than
      // anything the provider said, so it must not become a `ProviderFault`.
      final ProviderSession session = await emptySession();
      final ProviderSetupController controller = controllerFor(session);

      await controller.submit(
        baseUrl: 'panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      expect(controller.fieldError, isNotNull);
      expect(controller.fault, isNull);
      expect(controller.busy, isFalse);
      expect(session.hasCredentials, isFalse);
      expect(await Vault.get(XtreamCredentials.vaultKey), isNull);
      driver.assertNothingSent();
    });

    test('a second submit while one is in flight sends nothing', () async {
      // The measured connection limit on a real account is one, so a double tap
      // must not become two handshakes. `busy` is what the screen reads to
      // refuse the second one, and it is true before the first request leaves.
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      final ProviderSession session = await emptySession(playing: true);
      final ProviderSetupController controller = controllerFor(session);

      final Future<void> first = controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      expect(controller.busy, isTrue);

      final Future<void> second = controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      await Future.wait(<Future<void>>[first, second]);

      expect(panel.handshakeCalls, 1);
      driver.assertSentCount(1);
      expect(session.hasCredentials, isTrue);
    });

    test('a keychain that will not store the credential says so, and adopts nothing', () async {
      // The arm whose own doc block calls it "a live path rather than a
      // hypothetical", and nothing exercised it: on macOS every `Vault.put`
      // from a build with no `keychain-access-groups` entitlement fails with
      // OSStatus -34018. A `fieldError` rather than a `ProviderFault`, because
      // all four faults are statements about the provider and the panel here
      // said yes.
      panel.handshakeBody = _handshake(auth: 1, status: 'Active', maxConnections: 2);

      final ProviderSession session = await emptySession(playing: true);
      final ProviderSetupController controller = controllerFor(session);

      ThrowingVaultService.install(VaultFailure.put);

      await controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      expect(controller.fieldError, isNotNull);
      expect(controller.fault, isNull);
      expect(controller.busy, isFalse, reason: 'the finally arm runs on this path too');

      // Nothing was adopted, which is the assertion the arm's doc block
      // claims: `adopt` saves before it mutates.
      expect(session.hasCredentials, isFalse);
      expect(controller.hasCredential, isFalse);
    });

    test('clears the previous verdict before asking again', () async {
      final ProviderSession session = await emptySession(playing: true);
      final ProviderSetupController controller = controllerFor(session);

      await controller.submit(
        baseUrl: 'panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );
      expect(controller.fieldError, isNotNull);

      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      await controller.submit(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
      );

      expect(controller.fieldError, isNull);
      expect(controller.fault, isNull);
      expect(session.hasCredentials, isTrue);
    });
  });

  group('signOut()', () {
    test('stops playback before the session clears', () async {
      // The order is the deliverable: the core holds the account's single
      // connection slot with a credential the session is about to forget, so
      // stopping it afterwards leaves a stream running against a provider the
      // app no longer has.
      final ProviderSession session = await configuredSession();
      expect(session.hasCredentials, isTrue);

      final List<String> order = <String>[];
      final ProviderSetupController controller = controllerFor(session, order: order);
      session.addListener(() => order.add('session cleared'));

      await controller.signOut();

      expect(order, <String>['playback stopped', 'session cleared']);
      expect(session.hasCredentials, isFalse);
      expect(await Vault.get(XtreamCredentials.vaultKey), isNull);
    });

    test('a keychain that will not release the credential says so instead of throwing', () async {
      // `XtreamCredentials.clear` is a `Vault.delete`, and every `Vault`
      // operation wraps a `PlatformException` as `MagicVaultException`, so a
      // delete that fails natively throws a type nothing above this catches:
      // `ProviderSettingsLayout._run` catches `PlatformException` alone, and
      // `WAnchor.onTap` is a `VoidCallback`, so it would become an unhandled
      // async error and the user would watch a sign-out silently do nothing.
      //
      // A `fieldError` and not a `ProviderFault`, for the reason this
      // controller's own `_storeRefused` records: all four faults are
      // statements about the provider, and this one is about the keychain, so
      // any of them would send the user to retry a panel that never refused.
      final ProviderSession session = await configuredSession();
      expect(session.hasCredentials, isTrue);

      // Installed AFTER the credential is stored, so the failure is a delete
      // that cannot land rather than a save that never happened.
      ThrowingVaultService.install(VaultFailure.remove);

      final ProviderSetupController controller = controllerFor(session);

      await controller.signOut();

      expect(controller.fieldError, isNotNull);
      expect(controller.fault, isNull);

      // The session is deliberately unchanged: it clears the vault first
      // precisely so a failed delete does not leave the app having forgotten
      // a credential it could not remove from storage. `hasCredential` is
      // what the screen reads to decide whether to offer the sign-out again,
      // so it staying true is what keeps the retry on screen.
      expect(session.hasCredentials, isTrue);
      expect(controller.hasCredential, isTrue);
    });
  });
}
