import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/network/host_resolver.dart';
import 'package:watchools/app/network/resolver_setting.dart';
import 'package:watchools/app/network/resolving_http_overrides.dart';

/// The panel host of every pinned test that needs a hostname the default
/// connect could not reach.
///
/// TEST-NET-2 (RFC 5737), which is guaranteed never to be routed, and an IP
/// literal rather than a name for a reason that is [HostResolver]'s rather than
/// this file's: the ladder refuses a loopback answer for a real hostname,
/// because that is the documented Turkish tampering shape. A host that is
/// already a literal is exempt, and `localhost` is the only other exemption,
/// so a literal is the one panel host a test can legitimately pin AT a loopback
/// server. Pinning `localhost` would prove nothing, since the default connect
/// reaches 127.0.0.1 too.
const String _unroutablePanel = '198.51.100.7';

/// The name the TLS certificate is issued for, and the one host the https
/// tests address.
const String _tlsPanel = 'localhost';

/// A 200 with a body short enough to read back in one go.
const String _ok200 =
    'HTTP/1.1 200 OK\r\n'
    'Content-Type: text/html\r\n'
    'Content-Length: 2\r\n'
    'Connection: close\r\n'
    '\r\n'
    '{}';

/// A rung that answers with [address], or fails the way a real rung fails when
/// it is null.
///
/// [calls] is the evidence for every "was the resolver consulted at all"
/// assertion here, which is half of what this step has to prove: an override
/// installed process-wide must leave every host but the panel alone.
class _ScriptedLookup implements HostLookup {
  /// The single address this rung answers with, or null to throw.
  final String? address;

  /// Every host this rung was asked about, in order.
  final List<String> calls = <String>[];

  _ScriptedLookup([this.address]);

  @override
  Future<HostAnswer> lookup(String host) async {
    calls.add(host);

    final String? answer = address;

    if (answer == null) throw const HostLookupException('scripted rung failure');

    return HostAnswer(<String>[answer]);
  }
}

/// A loopback panel that keeps the raw bytes of every request it is sent.
///
/// The same instrument `xtream_client_test.dart` uses and for the same reason:
/// an [HttpServer] lowercases header names on parse and rebuilds the request
/// line, so raw bytes are the only evidence of what actually went down the
/// socket. Here they are also the only evidence of WHICH socket, since the
/// address this server is bound to is the whole assertion.
class _RawPanel {
  _RawPanel._(this._server);

  final ServerSocket _server;

  /// Every request, whole, in arrival order.
  final List<String> requests = <String>[];

  static Future<_RawPanel> start() async {
    final ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final _RawPanel panel = _RawPanel._(server);

    server.listen(panel._serve);

    return panel;
  }

  int get port => _server.port;

  Future<void> close() => _server.close();

  void _serve(Socket socket) {
    final StringBuffer buffer = StringBuffer();

    socket.listen((List<int> data) {
      buffer.write(utf8.decode(data));

      if (!buffer.toString().contains('\r\n\r\n')) return;

      requests.add(buffer.toString());
      socket.write(_ok200);
      unawaited(socket.close());
    });
  }
}

/// A loopback panel that speaks TLS, presenting a certificate issued for
/// [_tlsPanel] while listening on an address.
///
/// The instrument the https branch needs, and a real handshake rather than a
/// mock is the point: a factory that hands an unsecured socket back for an
/// https URL sends the subscription password in cleartext, and nothing short of
/// a server that actually expects TLS records can tell that apart.
class _TlsPanel {
  _TlsPanel._(this._server);

  final HttpServer _server;

  /// The name out of the `Host` header of every request that completed a
  /// handshake. Parsed rather than raw, so it carries no port.
  final List<String> hosts = <String>[];

  /// How many connections failed before they became a request, which is what a
  /// rejected certificate looks like from this side.
  int handshakeFailures = 0;

  static Future<_TlsPanel> start(SecurityContext context) async {
    final HttpServer server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    final _TlsPanel panel = _TlsPanel._(server);

    server.listen(panel._serve, onError: panel._countFailure);

    return panel;
  }

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  void _serve(HttpRequest request) {
    hosts.add(request.headers.host ?? '');

    request.response
      ..statusCode = HttpStatus.ok
      ..write('{}');

    unawaited(request.response.close());
  }

  /// A handshake this server refused or the client walked away from. Recorded
  /// rather than ignored: the control test deliberately produces one, and an
  /// unhandled stream error would fail the run for the wrong reason.
  void _countFailure(Object error) => handshakeFailures++;
}

void main() {
  late Directory certificates;
  late SecurityContext serverContext;
  late SecurityContext clientContext;
  late HttpOverrides? previousOverrides;

  /// Runs one `openssl` invocation, failing the run with its own diagnostics
  /// rather than with whatever the handshake does three steps later.
  Future<void> openssl(List<String> arguments) async {
    final ProcessResult run = await Process.run('openssl', arguments);

    expect(run.exitCode, 0, reason: 'openssl ${arguments.first} failed: ${run.stderr}');
  }

  setUpAll(() async {
    certificates = await Directory.systemTemp.createTemp('watchools-resolver-tls');

    final String authority = '${certificates.path}/ca.crt';
    final String authorityKey = '${certificates.path}/ca.key';
    final String request = '${certificates.path}/panel.csr';
    final String certificate = '${certificates.path}/panel.crt';
    final String key = '${certificates.path}/panel.key';

    // Generated rather than committed, and an authority plus a leaf rather than
    // one self-signed certificate doing both jobs: trusting a leaf directly is
    // a partial chain, which `dart:io`'s verifier does not accept.
    await openssl(<String>[
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      authorityKey,
      '-out',
      authority,
      '-days',
      '1',
      '-subj',
      '/CN=Watchools Test CA',
    ]);

    // A `subjectAltName` rather than a common name alone, because BoringSSL
    // ignores the common name entirely, and `DNS:` rather than `IP:` because
    // the name is the whole question this fixture exists to ask.
    //
    // `extendedKeyUsage=serverAuth` is not decoration either. A leaf carrying
    // the SAN and nothing else is refused by `dart:io`'s verifier with the same
    // CERTIFICATE_VERIFY_FAILED a wrong name produces, while `openssl s_client`
    // against the same server reports `Verification: OK`. Measured here by
    // adding this one extension to an otherwise identical certificate.
    await openssl(<String>[
      'req',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key,
      '-out',
      request,
      '-subj',
      '/CN=$_tlsPanel',
      '-addext',
      'subjectAltName=DNS:$_tlsPanel',
      '-addext',
      'extendedKeyUsage=serverAuth',
    ]);

    await openssl(<String>[
      'x509',
      '-req',
      '-in',
      request,
      '-CA',
      authority,
      '-CAkey',
      authorityKey,
      '-out',
      certificate,
      '-days',
      '1',
      '-copy_extensions',
      'copy',
    ]);

    serverContext = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey(key);

    // A bare `SecurityContext` carries no trusted roots of its own, so the
    // authority generated above is the only one this client trusts and a
    // handshake that succeeds here succeeded on that certificate's own terms.
    // That is what makes the `host:` assertion mean something.
    clientContext = SecurityContext()..setTrustedCertificates(authority);
  });

  tearDownAll(() async {
    await certificates.delete(recursive: true);
  });

  // `HttpOverrides` exposes `global` as a setter only, so what is put back is
  // what `current` reads: identical outside a zone that installed its own, and
  // this file installs none.
  setUp(() {
    previousOverrides = HttpOverrides.current;
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  /// A resolver whose only rung answers [address], or fails when it is null.
  (HostResolver, _ScriptedLookup) resolverAnswering(String? address) {
    final _ScriptedLookup system = _ScriptedLookup(address);

    return (HostResolver(setting: ResolverSetting.system, system: system), system);
  }

  /// Reads a whole response body, so the connection is finished before a test
  /// asserts on what the server recorded.
  Future<String> get_(HttpClient client, String url) async {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();

    return response.transform(utf8.decoder).join();
  }

  group('the pinned connection', () {
    test('goes to the address the resolver chose, carrying the original host', () async {
      final _RawPanel panel = await _RawPanel.start();
      addTearDown(panel.close);

      final (HostResolver resolver, _ScriptedLookup system) = resolverAnswering(InternetAddress.loopbackIPv4.address);

      // Installed process-wide, the way `AppServiceProvider.register()` does
      // it, so this exercises the real route a provider request takes rather
      // than a client the test wired by hand.
      installResolvingHttpOverrides(resolver: resolver, panelHost: () => _unroutablePanel);

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      expect(await get_(client, 'http://$_unroutablePanel:${panel.port}/player_api.php'), '{}');

      expect(system.calls, <String>[_unroutablePanel]);

      // Nothing is listening on TEST-NET-2, so the request reaching a server
      // bound to 127.0.0.1 is itself the proof that the chosen address, and not
      // the URL's host, is where the socket went.
      expect(panel.requests, hasLength(1));

      // Case-insensitively, because `dart:io` spells the header lowercase on
      // the wire while a panel and this assertion both mean the same header.
      expect(
        panel.requests.single,
        matches(
          RegExp('^host: ${RegExp.escape(_unroutablePanel)}:${panel.port}\$', multiLine: true, caseSensitive: false),
        ),
      );
    });

    test('leaves a host that is not the configured panel to the default connect', () async {
      final _RawPanel panel = await _RawPanel.start();
      addTearDown(panel.close);

      final (HostResolver resolver, _ScriptedLookup system) = resolverAnswering(InternetAddress.loopbackIPv4.address);

      installResolvingHttpOverrides(resolver: resolver, panelHost: () => _unroutablePanel);

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      final String loopback = InternetAddress.loopbackIPv4.address;

      expect(await get_(client, 'http://$loopback:${panel.port}/anything'), '{}');

      // The whole reason this override matches on the panel host: it is
      // installed process-wide, and silently redirecting unrelated traffic is
      // not what the user agreed to when they picked a resolver for their
      // provider.
      expect(system.calls, isEmpty);
      expect(panel.requests, hasLength(1));
    });

    test('falls through to the default connect when the resolver answers null', () async {
      final _RawPanel panel = await _RawPanel.start();
      addTearDown(panel.close);

      final String loopback = InternetAddress.loopbackIPv4.address;
      final (HostResolver resolver, _ScriptedLookup system) = resolverAnswering(null);

      installResolvingHttpOverrides(resolver: resolver, panelHost: () => loopback);

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      expect(await get_(client, 'http://$loopback:${panel.port}/player_api.php'), '{}');

      // Consulted and unable to answer, rather than never consulted: a resolver
      // problem has to degrade to the behaviour the user had before this
      // feature existed, never take the app offline.
      expect(system.calls, <String>[loopback]);
      expect(panel.requests, hasLength(1));
    });
  });

  group('the https branch', () {
    test('hands back a secured socket whose handshake ran against the original name', () async {
      final _TlsPanel panel = await _TlsPanel.start(serverContext);
      addTearDown(panel.close);

      final (HostResolver resolver, _ScriptedLookup system) = resolverAnswering(InternetAddress.loopbackIPv4.address);

      installResolvingHttpOverrides(resolver: resolver, panelHost: () => _tlsPanel);

      final HttpClient client = HttpClient(context: clientContext);
      addTearDown(client.close);

      // Two failures are being ruled out at once. An unsecured socket would put
      // a plaintext request line into a server expecting TLS records, and a
      // handshake run against the address rather than the name would be refused
      // by the certificate, which carries `DNS:localhost` and no IP at all.
      expect(await get_(client, 'https://$_tlsPanel:${panel.port}/player_api.php'), '{}');

      expect(system.calls, <String>[_tlsPanel]);
      expect(panel.hosts, <String>[_tlsPanel]);
    });

    test('a certificate for the name is refused against the address, which is what host: carries', () async {
      final _TlsPanel panel = await _TlsPanel.start(serverContext);
      addTearDown(panel.close);

      // The control the QA asks for, at the layer the production call lives on.
      // Without it "the handshake succeeded" is compatible with `host:` never
      // having mattered, and the Dart trap this step exists to avoid is exactly
      // one that fails open.
      final Socket byAddress = await Socket.connect(InternetAddress.loopbackIPv4, panel.port);

      await expectLater(SecureSocket.secure(byAddress, context: clientContext), throwsA(isA<HandshakeException>()));

      final Socket byName = await Socket.connect(InternetAddress.loopbackIPv4, panel.port);
      final SecureSocket secured = await SecureSocket.secure(byName, host: _tlsPanel, context: clientContext);

      expect(secured.peerCertificate, isNotNull);

      secured.destroy();
    });
  });
}
