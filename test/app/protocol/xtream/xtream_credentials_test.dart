import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';

XtreamCredentials _record({String baseUrl = 'http://panel.example:8080'}) =>
    XtreamCredentials(baseUrl: baseUrl, username: 'bob', password: 's3cret', userAgent: 'Watchools/1.0');

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

  group('toString', () {
    test('names the provider and the user, and redacts the password', () {
      final String text = _record().toString();

      expect(text, contains('http://panel.example:8080'));
      expect(text, contains('bob'));
      expect(text, isNot(contains('s3cret')));
    });
  });

  group('describe', () {
    test('drops the query and the credential path segments of a stream URL', () {
      final String described = _record().describe(
        Uri.parse('http://h:8080/live/bob/s3cret/1.ts?username=bob&password=s3cret'),
      );

      expect(described, isNot(contains('s3cret')));
      expect(described, isNot(contains('bob')));
      expect(described, isNot(contains('?')));
      expect(described, 'http://h:8080/live/***/***/1.ts');
    });

    test('keeps scheme, host, port and the segments that are not a credential', () {
      expect(
        _record().describe(Uri.parse('https://h.example:2095/player_api.php?username=bob&password=s3cret')),
        'https://h.example:2095/player_api.php',
      );
      expect(_record().describe(Uri.parse('http://h/xmltv.php')), 'http://h/xmltv.php');
    });

    test('drops userInfo, the other place a URL carries a credential', () {
      expect(_record().describe(Uri.parse('http://bob:s3cret@h:8080/live')), 'http://h:8080/live');
    });
  });
}
