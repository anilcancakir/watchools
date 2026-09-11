import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/protocol/xtream/xtream_account.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/protocol/xtream/xtream_stream_url.dart';

XtreamCredentials _record({String baseUrl = 'http://panel.example:8080', String? resolver}) => XtreamCredentials(
  baseUrl: baseUrl,
  username: 'bob',
  password: 's3cret',
  userAgent: 'Watchools/1.0',
  resolver: resolver,
);

/// A credential whose secrets need escaping, so the three spellings of one
/// secret are three different strings: `b@b` encodes to `b%40b` either way,
/// while `p@ss word` is `p%40ss%20word` in a path and `p%40ss+word` in a query.
XtreamCredentials _punctuated() =>
    XtreamCredentials(baseUrl: 'http://h:8080', username: 'b@b', password: 'p@ss word', userAgent: 'Watchools/1.0');

/// Every write the fake recorded, in order. The count is the assertion that
/// matters: a second Vault key would make [XtreamCredentials.clear] partial.
List<VaultOperation> _writes(FakeVaultService vault) =>
    vault.recorded.where((VaultOperation op) => op.operation == 'put').toList();

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  group('base URL normalisation', () {
    test('strips a trailing slash, because every later call concatenates onto it', () {
      expect(_record(baseUrl: 'http://host:8080/').baseUrl, 'http://host:8080');
      expect(_record(baseUrl: 'http://host:8080//').baseUrl, 'http://host:8080');
      expect(_record(baseUrl: '  http://host:8080/  ').baseUrl, 'http://host:8080');
    });

    test('keeps a panel path prefix, minus its trailing slash', () {
      expect(_record(baseUrl: 'http://host:8080/panel/').baseUrl, 'http://host:8080/panel');
    });

    test('rejects a base URL Http would concatenate onto the driver base_url', () {
      // `host:8080` is the trap: Uri.parse reads `host` as the scheme, so a
      // bare emptiness check on Uri.scheme passes it through.
      expect(() => _record(baseUrl: 'host:8080'), throwsArgumentError);
      expect(() => _record(baseUrl: 'panel.example.com'), throwsArgumentError);
      expect(() => _record(baseUrl: '//host:8080'), throwsArgumentError);
      expect(() => _record(baseUrl: 'ftp://host:8080'), throwsArgumentError);
      expect(() => _record(baseUrl: ''), throwsArgumentError);
    });

    test('accepts https as readily as http', () {
      expect(_record(baseUrl: 'https://host/').baseUrl, 'https://host');
    });

    test('rejects credentials in the authority, which toString would print in full', () {
      expect(() => _record(baseUrl: 'http://bob:s3cret@host:8080'), throwsArgumentError);
    });

    test('rejects without naming the value, so a pasted password never reaches a log', () {
      expect(
        () => _record(baseUrl: 'http://bob:s3cret@host:8080'),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.toString(), 'toString', isNot(contains('s3cret')))),
      );
    });
  });

  group('Vault round trip', () {
    test('save() writes exactly one key and load() returns an equal record', () async {
      final FakeVaultService vault = Vault.fake();

      await _record().save();

      expect(_writes(vault).length, 1);
      expect(_writes(vault).single.key, XtreamCredentials.vaultKey);
      vault.assertWritten(XtreamCredentials.vaultKey);
      expect(await XtreamCredentials.load(), _record());
    });

    test('clear() removes the one key it wrote', () async {
      final FakeVaultService vault = Vault.fake();

      await _record().save();
      await XtreamCredentials.clear();

      vault.assertDeleted(XtreamCredentials.vaultKey);
      vault.assertMissing(XtreamCredentials.vaultKey);
      expect(await XtreamCredentials.load(), isNull);
    });

    test('load() is null on a vault that never held a credential', () async {
      Vault.fake();

      expect(await XtreamCredentials.load(), isNull);
    });

    test('load() normalises the stored base URL the way the constructor does', () async {
      Vault.fake({
        XtreamCredentials.vaultKey: jsonEncode(<String, String>{
          'base_url': 'http://host:8080/',
          'username': 'bob',
          'password': 's3cret',
          'user_agent': 'Watchools/1.0',
        }),
      });

      final XtreamCredentials? loaded = await XtreamCredentials.load();

      expect(loaded?.baseUrl, 'http://host:8080');
    });

    test('load() throws on a payload that is not a credential object', () async {
      Vault.fake({XtreamCredentials.vaultKey: 'not json at all'});

      expect(XtreamCredentials.load, throwsFormatException);
    });

    test('load() reads the exact four-key blob the previous version wrote, resolver null', () async {
      // Every existing install has exactly this shape on disk right now.
      // If load() throws on it, ProviderSession renders ProviderFault.expired
      // and tells the user their working subscription has lapsed.
      Vault.fake({
        XtreamCredentials.vaultKey: jsonEncode(<String, String>{
          'base_url': 'http://host:8080',
          'username': 'bob',
          'password': 's3cret',
          'user_agent': 'Watchools/1.0',
        }),
      });

      final XtreamCredentials? loaded = await XtreamCredentials.load();

      expect(loaded?.resolver, isNull);
    });

    test('load() reads resolver null, throwing neither FormatException nor TypeError, when it is a number', () async {
      Vault.fake({
        XtreamCredentials.vaultKey: jsonEncode(<String, Object>{
          'base_url': 'http://host:8080',
          'username': 'bob',
          'password': 's3cret',
          'user_agent': 'Watchools/1.0',
          'resolver': 42,
        }),
      });

      final XtreamCredentials? loaded = await XtreamCredentials.load();

      expect(loaded?.resolver, isNull);
    });

    test('save() then load() round-trips a resolver value', () async {
      Vault.fake();

      await _record(resolver: 'cloudflare').save();

      expect((await XtreamCredentials.load())?.resolver, 'cloudflare');
    });

    test('save() omits the resolver key entirely when the setting is the system one', () async {
      Vault.fake();

      await _record().save();

      final String payload = (await Vault.get(XtreamCredentials.vaultKey))!;
      expect(jsonDecode(payload), isNot(contains('resolver')));
    });

    test('load() throws when a field is missing or not a string', () async {
      Vault.fake({
        XtreamCredentials.vaultKey: jsonEncode(<String, Object>{'base_url': 'http://host', 'username': 7}),
      });

      expect(XtreamCredentials.load, throwsFormatException);
    });

    test('load() throws without naming the field values, so nothing leaks', () async {
      Vault.fake({
        XtreamCredentials.vaultKey: jsonEncode(<String, Object>{
          'base_url': 'http://host',
          'username': 'bob',
          'password': 42,
          'user_agent': 'Watchools/1.0',
        }),
      });

      await expectLater(
        XtreamCredentials.load(),
        throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', isNot(contains('42')))),
      );
    });
  });

  group('fromEnvironment', () {
    test('a build given no define carries no credential', () {
      // The property that matters for a shipped build, and it is asserted with
      // no arguments deliberately: this call reads the real defines, a test
      // process has none, so this is exactly what a release build without them
      // does. If this ever returns a record, a credential has been compiled in.
      expect(XtreamCredentials.fromEnvironment(), isNull);
    });

    test('builds the record when all three are given', () {
      final XtreamCredentials? credentials = XtreamCredentials.fromEnvironment(
        baseUrl: 'http://panel.example:8080/',
        username: 'bob',
        password: 's3cret',
      );

      expect(credentials, isNotNull);
      // Normalised on the way in, like any other construction: the trailing
      // slash goes, because the endpoints are built by concatenation.
      expect(credentials!.baseUrl, 'http://panel.example:8080');
      expect(credentials.username, 'bob');
      expect(credentials.password, 's3cret');
    });

    test('defaults the user agent, which is not a secret and is always needed', () {
      final XtreamCredentials? credentials = XtreamCredentials.fromEnvironment(
        baseUrl: 'http://h:8080',
        username: 'bob',
        password: 's3cret',
      );

      expect(credentials!.userAgent, 'Watchools/1.0');
    });

    test('refuses a partial set rather than half-honouring it', () {
      // Each of the three missing in turn. A partial set is a mistake at the
      // launch command, and the one thing this must never do is invent a
      // default for a password.
      expect(XtreamCredentials.fromEnvironment(username: 'bob', password: 's3cret'), isNull);
      expect(XtreamCredentials.fromEnvironment(baseUrl: 'http://h:8080', password: 's3cret'), isNull);
      expect(XtreamCredentials.fromEnvironment(baseUrl: 'http://h:8080', username: 'bob'), isNull);
    });

    test('a bad base URL throws rather than addressing the wrong server', () {
      // Not softened to a null. `_normaliseBaseUrl`'s rejection exists because
      // Dio prepends its configured base to any path not matching `https?:`,
      // so a scheme-less panel URL silently addresses the wrong host, and a
      // define is typed by hand at a shell prompt.
      expect(
        () => XtreamCredentials.fromEnvironment(baseUrl: 'panel.example:8080', username: 'bob', password: 's3cret'),
        throwsArgumentError,
      );
    });
  });

  group('toString', () {
    test('names the provider and the user, and redacts the password', () {
      final String text = _record().toString();

      expect(text, contains('http://panel.example:8080'));
      expect(text, contains('bob'));
      expect(text, isNot(contains('s3cret')));
    });
  });

  group('redact', () {
    // What the deleted `describe(Uri)` used to cover, asserted through the one
    // method that has callers. A stringified URL is prose, so the guarantee is
    // the same and there is no second door to keep in step.
    test('covers a whole stream URL, its query and its userInfo', () {
      expect(
        _record().redact('http://h:8080/live/bob/s3cret/1.ts?username=bob&password=s3cret'),
        'http://h:8080/live/***/***/1.ts?username=***&password=***',
      );
      expect(_record().redact('http://bob:s3cret@h:8080/live'), 'http://***:***@h:8080/live');
      expect(_record().redact('http://h/xmltv.php'), 'http://h/xmltv.php');
    });

    test('strips both secrets out of the FFmpeg reconnect warning that is the only lapse signal', () {
      // The verbatim shape watchools_player.dart:42-44 quotes: mpv forwards
      // FFmpeg's warning as prose, and the stream URL carries the credential in
      // its path, so this is the line that leaks a paid subscription.
      final String line = _record().redact(
        'http: Will reconnect to http://h:8080/live/bob/s3cret/1.ts, error=End of file',
      );

      expect(line, isNot(contains('bob')));
      expect(line, isNot(contains('s3cret')));
      expect(line, 'http: Will reconnect to http://h:8080/live/***/***/1.ts, error=End of file');
    });

    test('replaces every occurrence, since a retry line names the same URL twice', () {
      expect(
        _record().redact('reconnect http://h/live/bob/s3cret/1.ts after http://h/live/bob/s3cret/1.ts'),
        'reconnect http://h/live/***/***/1.ts after http://h/live/***/***/1.ts',
      );
    });

    test('leaves a line naming no secret exactly as it arrived', () {
      const String line = 'cplayer: audio/video desynchronisation detected';

      expect(_record().redact(line), line);
    });

    test('redacts the password before the username, so a password containing the username still goes', () {
      final XtreamCredentials record = XtreamCredentials(
        baseUrl: 'http://h:8080',
        username: 'bob',
        password: 'bob-s3cret',
        userAgent: 'Watchools/1.0',
      );

      // Username first would leave `***-s3cret`, which is the whole password
      // minus its first three characters.
      expect(record.redact('/live/bob/bob-s3cret/1.ts'), isNot(contains('s3cret')));
      expect(record.redact('/live/bob/bob-s3cret/1.ts'), '/live/***/***/1.ts');
    });

    test('a provider that issues the password as the username redacts once, not twice over', () {
      final XtreamCredentials record = XtreamCredentials(
        baseUrl: 'http://h:8080',
        username: 'bob',
        password: 'bob',
        userAgent: 'Watchools/1.0',
      );

      expect(record.redact('/live/bob/bob/1.ts'), '/live/***/***/1.ts');
    });

    test('redacts the percent-encoded spelling a URL path carries', () {
      final XtreamCredentials record = _punctuated();

      expect(record.redact('http://h:8080/live/b%40b/p%40ss%20word/1.ts'), 'http://h:8080/live/***/***/1.ts');
      expect(record.redact('open b@b / p@ss word'), 'open *** / ***');
    });

    test('redacts the query spelling too, which writes a space as + rather than %20', () {
      // Uri.encodeQueryComponent is a third distinct form, not a synonym of
      // encodeComponent: space becomes + and !*'() are escaped as well.
      final XtreamCredentials record = _punctuated();

      expect(
        record.redact('GET /player_api.php?username=b%40b&password=p%40ss+word failed'),
        'GET /player_api.php?username=***&password=*** failed',
      );
    });

    test('cleans a URL this app actually built, not only one written by hand', () {
      // The boundary neither half can see on its own: `XtreamStreamUrl` encodes
      // its path segments through `Uri(pathSegments:)` and `redact` has to undo
      // exactly that encoding. A test written against a hand-typed URL agrees
      // with itself rather than with the builder, so this one asks the builder
      // for the string.
      final XtreamCredentials record = _punctuated();
      final Uri? url = XtreamStreamUrl.live(
        credentials: record,
        account: const XtreamAccount(
          auth: true,
          status: 'Active',
          expiresAt: null,
          maxConnections: 1,
          activeConnections: 0,
          allowedOutputFormats: <String>['ts'],
          panelTimestamp: null,
          panelTime: null,
        ),
        channel: const Channel(
          number: 2,
          name: '02 H.264 AAC | RAW TS',
          group: 'RAW TS',
          status: ChannelStatus.live,
          streamId: 10002,
        ),
      );

      final String line = record.redact('http: Will reconnect to $url, error=End of file');

      expect(line, isNot(contains('b@b')));
      expect(line, isNot(contains('p@ss word')));
      expect(line, isNot(contains('b%40b')));
      expect(line, isNot(contains('p%40ss%20word')));
      expect(line, 'http: Will reconnect to http://h:8080/live/***/***/10002.ts, error=End of file');
    });

    test('strips the base64 token a 302 puts in the path, which no literal spelling reaches', () {
      // The token measured against the fixture, verbatim from
      // `evidence/12-token-remint.txt`. It decodes to `demo:demo:1789003017`,
      // so the credential is fully present while none of the four literal
      // spellings appears anywhere in the encoded run. Reachable on the one
      // channel that cannot be switched off: mpv follows the redirect and
      // FFmpeg's reconnect warning names the URL it is retrying.
      final XtreamCredentials record = XtreamCredentials(
        baseUrl: 'http://127.0.0.1:3300',
        username: 'demo',
        password: 'demo',
        userAgent: 'Watchools/1.0',
      );

      const String line =
          'http: Will reconnect to '
          'http://127.0.0.1:3300/live/play/ZGVtbzpkZW1vOjE3ODkwMDMwMTc/10001.ts, error=End of file';

      expect(record.redact(line), isNot(contains('ZGVtbzpkZW1vOjE3ODkwMDMwMTc')));
      expect(record.redact(line), contains('/live/play/***/10001.ts'));
    });

    test('strips a token whose signature is binary and whose base64 is percent-escaped', () {
      // Two gaps in one line, both real and both invisible to the test above,
      // which uses a token that happens to be pure ASCII and pure
      // URL-alphabet.
      //
      // A token is commonly a readable payload plus a signature, and a
      // signature is bytes rather than text: one invalid UTF-8 byte made the
      // strict decode throw and the run was left alone with `demo:demo:` in
      // plain ASCII at its front. And a token in a query parameter is
      // percent-encoded, so a standard-alphabet `/` arrives as `%2F`, which
      // split the run in two at a character the run class did not admit.
      //
      // The payload here is `demo:demo:1789003017` followed by nine random
      // bytes, base64-encoded standard and escaped the way a URL carries it.
      final XtreamCredentials record = XtreamCredentials(
        baseUrl: 'http://127.0.0.1:3300',
        username: 'demo',
        password: 'demo',
        userAgent: 'Watchools/1.0',
      );

      const String line =
          'http: Will reconnect to '
          'http://127.0.0.1:3300/live/play/10001.ts?token=ZGVtbzpkZW1vOjE3ODkwMDMwMTfVD%2F8Hw8IGJCk';

      expect(record.redact(line), isNot(contains('ZGVtbzpkZW1vOjE3ODkw')));
      expect(record.redact(line), 'http: Will reconnect to http://127.0.0.1:3300/live/play/10001.ts?token=***');
    });

    test('leaves an encoded run that names no secret exactly as it arrived', () {
      // The guard that stops this from rewriting innocent text: a run has to
      // decode AND the decoding has to contain a secret. A base64 blob that is
      // somebody else's identifier is not ours to redact.
      const String line = 'cplayer: cache dump aGVsbG8gd29ybGQgdGhpcyBpcyBmaW5l written';

      expect(_record().redact(line), line);
    });

    test('an empty secret is skipped, because replaceAll of it matches between every character', () {
      final XtreamCredentials record = XtreamCredentials(
        baseUrl: 'http://h:8080',
        username: 'bob',
        password: '',
        userAgent: 'Watchools/1.0',
      );

      expect(
        record.redact('http: Will reconnect to http://h:8080/live/bob//1.ts'),
        'http: Will reconnect to http://h:8080/live/***//1.ts',
      );
    });
  });
}
