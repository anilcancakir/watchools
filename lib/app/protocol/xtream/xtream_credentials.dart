import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

/// The user's Xtream Codes panel credential, as one immutable record.
///
/// Watchools supplies no streams: everything the four screens show comes from
/// a subscription the user already has, and this record is the whole of what we
/// know about it. Every later call in the protocol layer concatenates onto
/// [baseUrl] and signs itself with [username], [password] and [userAgent], so
/// a field missing here is a field the client cannot send.
///
/// It is a value type rather than a Magic ORM model because [Vault] is the only
/// correct home for it: the ORM writes an unencrypted SQLite row, and a
/// provider credential is the one thing in this app that must not sit in one.
/// [Vault] stores strings only (`magic/lib/src/facades/vault.dart:17`), so the
/// record serialises itself to JSON under the single [vaultKey].
///
/// There is no onboarding screen yet. [save] is written to be callable from a
/// test or a debug hook, which is how a development build gets a credential in.
@immutable
class XtreamCredentials {
  /// The one and only Vault key the record lives under.
  ///
  /// A single fixed key is what makes [clear] total: a second key would leave
  /// half a credential behind after a sign-out, and half a credential is a
  /// password nobody can see and nobody can delete.
  static const String vaultKey = 'xtream_credentials';

  /// What replaces a secret in anything a human or a log file reads.
  static const String _redaction = '***';

  /// The panel root, with no trailing slash: `http://host:8080`.
  ///
  /// Normalised by the constructor rather than by each caller, because the
  /// endpoints are built by concatenation (`$baseUrl/player_api.php`) and a
  /// trailing slash there produces a double slash that some panels 404 on.
  final String baseUrl;

  /// The panel username. Also a path segment in every stream URL, which is why
  /// [describe] has to redact path segments and not only the query.
  final String username;

  /// The panel password, in plain text because the protocol sends it that way.
  ///
  /// Never reaches [toString] and never reaches an exception message. `Vault`
  /// is the only place it is written and [describe] is the only way a URL
  /// carrying it becomes printable.
  final String password;

  /// The `User-Agent` this provider is addressed with.
  ///
  /// Per-provider rather than global: resellers key their access control to it.
  /// The header name has to be spelled exactly `User-Agent` at the call site,
  /// because ExoPlayer's lookup is case sensitive and a lowercase key silently
  /// ships `User-Agent: ExoPlayer` instead.
  final String userAgent;

  /// Creates a credential, normalising and validating [baseUrl].
  ///
  /// Throws [ArgumentError] when [baseUrl] carries no `http`/`https` scheme,
  /// no host, or credentials in its authority. That rejection is not cosmetic:
  /// Dio prepends the driver's
  /// configured `base_url` to any path not matching `https?:`
  /// (`dio-5.9.2/lib/src/options.dart:630`), so a scheme-less panel URL does
  /// not fail loudly, it silently addresses the wrong server.
  XtreamCredentials({required String baseUrl, required this.username, required this.password, required this.userAgent})
    : baseUrl = _normaliseBaseUrl(baseUrl);

  /// Writes the record over whatever [vaultKey] held before.
  Future<void> save() => Vault.put(vaultKey, jsonEncode(_toJson()));

  /// The stored credential, or null when the user has none configured.
  ///
  /// Throws [FormatException] when [vaultKey] holds something that is not this
  /// record: not JSON, not an object, or an object missing a string field. The
  /// payload is untrusted on the way in (an older build's shape, a partial
  /// write) and swallowing that would present "no provider configured" to
  /// someone who has one. The exception names the field and never its value,
  /// because a `FormatException` reaches a log.
  static Future<XtreamCredentials?> load() async {
    final String? payload = await Vault.get(vaultKey);

    if (payload == null) return null;

    final Object? decoded = jsonDecode(payload);

    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Vault key "$vaultKey" does not hold an Xtream credential object.');
    }

    return XtreamCredentials(
      baseUrl: _requireString(decoded, 'base_url'),
      username: _requireString(decoded, 'username'),
      password: _requireString(decoded, 'password'),
      userAgent: _requireString(decoded, 'user_agent'),
    );
  }

  /// Forgets the credential entirely.
  static Future<void> clear() => Vault.delete(vaultKey);

  /// The only sanctioned way to name a provider URL in a log, an error or a
  /// diagnostic.
  ///
  /// Returns scheme, host, port and path, with the query dropped and any path
  /// segment equal to [username] or [password] replaced. Dropping the query
  /// alone is not enough and dropping the path is too much: a panel call keeps
  /// the credential in the query (`player_api.php?username=&password=`) while a
  /// stream URL keeps it in the path (`/live/<username>/<password>/<id>.ts`),
  /// and the path is the half that says which endpoint failed.
  ///
  /// `userInfo` goes with the query, since `http://user:pass@host` is the third
  /// place a URL can carry a secret.
  String describe(Uri url) {
    final List<String> segments = url.pathSegments
        .map((String segment) => segment == username || segment == password ? _redaction : segment)
        .toList();

    return Uri(
      scheme: url.scheme,
      host: url.host,
      port: url.hasPort ? url.port : null,
      pathSegments: segments,
    ).toString();
  }

  @override
  bool operator ==(Object other) =>
      other is XtreamCredentials &&
      other.baseUrl == baseUrl &&
      other.username == username &&
      other.password == password &&
      other.userAgent == userAgent;

  @override
  int get hashCode => Object.hash(baseUrl, username, password, userAgent);

  /// Names the provider and the user, and redacts the password.
  ///
  /// A value type's `toString` is what an assertion failure, a `Log` line and
  /// an IDE inspector all print, so this is the reason the password is not
  /// interpolated anywhere in this class.
  @override
  String toString() =>
      'XtreamCredentials(baseUrl: $baseUrl, username: $username, '
      'password: $_redaction, userAgent: $userAgent)';

  /// The wire shape stored under [vaultKey].
  Map<String, String> _toJson() => <String, String>{
    'base_url': baseUrl,
    'username': username,
    'password': password,
    'user_agent': userAgent,
  };

  /// Trims, strips trailing slashes, and rejects anything Dio would treat as a
  /// relative path.
  ///
  /// The scheme is matched against a whitelist rather than tested for
  /// emptiness, because `Uri.parse('host:8080')` reads `host` as the scheme and
  /// an emptiness check waves it through.
  ///
  /// A URL carrying `userInfo` is rejected rather than stripped. Xtream sends
  /// the credential as query parameters, so `http://user:pass@host:8080` is a
  /// malformed panel root rather than a supported one, and accepting it would
  /// put a password inside [baseUrl], which [toString] prints in full.
  ///
  /// The rejected value is never interpolated into the message, for the same
  /// reason: the string being rejected is exactly the one that may carry a
  /// secret, and an `ArgumentError` reaches a log.
  static String _normaliseBaseUrl(String baseUrl) {
    final String normalised = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final Uri? parsed = Uri.tryParse(normalised);

    if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https') || parsed.host.isEmpty) {
      throw ArgumentError('A panel URL needs an http:// or https:// scheme and a host');
    }

    if (parsed.userInfo.isNotEmpty) {
      throw ArgumentError(
        'A panel URL must not carry credentials in its authority; Xtream sends them as query parameters',
      );
    }

    return normalised;
  }

  /// Reads a required string field, naming the field and never its value.
  static String _requireString(Map<String, Object?> json, String field) {
    final Object? value = json[field];

    if (value is! String) {
      throw FormatException('Vault key "$vaultKey" is missing the string field "$field".');
    }

    return value;
  }
}
