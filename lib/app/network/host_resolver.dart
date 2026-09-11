import 'dart:async';

import 'package:flutter/foundation.dart';

import 'host_lookup_io.dart' if (dart.library.js_interop) 'host_lookup_web.dart';
import 'resolver_setting.dart';

export 'host_lookup_io.dart' if (dart.library.js_interop) 'host_lookup_web.dart';

/// One rung of [HostResolver]'s ladder.
///
/// Three implementations exist the moment this interface does, which is what
/// earns it rather than making it speculative: [SystemHostLookup] over the
/// platform resolver, [DohHostLookup] over HTTPS, and the scripted fake the
/// tests drive.
///
/// Addresses cross this boundary as plain literals rather than as a platform
/// address type. That keeps [HostResolver]'s ladder, cache and tamper check
/// free of any platform library, so all three are testable with nothing under
/// them, and it is what lets this app keep scaffolding a web target where no
/// such type exists at all.
abstract interface class HostLookup {
  /// Resolves [host] to its A records.
  ///
  /// Throws [HostLookupException] when the rung cannot answer. An empty answer
  /// is not a throw but means the same thing to [HostResolver]: move on.
  Future<HostAnswer> lookup(String host);
}

/// What one rung came back with.
@immutable
class HostAnswer {
  /// The A records, in the order the rung returned them, as dotted-decimal or
  /// colon-hex literals.
  ///
  /// Never re-ordered and never raced. FFmpeg already implements RFC 8305 and
  /// the measured panel publishes exactly one A record, so a Happy Eyeballs
  /// layer here would be a mechanism with no input.
  final List<String> addresses;

  /// How long the answer may be held, when the rung knows.
  ///
  /// Null for the system rung, whose platform API exposes no TTL at all, which
  /// is the case [HostResolver.ttlCeiling] exists for. The DoH JSON carries one
  /// per record.
  final Duration? ttl;

  const HostAnswer(this.addresses, {this.ttl});
}

/// A rung could not answer.
///
/// The platform rungs wrap whatever they caught into this one type so that
/// [HostResolver] can catch a named exception rather than everything: a ladder
/// that caught `Object` would swallow a programming error inside its own rung
/// and report it as a DNS failure.
@immutable
class HostLookupException implements Exception {
  /// Why the rung failed, for a log line.
  ///
  /// Safe to print: a DNS query carries a hostname and a record type, never a
  /// provider credential, which is the one thing this app must never log.
  final String reason;

  const HostLookupException(this.reason);

  @override
  String toString() => 'HostLookupException: $reason';
}

/// Resolves a provider hostname to one address, under a bounded wait.
///
/// **The system rung goes first, and the order is a measurement rather than a
/// preference.** On the owner's Turkish connection on 2026-09-11 a plain UDP
/// lookup answered in 11 to 13 ms against `1.1.1.1` and 14 to 26 ms against the
/// ISP resolver, while a cold DNS-over-HTTPS query to `cloudflare-dns.com` took
/// 71 to 108 ms. Putting DoH first would slow every healthy lookup by close to
/// an order of magnitude in order to fix the minority whose resolver is broken,
/// so DoH is the rung for the failing case and never the default path. A user
/// whose DNS works pays nothing for this feature.
///
/// **The timeout is the point of resolving in Dart at all**, not a defensive
/// extra. FFmpeg resolves through a plain blocking `getaddrinfo` with no
/// interrupt callback wired to it, so mpv's own `--network-timeout` cannot
/// bound a resolver that never answers: a hijacked or dead resolver hangs the
/// player with nothing to classify and nothing to retry. Owning the wait here
/// is what converts that unbounded hang into a bounded failure. The abandoned
/// lookup is not cancelled, because no API can cancel one; it is left to finish
/// into nothing while the next rung runs.
///
/// **A blackhole answer escalates rather than being refused.** Loopback,
/// unspecified and link-local for a host that is neither `localhost` nor
/// already a literal is the documented Turkish tampering shape, Vodafone
/// answering `127.0.0.1` for a blocked name. Escalating is what serves this
/// feature's purpose, because the next rung is a resolver the ISP does not
/// control; refusing outright would only fail differently.
///
/// **A private-range answer is deliberately not refused.** It is exactly what a
/// LAN panel and a WireGuard panel legitimately answer with, and refusing it
/// stops no attacker, who would simply answer with a public address they
/// control.
class HostResolver {
  /// How long one rung may take before it is abandoned.
  ///
  /// Measured healthy lookups on this app's own target are 11 to 26 ms, so two
  /// seconds is roughly eighty times a healthy answer and cuts nothing that was
  /// going to arrive, including a cold cache on a congested mobile path. It
  /// bounds the whole ladder at twice this, which is inside what a viewer will
  /// wait for a channel to open, and the case it replaces waits forever.
  static const Duration defaultTimeout = Duration(seconds: 2);

  /// The longest an answer is held when the rung supplied no TTL of its own.
  ///
  /// Five minutes is the TTL the measured panel's own A record carries, so an
  /// answer from the system rung, which arrives with no TTL at all, is never
  /// held past what the zone itself advertises for the one host this app
  /// resolves. It is also long enough that a channel-hopping session resolves
  /// once rather than on every stream open. A DoH answer's own TTL is used
  /// instead of this but clamped to it: a resolver claiming a day of freshness
  /// is not trusted to pin this app to one address for a day.
  static const Duration ttlCeiling = Duration(minutes: 5);

  /// Which resolver the user picked.
  ///
  /// Held rather than derived, so the settings screen can show the choice and
  /// [cached] side by side without reaching for a second object.
  final ResolverSetting setting;

  /// How long each rung may take. See [defaultTimeout] for the default's
  /// reasoning.
  final Duration timeout;

  final HostLookup _system;
  final HostLookup? _doh;
  final DateTime Function() _clock;
  final Map<String, _CachedAddress> _cache = <String, _CachedAddress>{};

  /// Builds a resolver for [setting].
  ///
  /// [system], [doh] and [clock] are seams for the tests, which drive rungs
  /// that hang on purpose and move time without waiting for it. [doh]
  /// substitutes the implementation of a rung the setting has already
  /// authorised rather than creating one, so [ResolverSetting.system] has no
  /// second rung whatever is passed here; the setting stays the single place
  /// that decides whether DoH happens at all.
  HostResolver({
    required this.setting,
    HostLookup? system,
    HostLookup? doh,
    this.timeout = defaultTimeout,
    DateTime Function()? clock,
  }) : _system = system ?? const SystemHostLookup(),
       _doh = _dohRung(setting, doh),
       _clock = clock ?? DateTime.now;

  /// Resolves [host] to one address, or null when no rung produced a usable
  /// one.
  ///
  /// Null rather than a throw, because the caller is what knows whether a
  /// failed resolve means a dead provider, a dead network or a hijacked
  /// resolver, and `classifyProviderFault` is where that vocabulary lives.
  Future<String?> resolve(String host) async {
    // 1. A live cache entry answers without touching either rung, which is what
    //    keeps a channel-hopping session from resolving on every stream open.
    final String? hit = cached(host);

    if (hit != null) return hit;

    // 2. The system rung, because it is an order of magnitude faster than DoH
    //    on the connection this was measured on, and it works for almost
    //    everybody.
    final String? viaSystem = await _ask(_system, host);

    if (viaSystem != null) return viaSystem;

    // 3. DoH only where the user named an endpoint, and only after the system
    //    rung hung, threw, or answered with a blackhole.
    final HostLookup? doh = _doh;

    if (doh == null) return null;

    return _ask(doh, host);
  }

  /// The cached address for [host], or null when there is none or it expired.
  ///
  /// Synchronous and issues no lookup, so the settings screen can render what
  /// the resolver is actually using without provoking network traffic on a
  /// rebuild. An expired entry is dropped on the way past, which is what keeps
  /// the map from growing one dead entry per host ever asked about.
  String? cached(String host) {
    final _CachedAddress? entry = _cache[host];

    if (entry == null) return null;

    if (!_clock().isBefore(entry.expiresAt)) {
      _cache.remove(host);

      return null;
    }

    return entry.address;
  }

  /// Runs one rung under [timeout] and caches whatever it produced.
  ///
  /// Returns null for every kind of failure, because the ladder acts on all of
  /// them identically: a throw, a wait that ran out, and an answer that is a
  /// blackhole all mean "this rung did not resolve the host". Catching to move
  /// to the next rung is the deliberate handling here rather than a swallow;
  /// the failure is not discarded so much as answered, and when the last rung
  /// fails too it reaches the caller as [resolve] returning null.
  Future<String?> _ask(HostLookup lookup, String host) async {
    final HostAnswer answer;

    try {
      answer = await lookup.lookup(host).timeout(timeout);
    } on HostLookupException {
      return null;
    } on TimeoutException {
      return null;
    }

    final String? usable = _firstUsable(host, answer.addresses);

    if (usable == null) return null;

    _remember(host, usable, answer.ttl);

    return usable;
  }

  /// Holds [address] for [host] until its TTL runs out.
  void _remember(String host, String address, Duration? ttl) {
    final Duration lifetime = ttl == null || ttl > ttlCeiling ? ttlCeiling : ttl;

    // A resolver answering with a TTL of zero is asking not to be cached, and
    // obeying it costs one extra lookup rather than an argument: the next
    // resolve simply asks again.
    if (lifetime <= Duration.zero) return;

    _cache[host] = _CachedAddress(address, _clock().add(lifetime));
  }

  /// The DoH rung for [setting], or null where the setting names no endpoint.
  static HostLookup? _dohRung(ResolverSetting setting, HostLookup? substitute) {
    final Uri? endpoint = setting.dohEndpoint;

    if (endpoint == null) return null;

    return substitute ?? DohHostLookup(endpoint);
  }

  /// The first address in [addresses] this ladder will hand back for [host].
  ///
  /// Scanning rather than taking the head, so a mixed answer that carries both
  /// an injected blackhole and the real record still resolves instead of
  /// escalating over an address it did not have to use.
  static String? _firstUsable(String host, List<String> addresses) {
    for (final String address in addresses) {
      if (_isUsable(host, address)) return address;
    }

    return null;
  }

  /// Whether [address] can carry traffic for [host].
  ///
  /// Two rejections, and only two. Anything that does not parse as an IP
  /// literal is not an address at all: a DoH answer is untrusted input and its
  /// `data` field carries a hostname on a CNAME record, measured on both
  /// shipped endpoints. And a blackhole answer for a host that is neither
  /// `localhost` nor already a literal is the tampering shape the class doc
  /// describes.
  static bool _isUsable(String host, String address) {
    if (!_isIpLiteral(address)) return false;
    if (_isLiteralOrLocalhost(host)) return true;

    return !_isBlackhole(address);
  }

  /// Whether a blackhole answer can honestly belong to [host]: the name
  /// `localhost`, or a host that is already an IP literal and was therefore
  /// never resolved by anybody who could have tampered with it.
  static bool _isLiteralOrLocalhost(String host) => host.toLowerCase() == 'localhost' || _isIpLiteral(host);

  /// Whether [address] goes nowhere: loopback, unspecified or link-local, in
  /// either family.
  ///
  /// A private-range address is deliberately absent from this list; the class
  /// doc carries why.
  static bool _isBlackhole(String address) {
    final List<int>? octets = _tryParseIPv4(address);

    if (octets != null) {
      // 127.0.0.0/8 loopback, 0.0.0.0 unspecified, 169.254.0.0/16 link-local.
      // The unspecified case is the single address rather than the whole
      // 0.0.0.0/8 RFC 1122 reserves, because that is the shape a tampering
      // resolver actually answers with and widening it is a behaviour change
      // no test covers.
      return octets[0] == 127 || octets.every((int octet) => octet == 0) || (octets[0] == 169 && octets[1] == 254);
    }

    final List<int>? bytes = _tryParseIPv6(address);

    if (bytes == null) return false;

    // fe80::/10 link-local.
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;

    // ::1 loopback and :: unspecified, which differ only in the last byte.
    return bytes.take(15).every((int byte) => byte == 0) && bytes[15] <= 1;
  }

  /// Whether [candidate] is an IP literal in either family.
  static bool _isIpLiteral(String candidate) => _tryParseIPv4(candidate) != null || _tryParseIPv6(candidate) != null;

  /// [candidate] as four octets, or null when it is not dotted-decimal IPv4.
  ///
  /// `Uri.parseIPv4Address` lives in `dart:core` rather than in a platform
  /// library, which is what lets the tamper check run with no platform under
  /// it, and it hands back the raw bytes so the prefixes above are arithmetic
  /// rather than string matching on a text form with several spellings. The
  /// same trick is what `ResolverSetting` validates a custom endpoint with.
  static List<int>? _tryParseIPv4(String candidate) {
    try {
      return Uri.parseIPv4Address(candidate);
    } on FormatException {
      return null;
    }
  }

  /// [candidate] as sixteen bytes, or null when it is not an IPv6 literal.
  static List<int>? _tryParseIPv6(String candidate) {
    try {
      return Uri.parseIPv6Address(candidate);
    } on FormatException {
      return null;
    }
  }
}

/// One resolved address and the moment it stops counting.
@immutable
class _CachedAddress {
  final String address;
  final DateTime expiresAt;

  const _CachedAddress(this.address, this.expiresAt);
}
