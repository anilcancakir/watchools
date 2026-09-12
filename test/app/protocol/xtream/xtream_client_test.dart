import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/app/protocol/xtream/xtream_client.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/providers/app_service_provider.dart';

/// The panel every faked test addresses.
const String _panelUrl = 'http://panel.example:8080';

/// The one endpoint the whole action surface goes through.
const String _endpoint = '$_panelUrl/player_api.php';

/// The watchools bearer token seeded into the auth guard.
///
/// A distinctive literal so a raw-socket assertion can look for the value as
/// well as for the header name: a driver that ships the token under some other
/// header is the same leak.
const String _watchoolsToken = 'watchools-jwt-do-not-leak';

/// A 200 the panel answers with `text/html`, which is what makes Dio hand the
/// body back as a raw [String] instead of a decoded map.
const String _htmlTyped200 =
    'HTTP/1.1 200 OK\r\n'
    'Content-Type: text/html\r\n'
    'Content-Length: 2\r\n'
    'Connection: close\r\n'
    '\r\n'
    '{}';

/// The redirect a real panel answers a stream request with. Pointed at the same
/// endpoint so a driver that followed it would produce a second recorded
/// request rather than a connection error.
const String _redirect302 =
    'HTTP/1.1 302 Found\r\n'
    'Location: /player_api.php?followed=1\r\n'
    'Content-Length: 0\r\n'
    'Connection: close\r\n'
    '\r\n';

/// A 401 from the panel, which the shared driver's [AuthInterceptor] reads as a
/// signal to refresh the watchools token and replay the request.
const String _unauthorised401 =
    'HTTP/1.1 401 Unauthorized\r\n'
    'Content-Length: 0\r\n'
    'Connection: close\r\n'
    '\r\n';

XtreamCredentials _credentials({String baseUrl = _panelUrl}) =>
    XtreamCredentials(baseUrl: baseUrl, username: 'bob', password: 's3cret', userAgent: 'Watchools/1.0 (provider)');

/// Binds a recording double under the client's own container key.
///
/// `Http.fake()` is the wrong instrument here: it replaces the `network`
/// singleton, which is exactly the driver this client must never resolve, so
/// every assertion against it would be vacuous.
FakeNetworkDriver _bindFakeDriver([Object? stubs]) {
  final FakeNetworkDriver fake = FakeNetworkDriver(stubs: stubs);

  Magic.singleton(XtreamClient.driverKey, () => fake);

  return fake;
}

/// The request the client last sent through [fake].
MagicRequest _lastRequest(FakeNetworkDriver fake) => fake.recorded.last.$1;

/// The query map the client last sent through [fake].
Map<String, dynamic> _lastQuery(FakeNetworkDriver fake) => _lastRequest(fake).queryParameters ?? <String, dynamic>{};

/// The `action` the client last sent, or null for the handshake.
String? _lastAction(FakeNetworkDriver fake) => _lastQuery(fake)['action'] as String?;

/// Seeds a watchools bearer token into the real auth guard.
///
/// [FakeAuthManager] is not usable for this: its guard is not a [BaseGuard], so
/// `cachedToken` never exists and [AuthInterceptor] would find nothing to
/// attach even on a driver that carries it. A real [BearerTokenGuard] over a
/// faked vault is the seam that actually caches a token.
Future<void> _seedWatchoolsToken() async {
  Vault.fake();
  Magic.singleton('auth', AuthManager.new);

  final BaseGuard guard = Auth.guard() as BaseGuard;
  await guard.storeToken(_watchoolsToken);

  expect(guard.cachedToken, _watchoolsToken, reason: 'the token seam must actually cache, or the leak test is vacuous');
}

/// A loopback panel that keeps the raw bytes of every request it is sent.
///
/// The receiving side of an [HttpServer] lowercases header names on parse and
/// an interceptor-level assertion runs before the wire, so raw bytes are the
/// only evidence of what a driver actually sent.
class _RawPanel {
  _RawPanel._(this._server, this._response);

  final ServerSocket _server;
  final String _response;

  /// Every request, whole, in arrival order.
  final List<String> requests = <String>[];

  static Future<_RawPanel> start({String response = _htmlTyped200}) async {
    final ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final _RawPanel panel = _RawPanel._(server, response);

    server.listen(panel._serve);

    return panel;
  }

  /// The panel root, in the shape [XtreamCredentials] accepts.
  String get baseUrl => 'http://${InternetAddress.loopbackIPv4.address}:${_server.port}';

  Future<void> close() => _server.close();

  void _serve(Socket socket) {
    final StringBuffer buffer = StringBuffer();

    socket.listen((List<int> data) {
      buffer.write(utf8.decode(data));

      if (!buffer.toString().contains('\r\n\r\n')) return;

      requests.add(buffer.toString());
      socket.write(_response);
      unawaited(socket.close());
    });
  }
}

void main() {
  /// Whatever was installed before a test in this file booted the real service
  /// provider, put back afterwards.
  ///
  /// `AppServiceProvider.register()` assigns `HttpOverrides.global`, and five
  /// tests below call it. Without this the LAST one leaves the app's resolving
  /// override installed for the rest of the isolate, on top of whatever
  /// `flutter_test` had there. The failure that causes is quiet rather than
  /// loud: the binding's own override is what answers a network image with a
  /// canned 400, so a later widget test would make a REAL outbound request and
  /// pass. A test that fails is a test doing its job; a test that reaches the
  /// network and goes green is the one worth ten lines to prevent.
  ///
  /// `HttpOverrides` exposes `global` as a setter only, so what is put back is
  /// what `current` reads. Identical outside a zone that installed its own, and
  /// this file installs none.
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;

    MagicApp.reset();
    Magic.flush();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  // ---------------------------------------------------------------------------
  // Group 1 — No watchools credential reaches the panel.
  //
  // The reason this step exists. Every assertion here reads raw bytes off a
  // loopback socket: the same assertion against FakeNetworkDriver cannot fail,
  // because the fake records what the caller passed and runs no interceptors.
  // ---------------------------------------------------------------------------

  group('no watchools credential reaches the panel', () {
    test('the registered provider driver ships no Authorization header with a token cached', () async {
      await _seedWatchoolsToken();
      AppServiceProvider(Magic.app).register();

      final _RawPanel panel = await _RawPanel.start();
      addTearDown(panel.close);

      await XtreamClient(_credentials(baseUrl: panel.baseUrl)).handshake();

      expect(panel.requests, hasLength(1));
      expect(panel.requests.single.toLowerCase(), isNot(contains('authorization')));
      expect(panel.requests.single, isNot(contains(_watchoolsToken)));
    });

    test('the same request through a driver carrying AuthInterceptor does ship it', () async {
      // The control that makes the assertion above non-vacuous: it proves the
      // token seam, the loopback capture and the request path are all live, so
      // a missing Authorization line above is the driver's doing.
      await _seedWatchoolsToken();

      final DioNetworkDriver leaky = DioNetworkDriver(baseUrl: '')..addInterceptor(AuthInterceptor());
      Magic.singleton(XtreamClient.driverKey, () => leaky);

      final _RawPanel panel = await _RawPanel.start();
      addTearDown(panel.close);

      await XtreamClient(_credentials(baseUrl: panel.baseUrl)).handshake();

      expect(panel.requests.single, contains('Bearer $_watchoolsToken'));
    });

    test('the registered provider driver carries no interceptor and follows no redirect', () {
      AppServiceProvider(Magic.app).register();

      int interceptors = -1;
      bool followsRedirects = true;

      Magic.make<DioNetworkDriver>(XtreamClient.driverKey).configureDriver((dio) {
        interceptors = dio.interceptors.length;
        followsRedirects = dio.options.followRedirects;
      });

      // Dio seeds its own ImplyContentTypeInterceptor and magic's
      // `addInterceptor` appends on top of it, so one is the empty state.
      expect(interceptors, 1);
      expect(followsRedirects, isFalse);
    });

    test('a 302 is surfaced rather than followed', () async {
      AppServiceProvider(Magic.app).register();

      final _RawPanel panel = await _RawPanel.start(response: _redirect302);
      addTearDown(panel.close);

      final XtreamResponse<Map<String, dynamic>> response = await XtreamClient(_credentials(baseUrl: panel.baseUrl))
          .handshake();

      expect(response.statusCode, 302);
      expect(panel.requests, hasLength(1));
    });

    test('a 401 from the panel is surfaced without a refresh or a replay', () async {
      await _seedWatchoolsToken();
      AppServiceProvider(Magic.app).register();

      final _RawPanel panel = await _RawPanel.start(response: _unauthorised401);
      addTearDown(panel.close);

      final XtreamResponse<Map<String, dynamic>> response = await XtreamClient(_credentials(baseUrl: panel.baseUrl))
          .handshake();

      expect(response.statusCode, 401);
      expect(panel.requests, hasLength(1));
    });

    test(
      'the User-Agent header key reaches the wire with its casing intact',
      () async {
        AppServiceProvider(Magic.app).register();

        final _RawPanel panel = await _RawPanel.start();
        addTearDown(panel.close);

        await XtreamClient(_credentials(baseUrl: panel.baseUrl)).handshake();

        expect(panel.requests.single, contains('User-Agent: Watchools/1.0 (provider)'));
      },
      skip:
          'Needs magic with preserveHeaderCase, fluttersdk/magic#151 (branch '
          'fix/dio-preserve-header-case). It passes against the local override '
          'and fails against the published constraint, so it stays skipped '
          'until the commit that bumps `magic:` unskips it.',
    );
  });

  // ---------------------------------------------------------------------------
  // Group 2 — The endpoint, and where the credential rides.
  // ---------------------------------------------------------------------------

  group('endpoint and credentials', () {
    test('the handshake sends the credential and no action', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();

      await XtreamClient(_credentials()).handshake();

      expect(_lastRequest(fake).url, _endpoint);
      expect(_lastQuery(fake)['username'], 'bob');
      expect(_lastQuery(fake)['password'], 's3cret');
      expect(_lastQuery(fake).containsKey('action'), isFalse);
    });

    test('the credential rides in the query map and never in the URL string', () async {
      // The telescope integration records `options.path`, which excludes the
      // query. A credential built into the URL would land in that record.
      final FakeNetworkDriver fake = _bindFakeDriver();
      final XtreamClient client = XtreamClient(_credentials());

      await client.handshake();
      await client.liveStreams();
      await client.shortEpg(101);

      for (final (MagicRequest request, MagicResponse _) in fake.recorded) {
        expect(request.url, _endpoint);
        expect(request.url, isNot(contains('bob')));
        expect(request.url, isNot(contains('s3cret')));
      }
    });

    test('every action reaches the panel under its own name', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();
      final XtreamClient client = XtreamClient(_credentials());

      final Map<String, Future<Object?> Function()> actions = <String, Future<Object?> Function()>{
        'get_live_categories': client.liveCategories,
        'get_vod_categories': client.vodCategories,
        'get_series_categories': client.seriesCategories,
        'get_series': client.series,
        'get_live_streams': client.liveStreams,
        'get_vod_streams': client.vodStreams,
        'get_vod_info': () => client.vodInfo(7),
        'get_short_epg': () => client.shortEpg(101),
        'get_simple_data_table': () => client.simpleDataTable(101),
      };

      for (final MapEntry<String, Future<Object?> Function()> entry in actions.entries) {
        final int before = fake.recorded.length;

        await entry.value();

        // The first request of the call, not the last: an empty data table
        // legitimately fires a second one under the typo'd spelling, which the
        // fallback group asserts on its own.
        final MagicRequest sent = fake.recorded[before].$1;

        expect(sent.queryParameters?['action'], entry.key);
        expect(sent.url, _endpoint);
      }
    });

    test('the client addresses the stored panel and ignores server_info.url', () async {
      // The credentials ride in the path of a stream URL, so a host taken off
      // a response field hands them to whichever host the panel names.
      final FakeNetworkDriver fake = _bindFakeDriver((MagicRequest request) {
        return MagicResponse(
          data: <String, dynamic>{
            'server_info': <String, dynamic>{'url': 'http://stranger.example', 'port': '9999'},
          },
          statusCode: 200,
        );
      });
      final XtreamClient client = XtreamClient(_credentials());

      await client.handshake();
      await client.liveStreams();

      expect(_lastRequest(fake).url, _endpoint);
    });

    test('the header key is spelled exactly User-Agent, which ExoPlayer needs', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();

      await XtreamClient(_credentials()).handshake();

      expect(_lastRequest(fake).headers['User-Agent'], 'Watchools/1.0 (provider)');
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3 — Query shape, and the pagination that does not exist.
  // ---------------------------------------------------------------------------

  group('query shape', () {
    test('the stream lists send the credential and the action and nothing else', () async {
      // No offset, no limit, no page: `category_id` is the only narrowing
      // parameter the protocol has, and a whole catalogue arrives in one array.
      // Asserted over the recorded query rather than by grep, because
      // `get_short_epg` legitimately sends `limit`.
      final FakeNetworkDriver fake = _bindFakeDriver();
      final XtreamClient client = XtreamClient(_credentials());

      await client.liveStreams();
      expect(_lastQuery(fake).keys, unorderedEquals(<String>['username', 'password', 'action']));

      await client.vodStreams();
      expect(_lastQuery(fake).keys, unorderedEquals(<String>['username', 'password', 'action']));

      await client.series();
      expect(_lastQuery(fake).keys, unorderedEquals(<String>['username', 'password', 'action']));
    });

    test('get_short_epg sends stream_id and the limit the action honours', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();

      await XtreamClient(_credentials()).shortEpg(101, limit: 10);

      expect(_lastQuery(fake)['stream_id'], 101);
      expect(_lastQuery(fake)['limit'], 10);
    });

    test('get_simple_data_table sends stream_id and no limit, being the unlimited sibling', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();

      await XtreamClient(_credentials()).simpleDataTable(101);

      expect(_lastQuery(fake)['stream_id'], 101);
      expect(_lastQuery(fake).containsKey('limit'), isFalse);
    });

    test('get_vod_info sends vod_id', () async {
      final FakeNetworkDriver fake = _bindFakeDriver();

      await XtreamClient(_credentials()).vodInfo(42);

      expect(_lastQuery(fake)['vod_id'], 42);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 4 — What the client hands back, and what it refuses to interpret.
  // ---------------------------------------------------------------------------

  group('response reading', () {
    test('an object body arriving as a raw String still parses', () async {
      _bindFakeDriver(<String, MagicResponse>{
        '*': MagicResponse(data: '{"user_info":{"auth":1},"server_info":{}}', statusCode: 200),
      });

      final XtreamResponse<Map<String, dynamic>> response = await XtreamClient(_credentials()).handshake();

      expect(response.data?['user_info'], <String, dynamic>{'auth': 1});
    });

    test('a list body arriving as a raw String still parses', () async {
      _bindFakeDriver(<String, MagicResponse>{
        '*': MagicResponse(data: '[{"category_id":"1"},{"category_id":"2"}]', statusCode: 200),
      });

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials()).liveCategories();

      expect(response.data, hasLength(2));
      expect(response.data?.first['category_id'], '1');
    });

    test('a 200 carrying the plain word blocked keeps the body and decodes to null', () async {
      _bindFakeDriver(<String, MagicResponse>{'*': MagicResponse(data: 'blocked', statusCode: 200)});
      final XtreamClient client = XtreamClient(_credentials());

      final XtreamResponse<Map<String, dynamic>> handshake = await client.handshake();
      final XtreamResponse<List<Map<String, dynamic>>> streams = await client.liveStreams();

      expect(handshake.statusCode, 200);
      expect(handshake.body, 'blocked');
      expect(handshake.data, isNull);
      expect(streams.body, 'blocked');
      expect(streams.data, isNull);
    });

    test('a transport failure surfaces as status 0 rather than a throw', () async {
      _bindFakeDriver(<String, MagicResponse>{'*': MagicResponse(data: null, statusCode: 0)});

      final XtreamResponse<Map<String, dynamic>> response = await XtreamClient(_credentials()).handshake();

      expect(response.statusCode, 0);
      expect(response.data, isNull);
      expect(response.body, isNull);
    });

    test('an unknown action answering with an array reads as empty rather than unreadable', () async {
      // The panel answers `[]` for an action it does not implement, which is a
      // different state from a body this layer cannot read.
      _bindFakeDriver(<String, MagicResponse>{'*': MagicResponse(data: <dynamic>[], statusCode: 200)});

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials()).series();

      expect(response.data, isEmpty);
    });

    test('the EPG actions unwrap the epg_listings envelope', () async {
      _bindFakeDriver(<String, MagicResponse>{
        '*': MagicResponse(
          data: <String, dynamic>{
            'epg_listings': <Map<String, dynamic>>[
              <String, dynamic>{'id': '1'},
            ],
          },
          statusCode: 200,
        ),
      });

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials()).shortEpg(101);

      expect(response.data, hasLength(1));
      expect(response.data?.single['id'], '1');
    });
  });

  // ---------------------------------------------------------------------------
  // Group 5 — The typo'd action some panels implement instead.
  // ---------------------------------------------------------------------------

  group('get_simple_date_table fallback', () {
    /// Answers [populated] for whichever spelling it names and an empty
    /// envelope for the other.
    FakeNetworkDriver bindPanel({required String populated}) {
      return _bindFakeDriver((MagicRequest request) {
        final String? action = request.queryParameters?['action'] as String?;

        return MagicResponse(
          data: <String, dynamic>{
            'epg_listings': action == populated
                ? <Map<String, dynamic>>[
                    <String, dynamic>{'id': '1'},
                  ]
                : <Map<String, dynamic>>[],
          },
          statusCode: 200,
        );
      });
    }

    test('an empty data table retries the typo spelling', () async {
      final FakeNetworkDriver fake = bindPanel(populated: 'get_simple_date_table');

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials())
          .simpleDataTable(101);

      expect(response.data, hasLength(1));
      fake.assertSentCount(2);
      expect(_lastAction(fake), 'get_simple_date_table');
    });

    test('a populated data table does not retry', () async {
      final FakeNetworkDriver fake = bindPanel(populated: 'get_simple_data_table');

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials())
          .simpleDataTable(101);

      expect(response.data, hasLength(1));
      fake.assertSentCount(1);
    });

    test('two empty answers return the documented spelling, which is the truthful one', () async {
      final FakeNetworkDriver fake = bindPanel(populated: 'neither');

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials())
          .simpleDataTable(101);

      expect(response.data, isEmpty);
      fake.assertSentCount(2);
    });

    test('a refused data table is surfaced rather than retried', () async {
      final FakeNetworkDriver fake = _bindFakeDriver(<String, MagicResponse>{
        '*': MagicResponse(data: null, statusCode: 0),
      });

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials())
          .simpleDataTable(101);

      expect(response.statusCode, 0);
      fake.assertSentCount(1);
    });

    test('a 200 carrying an unreadable body is NOT retried', () async {
      // The panel's generic denial: HTTP 200 with the plain word `blocked`.
      // `data` is null there, and the previous guard read null as "empty, so
      // try the other spelling" and sent a second request to a panel that had
      // just refused one. On an account at its connection limit that second
      // request is what costs another device its slot, which is the whole
      // reason `ProviderFault.evicted` exists as a separate member.
      final FakeNetworkDriver fake = _bindFakeDriver(<String, MagicResponse>{
        '*': MagicResponse(data: 'blocked', statusCode: 200),
      });

      final XtreamResponse<List<Map<String, dynamic>>> response = await XtreamClient(_credentials())
          .simpleDataTable(101);

      expect(response.statusCode, 200);
      expect(response.data, isNull);
      expect(response.body, 'blocked', reason: 'the caller needs the raw body to classify the denial');
      fake.assertSentCount(1);
    });
  });
}
