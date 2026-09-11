import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/protocol/xtream/xtream_account.dart';

/// Seconds since the epoch, right now. Every "future"/"past" fixture below is
/// built relative to this rather than to a fixed constant, the way the mock
/// panel itself computes `exp_date`.
int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A handshake shaped the way `tool/xtream-mock/server.mjs`'s `userInfo()` /
/// `serverInfo()` build one: `user_info` plus `server_info`, with the same
/// type drift (`auth` bare, `max_connections` quoted).
Map<String, dynamic> _handshake({
  required int auth,
  String? status,
  Object? expDate,
  String activeCons = '1',
  String maxConnections = '2',
}) {
  final Map<String, dynamic> userInfo = <String, dynamic>{
    'auth': auth,
    'exp_date': expDate,
    'is_trial': '0',
    'active_cons': activeCons,
    'created_at': '0',
    'max_connections': maxConnections,
    'allowed_output_formats': <String>['m3u8', 'ts'],
  };
  if (status != null) {
    userInfo['status'] = status;
  }

  return <String, dynamic>{
    'user_info': userInfo,
    'server_info': <String, dynamic>{'timestamp_now': _nowSeconds(), 'time_now': '2026-09-09 20:12:00'},
  };
}

void main() {
  group('XtreamAccount.fromHandshake / active', () {
    test('demo: auth 1, status Active, future exp_date is active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Active', expDate: (_nowSeconds() + 365 * 86400).toString()),
      );

      expect(account.active, true);
    });

    test('expired: auth 1, status Expired, future exp_date is not active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Expired', expDate: (_nowSeconds() + 365 * 86400).toString()),
      );

      expect(account.active, false);
    });

    test('lapsed: auth 1, status Active, past exp_date is not active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Active', expDate: (_nowSeconds() - 14 * 86400).toString()),
      );

      expect(account.active, false);
    });

    test('lifetime: auth 1, status Active, exp_date null is active, the trap a naive date '
        'comparison fails', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(account.active, true);
    });

    test('a lowercase "active" status is active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'active'));

      expect(account.active, true);
    });

    test('banned: auth 1, status Banned is not active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Banned', expDate: (_nowSeconds() + 365 * 86400).toString()),
      );

      expect(account.active, false);
    });

    test('disabled: auth 1, status Disabled is not active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Disabled', expDate: (_nowSeconds() + 365 * 86400).toString()),
      );

      expect(account.active, false);
    });

    test('unknown credentials: a single-key {auth: 0} user_info parses without throwing and is '
        'not active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(<String, dynamic>{
        'user_info': const <String, dynamic>{'auth': 0},
        'server_info': <String, dynamic>{'timestamp_now': _nowSeconds(), 'time_now': '2026-09-09 20:12:00'},
      });

      expect(account.active, false);
    });

    test('a missing status with a truthy auth is active', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(_handshake(auth: 1));

      expect(account.active, true);
    });
  });

  group('XtreamAccount.atConnectionLimit', () {
    test('is at the limit when active connections meet the maximum', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active', activeCons: '2'));

      expect(account.atConnectionLimit, true);
    });

    test('is not at the limit while under the maximum', () {
      final XtreamAccount account = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(account.atConnectionLimit, false);
    });

    test('a panel that stated no limit has not reached one', () {
      // `max_connections` drifts or goes missing on real panels. Reading the
      // `0` default as a limit makes `0 >= 0` true and routes a healthy
      // account to `evicted`, which withholds the retry and blames a device
      // that may not exist.
      final Map<String, dynamic> handshake = _handshake(auth: 1, status: 'Active');
      (handshake['user_info'] as Map<String, dynamic>).remove('max_connections');

      final XtreamAccount account = XtreamAccount.fromHandshake(handshake);

      expect(account.maxConnections, 0);
      expect(account.atConnectionLimit, false);
      expect(classifyProviderFault(account: account, statusCode: 200, body: 'blocked'), ProviderFault.throttled);
    });
  });

  group('the parsed account carries no credential', () {
    test('neither toString nor any field echoes the username or the password back', () {
      // The panel echoes both inside `user_info`
      // (`tool/xtream-mock/server.mjs:151-152`), and magic_devtools' telescope
      // interceptor records the first 8 KiB of every response body, which is
      // far more than a handshake. So a model that kept either field would be
      // one `Log` line or one inspector away from a provider password. Nothing
      // asserted the stripping until this test.
      final Map<String, dynamic> handshake = _handshake(auth: 1, status: 'Active');
      (handshake['user_info'] as Map<String, dynamic>)
        ..['username'] = 'Vipall39933'
        ..['password'] = 'rjJB1jq';

      final XtreamAccount account = XtreamAccount.fromHandshake(handshake);

      expect(account.toString(), isNot(contains('rjJB1jq')));
      expect(account.toString(), isNot(contains('Vipall39933')));
    });
  });

  group('value equality', () {
    test('two accounts parsed from the same handshake are equal and hash alike', () {
      final Map<String, dynamic> handshake = _handshake(auth: 1, status: 'Active');

      final XtreamAccount first = XtreamAccount.fromHandshake(handshake);
      final XtreamAccount second = XtreamAccount.fromHandshake(handshake);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('a difference in any single field breaks equality', () {
      final XtreamAccount base = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(base, isNot(XtreamAccount.fromHandshake(_handshake(auth: 0, status: 'Active'))));
      expect(base, isNot(XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Expired'))));
      expect(base, isNot(XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active', activeCons: '2'))));
      expect(base, isNot(XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active', maxConnections: '9'))));
    });

    test('the output formats participate by value, not by identity', () {
      // `allowedOutputFormats` is a list, so `==` on it would compare
      // references and two accounts parsed from two identical payloads would
      // read as different. `listEquals` is what makes the field carry.
      final XtreamAccount first = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));
      final XtreamAccount second = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(first.allowedOutputFormats, <String>['m3u8', 'ts']);
      expect(identical(first.allowedOutputFormats, second.allowedOutputFormats), isFalse);
      expect(first, second);
    });
  });

  group('classifyProviderFault', () {
    test('statusCode 0 is unreachable, regardless of account or body', () {
      expect(classifyProviderFault(account: null, statusCode: 0, body: null), ProviderFault.unreachable);
    });

    test('no account at all is expired', () {
      expect(classifyProviderFault(account: null, statusCode: 200, body: '{"auth":0}'), ProviderFault.expired);
    });

    test('an account that failed the disjunction is expired', () {
      final XtreamAccount lapsed = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Active', expDate: (_nowSeconds() - 14 * 86400).toString()),
      );

      expect(classifyProviderFault(account: lapsed, statusCode: 200, body: '{"user_info":{}}'), ProviderFault.expired);
    });

    test('a 404 with no parsable body is wrongAddress, not throttled', () {
      // The case a user typing their own address makes ordinary, and what it
      // used to report: `throttled`, whose copy states a rate limit and asks
      // them to wait a few seconds, forever, for a port that will never
      // answer. Before onboarding the base URL came from a define a developer
      // had already verified, so this arm had no way to fire.
      expect(
        classifyProviderFault(account: null, statusCode: 404, body: '<html>Not Found</html>'),
        ProviderFault.wrongAddress,
      );
    });

    test('a 301 is wrongAddress, since the driver refuses to follow it', () {
      // `AppServiceProvider` sets `followRedirects = false`, because a panel
      // URL carries the credential in its path and the target host is the
      // panel's choice. That decision only means something if the redirect
      // then becomes a fault the user can act on.
      expect(classifyProviderFault(account: null, statusCode: 301, body: ''), ProviderFault.wrongAddress);
    });

    test('a live account does not rescue a 404: the address is wrong whatever the subscription says', () {
      // Deliberately ahead of every account-based arm. A redirect or a missing
      // path is a statement about the ADDRESS, and it arrives the same way
      // whether the credential is a day old or three years old.
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 404, body: 'nope'), ProviderFault.wrongAddress);
    });

    test('403 and 500 stay on the arms that offer a retry', () {
      // The narrowness is the point. A 403 is what a reseller answers to a
      // blocked address or a blocked user agent, and a 5xx is the panel's own
      // bad day; both clear on their own or with a different `User-Agent`, so
      // sending the user back to a field they typed correctly would be wrong.
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 403, body: 'blocked'), ProviderFault.throttled);
      expect(classifyProviderFault(account: healthy, statusCode: 502, body: 'bad gateway'), ProviderFault.throttled);
    });

    test('a 404 that still answers with a healthy handshake is not a fault at all', () {
      // The body wins over the status when the body is Xtream JSON, which is
      // the order that was already there: a body that decoded is a body that
      // spoke. A panel behind an odd proxy that mislabels its status is still
      // a panel.
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 404, body: '{"user_info":{}}'), isNull);
    });

    test('a healthy account behind the generic non-JSON denial, under its connection limit, is '
        'throttled', () {
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 200, body: 'blocked'), ProviderFault.throttled);
    });

    test('a healthy account behind the generic non-JSON denial, at its connection limit, is '
        'evicted rather than throttled', () {
      final XtreamAccount atLimit = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active', activeCons: '2'));

      expect(classifyProviderFault(account: atLimit, statusCode: 200, body: 'blocked'), ProviderFault.evicted);
    });

    test('a dead account behind the same generic denial stays expired, never throttled', () {
      final XtreamAccount lapsed = XtreamAccount.fromHandshake(
        _handshake(auth: 1, status: 'Active', expDate: (_nowSeconds() - 14 * 86400).toString()),
      );

      expect(classifyProviderFault(account: lapsed, statusCode: 200, body: 'blocked'), ProviderFault.expired);
    });

    test('a healthy account with a well-formed JSON object body has no fault', () {
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 200, body: '{"user_info":{}}'), null);
    });

    test('a healthy account with a JSON array body (a catalogue call) has no fault, never '
        'inferred as a denial', () {
      final XtreamAccount healthy = XtreamAccount.fromHandshake(_handshake(auth: 1, status: 'Active'));

      expect(classifyProviderFault(account: healthy, statusCode: 200, body: '[{"stream_id":1}]'), null);
    });
  });
}
