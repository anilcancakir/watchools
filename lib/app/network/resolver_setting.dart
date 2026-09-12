import 'package:flutter/foundation.dart';

/// The four resolvers a user can pick from the provider form.
///
/// Quad9 is deliberately not a fifth member. Its JSON DoH endpoint answered
/// `400 DoH unable to decode BASE64-URL` on port 443, and port 5053, which its
/// own documentation names for the JSON API, timed out entirely, both
/// measured from a Turkish connection on 2026-09-11. Cloudflare and Google
/// both answered 200 in the same run.
enum ResolverChoice {
  /// Whatever the operating system already resolves with. The default, and
  /// the only choice a user who never opens this feature ever has.
  system,

  /// `https://cloudflare-dns.com/dns-query`.
  cloudflare,

  /// `https://dns.google/resolve`.
  google,

  /// A resolver the user typed themselves: an IP literal or an https URL.
  /// [ResolverSetting.customValue] carries the literal.
  custom,
}

/// The parsed and validated form of a resolver a user picked.
///
/// [XtreamCredentials.resolver] carries the raw string this class produces
/// through [storedValue] and reads back through [parse]; that string is the
/// whole of the round trip, so this class is the only place that decides what
/// counts as a resolver at all.
@immutable
class ResolverSetting {
  /// Which of the four choices this is.
  final ResolverChoice choice;

  /// The literal the user typed, for [ResolverChoice.custom] only. Null for
  /// the other three, whose endpoints are fixed.
  final String? customValue;

  const ResolverSetting._(this.choice, this.customValue);

  /// The system resolver: no override, no [dohEndpoint].
  static const ResolverSetting system = ResolverSetting._(ResolverChoice.system, null);

  /// Cloudflare's DoH resolver.
  static const ResolverSetting cloudflare = ResolverSetting._(ResolverChoice.cloudflare, null);

  /// Google's DoH resolver.
  static const ResolverSetting google = ResolverSetting._(ResolverChoice.google, null);

  /// Parses [stored], the raw value out of [XtreamCredentials.resolver].
  ///
  /// Returns [system] for null, for a name that is none of `system`,
  /// `cloudflare` or `google`, and for a custom literal that fails
  /// [_normaliseCustom]. All three are the same outcome on purpose: a
  /// resolver value this cannot make sense of means "use the system
  /// resolver", which is exactly what the user had before this feature
  /// existed, never a thrown exception over a setting nobody is forced to
  /// touch.
  static ResolverSetting parse(String? stored) {
    switch (stored) {
      case null:
      case 'system':
        return system;
      case 'cloudflare':
        return cloudflare;
      case 'google':
        return google;
    }

    final String? normalised = _normaliseCustom(stored);

    return normalised == null ? system : ResolverSetting._(ResolverChoice.custom, normalised);
  }

  /// The string [XtreamCredentials.resolver] should carry, or null for the
  /// system resolver so a user who never touches this feature keeps writing
  /// the same four-key credential blob.
  String? get storedValue {
    switch (choice) {
      case ResolverChoice.system:
        return null;
      case ResolverChoice.cloudflare:
        return 'cloudflare';
      case ResolverChoice.google:
        return 'google';
      case ResolverChoice.custom:
        return customValue;
    }
  }

  /// The DNS-over-HTTPS endpoint to query, or null to leave DNS to the
  /// operating system.
  ///
  /// A custom https URL is used exactly as typed: the user named the whole
  /// endpoint. A custom IP literal has no path of its own, so one is assumed:
  /// `/dns-query`, the path RFC 8484 standardises and the one Cloudflare's own
  /// endpoint uses.
  Uri? get dohEndpoint {
    switch (choice) {
      case ResolverChoice.system:
        return null;
      case ResolverChoice.cloudflare:
        return Uri.parse('https://cloudflare-dns.com/dns-query');
      case ResolverChoice.google:
        return Uri.parse('https://dns.google/resolve');
      case ResolverChoice.custom:
        return _customEndpoint(customValue!);
    }
  }

  /// [value] as typed, unless it is a bare IPv6 literal, which is bracketed:
  /// building a URL authority from raw colons is ambiguous with the `:port`
  /// separator, and RFC 3986 requires the brackets.
  static Uri _customEndpoint(String value) {
    if (value.startsWith('https://')) return Uri.parse(value);

    final String host = !value.startsWith('[') && _isIPv6(value) ? '[$value]' : value;

    return Uri.parse('https://$host/dns-query');
  }

  /// [raw] as a validated custom resolver, or null when it is neither.
  ///
  /// Accepts an IP literal, optionally carrying `:port` (IPv6 bracketed the
  /// way a URL authority requires when a port follows), or an `https` URL.
  /// Never a bare hostname: a hostname would have to be resolved by the
  /// resolver it is replacing, which bootstraps the ladder on itself. The
  /// parse-and-reject shape mirrors `XtreamCredentials._normaliseBaseUrl`.
  static String? _normaliseCustom(String raw) {
    final String trimmed = raw.trim();

    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('https://')) return _validHttpsUrl(trimmed) ? trimmed : null;

    return _validIpLiteral(trimmed) ? trimmed : null;
  }

  /// Whether [candidate] is an `https` URL with a non-empty host.
  ///
  /// The host inside it may be a hostname, unlike a bare custom value, which
  /// [_normaliseCustom] refuses when it is one. The asymmetry is deliberate and
  /// an earlier version of this comment justified it wrongly, by saying the
  /// endpoint is "what the user typed rather than what a bootstrap resolver
  /// would have to look up". It is both: `DohHostLookup` opens an `HttpClient`
  /// against this host, so a hostname here IS looked up by the system resolver
  /// first, and the two endpoints this app ships (`cloudflare-dns.com`,
  /// `dns.google`) are hostnames. What the refusal on a BARE value prevents is
  /// narrower and still worth it: a bare hostname would be the whole setting,
  /// leaving the ladder with nothing but a name it cannot resolve when the
  /// system resolver is the thing that is broken.
  ///
  /// A user facing a wholesale hijack has an escape and it is measured rather
  /// than assumed: `https://1.1.1.1/dns-query` and `https://8.8.8.8/resolve`
  /// both answered 200 with a valid chain from Dart's own TLS on 2026-09-12,
  /// so an IP-literal endpoint needs no name resolved at all.
  static bool _validHttpsUrl(String candidate) {
    final Uri? parsed = Uri.tryParse(candidate);

    return parsed != null && parsed.scheme == 'https' && parsed.host.isNotEmpty;
  }

  /// Whether [candidate] is an IPv4 or IPv6 literal, optionally followed by a
  /// port. An IPv6 literal needs `[...]` around it before a port can follow,
  /// the same authority syntax a URL uses; without a port it is bare.
  ///
  /// The ambiguous case is a bare IPv6 address, which is itself full of
  /// colons: splitting on the last one and demanding an IPv4 host on that
  /// branch, rather than any host, is what keeps `2606:4700:4700::1111` from
  /// being misread as a host of `2606:4700:4700:` and a port of `1111`.
  static bool _validIpLiteral(String candidate) {
    final RegExpMatch? bracketed = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(candidate);

    if (bracketed != null) {
      return _isIPv6(bracketed.group(1)!) && _validPort(bracketed.group(2)!);
    }

    final int lastColon = candidate.lastIndexOf(':');

    if (lastColon > 0) {
      final String host = candidate.substring(0, lastColon);
      final String port = candidate.substring(lastColon + 1);

      if (_isIPv4(host) && _validPort(port)) return true;
    }

    return _isIPv4(candidate) || _isIPv6(candidate);
  }

  /// Whether [value] parses as a port: an integer strictly between 0 and
  /// 65536.
  static bool _validPort(String value) {
    final int? port = int.tryParse(value);

    return port != null && port > 0 && port <= 65535;
  }

  /// Whether [candidate] is a dotted-decimal IPv4 address. `Uri.parseIPv4Address`
  /// is `dart:core`, not `dart:io`, so this stays available on the web target.
  static bool _isIPv4(String candidate) {
    try {
      Uri.parseIPv4Address(candidate);

      return true;
    } on FormatException {
      return false;
    }
  }

  /// Whether [candidate] is an unbracketed IPv6 address.
  static bool _isIPv6(String candidate) {
    try {
      Uri.parseIPv6Address(candidate);

      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ResolverSetting && other.choice == choice && other.customValue == customValue;

  @override
  int get hashCode => Object.hash(choice, customValue);

  /// Names the choice and redacts a custom literal.
  ///
  /// `XtreamCredentials.toString()` redacts the resolver, and redacting it
  /// there alone was not enough: this type is reachable on its own through
  /// `ProviderSession.providerResolution` and `ProviderSetupFacade.resolver`,
  /// so a value type printed by an assertion failure or an IDE inspector would
  /// have carried the literal anyway. A custom endpoint can identify the user
  /// in its path, `https://dns.nextdns.io/<profile-id>` being the shape this
  /// class accepts, so the whole literal goes rather than its query.
  ///
  /// The three named choices print as themselves. `cloudflare` is not a secret
  /// and a debug line that cannot tell them apart is worth less than one that
  /// can.
  @override
  String toString() =>
      'ResolverSetting(choice: $choice, '
      'customValue: ${customValue == null ? null : _redaction})';

  /// What a custom literal prints as, matching `XtreamCredentials`'s own
  /// redaction so the two read alike in one log line.
  static const String _redaction = '***';
}
