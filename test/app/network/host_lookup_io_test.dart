import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/network/host_resolver.dart';

/// A loopback server answering one canned `application/dns-json` body.
///
/// A real socket rather than a mocked client, for the reason
/// `xtream_client_test.dart:93-97` records about its own raw panel: the thing
/// under test here is a parser over bytes that arrived from somewhere else, and
/// a fake that hands it a Dart object has already done the half that can go
/// wrong.
class _DohServer {
  _DohServer._(this._server, this.body, this.statusCode);

  final HttpServer _server;
  final String body;
  final int statusCode;

  /// Every query string this server was asked with, in order.
  final List<String> queries = <String>[];

  static Future<_DohServer> start({required String body, int statusCode = 200}) async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final _DohServer doh = _DohServer._(server, body, statusCode);

    server.listen((HttpRequest request) async {
      doh.queries.add(request.uri.query);
      request.response.statusCode = doh.statusCode;
      request.response.headers.contentType = ContentType('application', 'dns-json');
      request.response.write(doh.body);

      await request.response.close();
    });

    return doh;
  }

  Uri get endpoint => Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${_server.port}/dns-query');

  Future<void> close() => _server.close(force: true);
}

/// One `Answer` record in the shape both shipped endpoints emit.
Map<String, Object?> _record({required int type, required String data, int ttl = 300}) => <String, Object?>{
  'type': type,
  'data': data,
  'TTL': ttl,
};

String _answer({required int status, List<Map<String, Object?>>? records}) =>
    jsonEncode(<String, Object?>{'Status': status, 'Answer': ?records});

void main() {
  group('DohHostLookup, reading an untrusted body', () {
    test('returns the A records and the shortest TTL in the set', () async {
      final _DohServer doh = await _DohServer.start(
        body: _answer(
          status: 0,
          records: <Map<String, Object?>>[
            _record(type: 1, data: '203.0.113.5', ttl: 600),
            _record(type: 1, data: '203.0.113.6', ttl: 120),
          ],
        ),
      );
      addTearDown(doh.close);

      final HostAnswer answer = await DohHostLookup(doh.endpoint).lookup('panel.example');

      expect(answer.addresses, <String>['203.0.113.5', '203.0.113.6']);

      // The shortest, because the set is cached as a unit and the longest would
      // hold an entry past what its own record admits.
      expect(answer.ttl, const Duration(seconds: 120));
      expect(doh.queries.single, contains('name=panel.example'));
      expect(doh.queries.single, contains('type=A'));
    });

    test('drops a CNAME record, whose data is a hostname rather than an address', () async {
      // Measured on both shipped endpoints against `www.wikipedia.org`: the
      // answer carries a `type: 5` record whose `data` is `dyna.wikimedia.org.`.
      // A parser taking `Answer[0].data` would hand that to a socket as an
      // address.
      final _DohServer doh = await _DohServer.start(
        body: _answer(
          status: 0,
          records: <Map<String, Object?>>[
            _record(type: 5, data: 'dyna.wikimedia.org.'),
            _record(type: 1, data: '198.51.100.7'),
          ],
        ),
      );
      addTearDown(doh.close);

      final HostAnswer answer = await DohHostLookup(doh.endpoint).lookup('www.example');

      expect(answer.addresses, <String>['198.51.100.7']);
    });

    test('throws on a DNS status other than NOERROR', () async {
      // NXDOMAIN. A rung that cannot answer has to throw so the ladder moves on,
      // rather than returning an empty answer that reads as "no such record".
      final _DohServer doh = await _DohServer.start(body: _answer(status: 3));
      addTearDown(doh.close);

      await expectLater(DohHostLookup(doh.endpoint).lookup('panel.example'), throwsA(isA<HostLookupException>()));
    });

    test('throws when the body is not a DNS JSON object at all', () async {
      final _DohServer doh = await _DohServer.start(body: '["not", "an", "object"]');
      addTearDown(doh.close);

      await expectLater(DohHostLookup(doh.endpoint).lookup('panel.example'), throwsA(isA<HostLookupException>()));
    });

    test('throws on a non-200, rather than parsing an error page', () async {
      final _DohServer doh = await _DohServer.start(body: 'gateway timeout', statusCode: 504);
      addTearDown(doh.close);

      await expectLater(DohHostLookup(doh.endpoint).lookup('panel.example'), throwsA(isA<HostLookupException>()));
    });

    test('reads NOERROR with no answer section as an empty answer, not a failure', () async {
      // The name exists and has no A record. A real answer, and one the ladder
      // escalates past rather than treating as a broken resolver.
      final _DohServer doh = await _DohServer.start(body: _answer(status: 0));
      addTearDown(doh.close);

      final HostAnswer answer = await DohHostLookup(doh.endpoint).lookup('panel.example');

      expect(answer.addresses, isEmpty);
      expect(answer.ttl, isNull);
    });

    test('ignores a negative TTL rather than caching backwards', () async {
      final _DohServer doh = await _DohServer.start(
        body: _answer(status: 0, records: <Map<String, Object?>>[_record(type: 1, data: '203.0.113.5', ttl: -1)]),
      );
      addTearDown(doh.close);

      final HostAnswer answer = await DohHostLookup(doh.endpoint).lookup('panel.example');

      expect(answer.addresses, <String>['203.0.113.5']);

      // Null rather than a negative duration, so `HostResolver.ttlCeiling`
      // decides instead.
      expect(answer.ttl, isNull);
    });

    test('keeps a query the endpoint already carried', () async {
      // A user's custom endpoint may carry an access token or a filtering
      // profile; replacing the query rather than merging would drop it silently.
      final _DohServer doh = await _DohServer.start(
        body: _answer(status: 0, records: <Map<String, Object?>>[_record(type: 1, data: '203.0.113.5')]),
      );
      addTearDown(doh.close);

      await DohHostLookup(doh.endpoint.replace(queryParameters: <String, String>{'profile': 'abc'}))
          .lookup('panel.example');

      expect(doh.queries.single, contains('profile=abc'));
      expect(doh.queries.single, contains('name=panel.example'));
    });
  });
}
