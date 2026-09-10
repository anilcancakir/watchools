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
  /// is the only place it is written, and [describe] and [redact] are the only
  /// two ways anything carrying it becomes printable.
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

  /// The same guarantee as [describe], for prose that merely contains a URL.
  ///
  /// Returns [text] with every spelling of [password] and [username] replaced
  /// by the marker, and everything else byte for byte as it arrived. This is
  /// [describe]'s sibling rather than its replacement: a `Uri` can be taken
  /// apart, a log line cannot, and the leak this closes arrives as a log line.
  /// mpv is subscribed at `warn`
  /// (`packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift:127`)
  /// and its lines are forwarded verbatim (`:465`), FFmpeg's reconnect warning
  /// names the URL it is retrying, and a stream URL carries the credential in
  /// its path. That channel is the only signal a subscription token is lapsing,
  /// so it cannot be switched off; it has to be cleaned instead.
  ///
  /// The text is never parsed for a URL. Prose of unknown shape has no URL
  /// boundary to find, and a parser that guesses one wrong passes the secret
  /// through, so a substring replacement is the honest tool.
  ///
  /// [password] goes before [username], because a password containing the
  /// username (`bob-s3cret` for `bob`) survives the other order: the username
  /// pass rewrites its first three characters and the password no longer
  /// matches itself. An empty secret is skipped rather than replaced, because
  /// `replaceAll('')` matches between every character and would return a string
  /// of nothing but markers.
  ///
  /// Four spellings per secret, because a URL escapes what it embeds and the
  /// three encoders that can produce one all disagree.
  ///
  /// [Uri.encodeComponent] keeps RFC 2396's marks and writes a space as `%20`.
  /// [Uri.encodeQueryComponent] escapes `!*'()` as well and writes a space as
  /// `+`. And `Uri(pathSegments:)`, which is what actually builds a stream URL
  /// (`xtream_stream_url.dart`), escapes **less than either**: `@`, `:` and `&`
  /// are all legal in an RFC 3986 path segment, so it leaves them alone. One
  /// password shows all three apart: `p@ss word` is `p%40ss%20word` through
  /// `encodeComponent`, `p%40ss+word` through `encodeQueryComponent`, and
  /// `p@ss%20word` on the wire. Enumerating the first two and stopping is what
  /// an earlier version of this method did, and a paired test against a URL the
  /// builder had actually produced is what caught the third: a `@` in a
  /// password reached a log line intact.
  ///
  /// The fourth form is therefore derived from the same constructor the builder
  /// uses rather than hand-written, so the two cannot drift apart. There is no
  /// public `encodePathSegment` in `dart:core`; a one-segment `Uri` is the only
  /// way to ask for that escaping. Its `path` carries **no** leading separator,
  /// because `Uri` only makes a path absolute when an authority is present, and
  /// stripping one anyway ate the secret's first character and redacted a
  /// nine-tenths match.
  ///
  /// One encoding pass is the ceiling. The URL is always built from the stored
  /// field, so a doubly encoded form would require the stored field to already
  /// be an encoding of the real secret, in which case the stored field is what
  /// the URL carries and its single encoding is this set.
  ///
  /// A `Set` rather than a list: for an alphanumeric secret all four spellings
  /// collapse to one, which is the ordinary case.
  String redact(String text) {
    String redacted = _redactEncodedSegments(text);

    for (final String secret in <String>[password, username]) {
      if (secret.isEmpty) continue;

      final Set<String> forms = <String>{
        secret,
        Uri.encodeComponent(secret),
        Uri.encodeQueryComponent(secret),
        Uri(pathSegments: <String>[secret]).path,
      };

      for (final String form in forms) {
        redacted = redacted.replaceAll(form, _redaction);
      }
    }

    return redacted;
  }

  /// Replaces any run that decodes from base64 into something naming a secret.
  ///
  /// The four literal spellings above cannot reach this, and it is not a
  /// hypothetical shape: the panel answers a stream request with a `302` whose
  /// target embeds a token, and the token measured against the fixture decodes
  /// to `username:password:issuedAt`
  /// (`evidence/12-token-remint.txt`). Base64 is encoding rather than
  /// encryption, so the credential is fully present and none of the literal
  /// forms appears anywhere in the encoded run.
  ///
  /// Reachable on the one channel that cannot be switched off: `reconnect=1`
  /// is set in the plugin's `stream-lavf-o`
  /// (`MpvEngine.swift:68`), mpv follows the redirect, and FFmpeg's reconnect
  /// warning names the URL it is retrying, which by then is the tokenised one.
  ///
  /// Matched on a **decoding** rather than on a pattern, because a token's
  /// layout is the panel's choice and the next one will not look like this one.
  /// Three guards keep it from rewriting innocent text: a minimum length, a
  /// successful base64 decode, and a UTF-8 decoding that actually contains a
  /// secret. A run that fails any of the three is left exactly as it arrived.
  /// No `/` in the run, deliberately. It is part of the standard base64
  /// alphabet, and including it made the match greedily swallow path
  /// separators: `/live/play/<token>/10001` came back as one run that decodes
  /// to nothing and so was left alone, with the token inside it. A token
  /// embedded in a URL path cannot contain `/` anyway, because that would end
  /// the segment, and the URL-safe alphabet spells the same two characters
  /// `-` and `_`.
  String _redactEncodedSegments(String text) => text.replaceAllMapped(
    RegExp(r'[A-Za-z0-9+_=-]{16,}'),
    (Match match) => _namesASecret(match[0]!) ? _redaction : match[0]!,
  );

  /// Whether [run] decodes from base64 into text containing either secret.
  bool _namesASecret(String run) {
    final String? decoded = _decodeBase64(run);

    if (decoded == null) return false;

    return (password.isNotEmpty && decoded.contains(password)) || (username.isNotEmpty && decoded.contains(username));
  }

  /// [run] as UTF-8 out of base64, or null when it is not both.
  ///
  /// Tries the URL alphabet as well as the standard one, because a panel that
  /// puts a token in a path has reason to prefer it, and pads to a multiple of
  /// four because a token in a URL usually has its padding stripped.
  String? _decodeBase64(String run) {
    final String padded = run.padRight(run.length + (4 - run.length % 4) % 4, '=');

    for (final Codec<List<int>, String> codec in <Codec<List<int>, String>>[base64Url, base64]) {
      try {
        return utf8.decode(codec.decode(padded));
      } on FormatException {
        continue;
      }
    }

    return null;
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
