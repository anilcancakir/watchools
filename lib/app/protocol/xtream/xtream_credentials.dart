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

  /// One percent-escape of a base64 character: `%2B`, `%2F` or `%3D`, in
  /// either case. Shared by the run pattern and the unescaper so neither can
  /// admit a character the other does not handle.
  static const String _escapedBase64Char = '%(?:2[BbFf]|3[Dd])';

  /// One character of a base64 run's **body**, escaped or not.
  ///
  /// `=` is deliberately absent and belongs to [_base64Padding] instead. It is
  /// padding, so base64 only ever puts it at the end, and admitting it in the
  /// body let a run reach backwards through a query parameter's `=` and match
  /// `token=<token>` as one string. That decodes to nothing, because a `=` in
  /// the middle is invalid padding, so the run was left alone with the token
  /// inside it: the escaped-token leak this pattern exists to close, reopened
  /// by the character class rather than by the escaping.
  static const String _base64RunChar = '(?:[A-Za-z0-9+_-]|%2[BbFf])';

  /// Base64 padding, escaped or not, of which there can be at most two.
  static const String _base64Padding = '(?:=|%3[Dd])';

  /// The panel root, with no trailing slash: `http://host:8080`.
  ///
  /// Normalised by the constructor rather than by each caller, because the
  /// endpoints are built by concatenation (`$baseUrl/player_api.php`) and a
  /// trailing slash there produces a double slash that some panels 404 on.
  final String baseUrl;

  /// The panel username. Also a path segment in every stream URL, which is why
  /// [redact] has to cover the escaping a path segment uses and not only the
  /// query encoders.
  final String username;

  /// The panel password, in plain text because the protocol sends it that way.
  ///
  /// Never reaches [toString] and never reaches an exception message. `Vault`
  /// is the only place it is written, and [redact] is the only way anything
  /// carrying it becomes printable.
  final String password;

  /// The `User-Agent` this provider is addressed with.
  ///
  /// Per-provider rather than global: resellers key their access control to it.
  /// The header name has to be spelled exactly `User-Agent` at the call site,
  /// because ExoPlayer's lookup is case sensitive and a lowercase key silently
  /// ships `User-Agent: ExoPlayer` instead.
  final String userAgent;

  /// The user's chosen resolver, or null for the system default.
  ///
  /// A raw stored string exactly as [ResolverSetting.storedValue] wrote it
  /// (`'cloudflare'`, `'google'`, an IP literal, or an `https` DoH endpoint),
  /// left unparsed here because this class is only the storage boundary:
  /// [ResolverSetting.parse] is what turns it back into a validated choice.
  /// Null is also what a wrong-typed or missing stored value reads back as;
  /// see [_optionalString].
  final String? resolver;

  /// The user's chosen background-playback behaviour, or null for the
  /// default (tear the core down).
  ///
  /// A raw stored string exactly as `BackgroundPlayback.storedValue` wrote it
  /// (`'audio'`, `'pictureInPicture'`), left unparsed here for the same
  /// reason as [resolver]: this class is only the storage boundary, and
  /// `BackgroundPlayback.parse` is what turns it back into a validated
  /// choice. Null is also what a wrong-typed or missing stored value reads
  /// back as; see [_optionalString].
  final String? backgroundPlayback;

  /// Creates a credential, normalising and validating [baseUrl].
  ///
  /// Throws [ArgumentError] when [baseUrl] carries no `http`/`https` scheme,
  /// no host, or credentials in its authority. That rejection is not cosmetic:
  /// Dio prepends the driver's
  /// configured `base_url` to any path not matching `https?:`
  /// (`dio-5.9.2/lib/src/options.dart:630`), so a scheme-less panel URL does
  /// not fail loudly, it silently addresses the wrong server.
  XtreamCredentials({
    required String baseUrl,
    required this.username,
    required this.password,
    required this.userAgent,
    this.resolver,
    this.backgroundPlayback,
  }) : baseUrl = _normaliseBaseUrl(baseUrl);

  /// Writes the record over whatever [vaultKey] held before.
  Future<void> save() => Vault.put(vaultKey, jsonEncode(_toJson()));

  /// A credential handed in at compile time, or null when none was.
  ///
  /// The development way in, and it exists because there is currently **no
  /// other one on macOS**. `Vault` is the Keychain, a sandboxed macOS build
  /// has no `keychain-access-groups` entitlement, and adding one makes the
  /// build demand a development certificate, so every `Vault.put` fails with
  /// OSStatus -34018 ("A required entitlement isn't present"). Measured
  /// through the running app, with and without the sandbox. The consequence is
  /// the whole product: no credential can be stored, so `hasCredentials` is
  /// false forever, all four screens fall back to the fixture, and a fixture
  /// channel has no `streamId`, so nothing is playable on the one platform
  /// that has a player.
  ///
  /// `--dart-define` rather than a file, and the choice is forced rather than
  /// preferred. `.env.local` is the file `CLAUDE.md` reserves for this, but
  /// magic loads exactly one env file and reads it as a **Flutter asset**, and
  /// a declared asset that is missing fails the build outright, so declaring
  /// `.env.local` would make every fresh checkout require one. The values
  /// still live in `.env.local`; `tool/dev/run_with_provider.sh` reads them
  /// from there and passes them as defines, so nothing new is committed and
  /// the file keeps the job it was reserved for.
  ///
  /// A define is also the safest shape available: it is compile-time, so a
  /// build that was not given one cannot carry a credential at all, and there
  /// is no runtime path that could read a stale value out of a shipped bundle.
  ///
  /// Returns null unless the base URL, the user name and the password are
  /// **all three** present. A partial define set is a mistake at the launch
  /// command rather than a configuration to honour, and guessing a default for
  /// a password is the one thing this must never do. The user agent does have a
  /// default, because it is not a secret and every request needs one.
  ///
  /// The three values are named parameters defaulting to their defines rather
  /// than read inline, which is what makes any of this testable. A define is
  /// compile-time, so a `flutter test` run has none and an inline read would
  /// leave every branch here but the null one unreachable from a test. The
  /// same seam shape as `MpvPlaybackEngine.toggleWakelock` and
  /// `PlaybackLayout.onBack`: the default is the real thing, and a test passes
  /// its own.
  static XtreamCredentials? fromEnvironment({
    String baseUrl = const String.fromEnvironment(_envBaseUrl),
    String username = const String.fromEnvironment(_envUsername),
    String password = const String.fromEnvironment(_envPassword),
    String userAgent = const String.fromEnvironment(_envUserAgent, defaultValue: 'Watchools/1.0'),
  }) {
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) return null;

    return XtreamCredentials(baseUrl: baseUrl, username: username, password: password, userAgent: userAgent);
  }

  /// The define names, spelled once. `String.fromEnvironment` needs a constant,
  /// so these are `const` and not a list a loop could walk.
  static const String _envBaseUrl = 'XTREAM_BASE_URL';
  static const String _envUsername = 'XTREAM_USERNAME';
  static const String _envPassword = 'XTREAM_PASSWORD';
  static const String _envUserAgent = 'XTREAM_USER_AGENT';

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
      resolver: _optionalString(decoded, 'resolver'),
      backgroundPlayback: _optionalString(decoded, 'background_playback'),
    );
  }

  /// Forgets the credential entirely.
  static Future<void> clear() => Vault.delete(vaultKey);

  /// The only sanctioned way to name a provider URL, or anything containing
  /// one, in a log, an error or a diagnostic.
  ///
  /// Returns [text] with every spelling of [password] and [username] replaced
  /// by the marker, and everything else byte for byte as it arrived.
  ///
  /// Prose rather than a `Uri`, and there is deliberately no `Uri` sibling. One
  /// existed, taking a URL apart to drop the query and rewrite matching path
  /// segments, and it went the whole implementation without a caller: every
  /// leak this class actually has to close arrives as a line of prose from
  /// somewhere below, where there is no `Uri` to take apart. A second door with
  /// weaker cover and no traffic is how a later reader picks the wrong one.
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
  /// No bare `/` in the run, deliberately. It is part of the standard base64
  /// alphabet, and including it made the match greedily swallow path
  /// separators: `/live/play/<token>/10001` came back as one run that decodes
  /// to nothing and so was left alone, with the token inside it. A token
  /// embedded in a URL path cannot contain `/` anyway, because that would end
  /// the segment, and the URL-safe alphabet spells the same two characters
  /// `-` and `_`.
  ///
  /// An **escaped** one is a different matter and is admitted: a token in a
  /// query parameter is percent-encoded, so a standard-alphabet token arrives
  /// as `dXNlcg%2FcGFzcw`. `%` was not in the run class, so that split into two
  /// runs neither of which decodes, and the token went through. Exactly three
  /// escapes are admitted, `%2B`, `%2F` and `%3D`, either case: they are the
  /// base64 characters a URL escapes, and they are the only ones that can be
  /// put back without changing what the run means. Admitting `%[0-9A-Fa-f]{2}`
  /// wholesale would be worse than the gap it closes, because `%20` would then
  /// join a token to the next word and the joined run decodes to nothing.
  ///
  /// Body then padding rather than one class for both, which is
  /// [_base64RunChar]'s own note and the correction that made the escaped case
  /// actually work.
  String _redactEncodedSegments(String text) => text.replaceAllMapped(
    RegExp('$_base64RunChar{16,}$_base64Padding{0,2}'),
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
  /// Both alphabets in one pass rather than one codec per attempt. `base64Url`
  /// and `base64` share a decoder that accepts `-_` and `+/` interchangeably
  /// (`convert/base64.dart`, `Base64Decoder`), so an earlier version's loop
  /// over the two ran its second iteration only when the first threw, which is
  /// exactly when the second throws too: dead code that read as coverage.
  ///
  /// Unescaped first, then padded to a multiple of four, because a token in a
  /// URL usually has its padding stripped and the escapes are part of what the
  /// run class admits.
  String? _decodeBase64(String run) {
    final String unescaped = _unescapeBase64(run);
    final String padded = unescaped.padRight(unescaped.length + (4 - unescaped.length % 4) % 4, '=');

    // Malformed bytes are allowed through as replacement characters rather
    // than rejected, and that is the second half of the same defect. A token
    // is commonly a readable payload plus a **binary** signature, and one
    // invalid UTF-8 byte anywhere in it made the strict decode throw, so the
    // whole run was left alone with the credential sitting in plain ASCII at
    // its front. The guard that stops innocent text being rewritten is
    // [_namesASecret]'s containment check, not this decode's strictness.
    try {
      return utf8.decode(base64Url.decode(padded), allowMalformed: true);
    } on FormatException {
      return null;
    }
  }

  /// [run] with the three escaped base64 characters put back.
  ///
  /// Written from the same pattern the run class admits, so the two cannot
  /// drift: a character admitted there and not put back here would corrupt the
  /// decode and hide the token, which is the failure the escape handling exists
  /// to close.
  static String _unescapeBase64(String run) => run.replaceAllMapped(
    RegExp(_escapedBase64Char),
    (Match match) => String.fromCharCode(int.parse(match[0]!.substring(1), radix: 16)),
  );

  @override
  bool operator ==(Object other) =>
      other is XtreamCredentials &&
      other.baseUrl == baseUrl &&
      other.username == username &&
      other.password == password &&
      other.userAgent == userAgent &&
      other.resolver == resolver &&
      other.backgroundPlayback == backgroundPlayback;

  @override
  int get hashCode => Object.hash(baseUrl, username, password, userAgent, resolver, backgroundPlayback);

  /// Names the provider and the user, and redacts the password and the
  /// resolver.
  ///
  /// A value type's `toString` is what an assertion failure, a `Log` line and
  /// an IDE inspector all print, so this is the reason the password is not
  /// interpolated anywhere in this class.
  ///
  /// [resolver] joins it, at the whole value rather than at its query. A named
  /// choice (`cloudflare`) is not a secret, but a custom endpoint can be one in
  /// its PATH rather than after the `?`: `https://dns.nextdns.io/<profile-id>`
  /// is a shape [ResolverSetting] accepts and that segment identifies the user.
  /// Redacting the whole value is the only rule that does not have to know
  /// which shape it was handed, and what it costs is a debug line that says
  /// less about a setting nobody debugs from a `toString`.
  ///
  /// **Not added to [redact], deliberately.** That helper exists for mpv's log
  /// lines, and mpv never sees a resolver: the ladder runs in Dart, over the
  /// app's own HTTP client. The only other interpolation is
  /// `HostLookupException`, which `HostResolver` catches and drops without
  /// logging. Adding a third secret to the loop would defend a path that does
  /// not exist, and would do it badly, because a short literal like `1.1.1.1`
  /// would start rewriting any log line that happened to contain it.
  ///
  /// [backgroundPlayback] is written literally, unlike [resolver]. A
  /// `BackgroundPlayback` name is one of three fixed constants and carries
  /// nothing about the user, so there is nothing here to redact.
  @override
  String toString() =>
      'XtreamCredentials(baseUrl: $baseUrl, username: $username, '
      'password: $_redaction, userAgent: $userAgent, '
      'resolver: ${resolver == null ? null : _redaction}, '
      'backgroundPlayback: $backgroundPlayback)';

  /// The wire shape stored under [vaultKey].
  ///
  /// [resolver] is omitted rather than written as `null` when the setting is
  /// the system one, so a user who never touches this feature keeps writing
  /// the same four-key blob every existing install already has on disk.
  Map<String, String> _toJson() => <String, String>{
    'base_url': baseUrl,
    'username': username,
    'password': password,
    'user_agent': userAgent,
    'resolver': ?resolver,
    'background_playback': ?backgroundPlayback,
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

  /// Reads an optional string field, returning null rather than throwing for
  /// both a missing key and a value present with the wrong type.
  ///
  /// The asymmetry with [_requireString] is deliberate. [_requireString]'s
  /// [FormatException] is caught in `ProviderSession._loadCredentials`
  /// (`provider_session.dart:494`) and rendered as `ProviderFault.expired`,
  /// which sends the user to re-enter a credential that is perfectly good
  /// over one optional field of the wrong shape. A bare nullable-string cast
  /// would be worse, not better: it throws [TypeError] for a wrong-typed
  /// value rather than returning null, and neither that catch nor the
  /// `MagicVaultException` catch beside it (`:498`) handles a [TypeError], so
  /// the app would boot to nothing, because `load()` is awaited inside
  /// `Magic.init()` before `runApp()`. A resolver value this cannot read
  /// means "use the system resolver", which is exactly what the user had
  /// before this feature existed.
  static String? _optionalString(Map<String, Object?> json, String field) {
    final Object? value = json[field];

    return value is String ? value : null;
  }
}
