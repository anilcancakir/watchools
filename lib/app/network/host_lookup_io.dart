import 'dart:convert';
import 'dart:io';

import 'host_resolver.dart';

/// The rung that asks whatever the operating system already resolves with.
///
/// The fast one, and the reason [HostResolver] tries it first: measured at 11
/// to 26 ms against 71 to 108 ms for a cold DoH query on the same connection.
class SystemHostLookup implements HostLookup {
  const SystemHostLookup();

  /// Resolves [host] through the platform resolver, IPv4 only.
  ///
  /// The family is pinned rather than left to the platform because the record
  /// this app resolves is an A record, the measured panel publishes exactly one
  /// and no AAAA, and the other rung asks for `type=A`. Two rungs of one ladder
  /// disagreeing about which family a host has would make the escalation
  /// compare two different answers.
  ///
  /// Carries no TTL, because the platform API exposes none. That is the case
  /// [HostResolver.ttlCeiling] exists for.
  @override
  Future<HostAnswer> lookup(String host) async {
    try {
      final List<InternetAddress> resolved = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);

      return HostAnswer(resolved.map((InternetAddress address) => address.address).toList(growable: false));
    } on SocketException catch (error) {
      throw HostLookupException('the system resolver did not answer for $host: ${error.message}');
    }
  }
}

/// The rung that asks a DNS-over-HTTPS endpoint, over a plain [HttpClient].
///
/// Deliberately not magic's `Http` facade, and that is a security boundary
/// rather than a style choice: the shared driver carries magic's
/// `AuthInterceptor`, which attaches the watchools bearer token to every
/// request with no host, scheme or origin test. A DoH query through the facade
/// would hand our own user's token to Cloudflare or Google on every lookup.
class DohHostLookup implements HostLookup {
  /// The endpoint, as `ResolverSetting.dohEndpoint` built it. Both shipped
  /// endpoints answered 200 on 2026-09-11, re-checked before this client was
  /// written.
  final Uri endpoint;

  const DohHostLookup(this.endpoint);

  /// Issues `GET <endpoint>?name=<host>&type=A` with an
  /// `accept: application/dns-json` header and reads the JSON answer.
  ///
  /// Cloudflare at `/dns-query` and Google at `/resolve` return the same body
  /// shape; Google writes the question and answer names fully qualified, which
  /// is not a field this reads, so one parser covers both.
  ///
  /// Throws [HostLookupException] for a transport failure, a non-200 status and
  /// a DNS status other than NOERROR, all of which mean the same thing to the
  /// ladder: this rung did not resolve the host.
  @override
  Future<HostAnswer> lookup(String host) async {
    final HttpClient client = HttpClient();

    try {
      final HttpClientRequest request = await client.getUrl(_queryFor(host));
      request.headers.set(HttpHeaders.acceptHeader, _dnsJson);

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw HostLookupException('$endpoint answered HTTP ${response.statusCode} for $host');
      }

      return _readAnswer(host, body);
    } on SocketException catch (error) {
      throw HostLookupException('$endpoint is unreachable: ${error.message}');
    } on HandshakeException catch (error) {
      throw HostLookupException('$endpoint failed its TLS handshake: ${error.message}');
    } on FormatException catch (error) {
      throw HostLookupException('$endpoint answered something that is not JSON: ${error.message}');
    } finally {
      client.close();
    }
  }

  /// The media type RFC 8484's JSON companion defines, and the one both shipped
  /// endpoints key their JSON response off: without it Cloudflare expects the
  /// base64url wire format on the same path.
  static const String _dnsJson = 'application/dns-json';

  /// The query URL for [host].
  ///
  /// Merges rather than replaces, so a parameter a user typed into a custom
  /// https endpoint (an access token, a filtering profile) survives instead of
  /// being silently dropped by ours.
  Uri _queryFor(String host) =>
      endpoint.replace(queryParameters: <String, String>{...endpoint.queryParameters, 'name': host, 'type': 'A'});

  /// Reads one `application/dns-json` body into an answer.
  ///
  /// A DoH body is untrusted input, so every field is checked rather than cast:
  /// a hostile or broken resolver answering with a different shape has to fail
  /// this rung, not the process. Records are filtered to type 1 because a CNAME
  /// chain returns type 5 records whose `data` is a hostname rather than an
  /// address, measured on both shipped endpoints against `www.wikipedia.org`.
  ///
  /// The TTL is the shortest in the record set, which is the only one safe for
  /// a set cached as a unit.
  static HostAnswer _readAnswer(String host, String body) {
    final Object? decoded = jsonDecode(body);

    if (decoded is! Map<String, dynamic>) {
      throw HostLookupException('$host: the resolver answered no DNS JSON object');
    }

    final Object? status = decoded['Status'];

    if (status != _noError) {
      throw HostLookupException('$host: the resolver answered DNS status $status');
    }

    final Object? records = decoded['Answer'];

    // NOERROR with no answer section at all: the name exists and has no A
    // record. A real answer, and an empty one, which the ladder escalates.
    if (records is! List<dynamic>) return const HostAnswer(<String>[]);

    final List<String> addresses = <String>[];
    Duration? ttl;

    for (final Object? record in records) {
      if (record is! Map<String, dynamic>) continue;

      final Object? type = record['type'];
      final Object? data = record['data'];

      if (type != _aRecord || data is! String) continue;

      addresses.add(data);

      final Duration? recordTtl = _ttlOf(record['TTL']);

      if (recordTtl != null && (ttl == null || recordTtl < ttl)) ttl = recordTtl;
    }

    return HostAnswer(List<String>.unmodifiable(addresses), ttl: ttl);
  }

  /// [raw] as a duration, or null where the record carried no usable TTL.
  ///
  /// A negative TTL is a malformed answer rather than an instruction, so it is
  /// dropped and [HostResolver.ttlCeiling] applies instead. A zero is kept: it
  /// is a resolver asking not to be cached, which the resolver obeys.
  static Duration? _ttlOf(Object? raw) {
    if (raw is! int || raw < 0) return null;

    return Duration(seconds: raw);
  }

  /// RCODE 0. Anything else, including NXDOMAIN's 3, fails this rung.
  static const int _noError = 0;

  /// The `type` an A record carries in a DNS JSON answer.
  static const int _aRecord = 1;
}
