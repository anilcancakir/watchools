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
