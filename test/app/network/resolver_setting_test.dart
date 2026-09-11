import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/network/resolver_setting.dart';

void main() {
  group('parse', () {
    test('a null stored value is the system resolver', () {
      expect(ResolverSetting.parse(null), ResolverSetting.system);
    });

    test('the literal "system" is the system resolver', () {
      expect(ResolverSetting.parse('system'), ResolverSetting.system);
    });

    test('"cloudflare" resolves to the Cloudflare DoH endpoint measured 2026-09-11', () {
      final ResolverSetting setting = ResolverSetting.parse('cloudflare');

      expect(setting, ResolverSetting.cloudflare);
      expect(setting.storedValue, 'cloudflare');
      expect(setting.dohEndpoint, Uri.parse('https://cloudflare-dns.com/dns-query'));
    });

    test('"google" resolves to the Google DoH endpoint measured 2026-09-11', () {
      final ResolverSetting setting = ResolverSetting.parse('google');

      expect(setting, ResolverSetting.google);
      expect(setting.storedValue, 'google');
      expect(setting.dohEndpoint, Uri.parse('https://dns.google/resolve'));
    });

    test('an unknown named choice falls back to the system resolver, which is where Quad9 lands', () {
      // Quad9 is deliberately not a named choice: its JSON endpoint answers
      // "400 DoH unable to decode BASE64-URL" on 443, and port 5053 timed out
      // entirely from a Turkish connection on 2026-09-11. A stored "quad9" is
      // neither a known name nor a valid IP literal or https URL, so it falls
      // through to the system resolver exactly like any other unknown token.
      final ResolverSetting setting = ResolverSetting.parse('quad9');

      expect(setting, ResolverSetting.system);
    });

    test('rejects a bare hostname, which would have to be resolved by the resolver it replaces', () {
      final ResolverSetting setting = ResolverSetting.parse('dns.example.com');

      expect(setting, ResolverSetting.system);
    });

    test('accepts a bare IPv4 literal as a custom resolver', () {
      final ResolverSetting setting = ResolverSetting.parse('1.1.1.1');

      expect(setting.storedValue, '1.1.1.1');
      expect(setting.dohEndpoint, Uri.parse('https://1.1.1.1/dns-query'));
    });

    test('accepts an IPv4 literal carrying a port', () {
      final ResolverSetting setting = ResolverSetting.parse('9.9.9.9:5053');

      expect(setting.storedValue, '9.9.9.9:5053');
      expect(setting.dohEndpoint, Uri.parse('https://9.9.9.9:5053/dns-query'));
    });

    test('accepts a bare IPv6 literal, bracketing it only for the endpoint URL', () {
      final ResolverSetting setting = ResolverSetting.parse('2606:4700:4700::1111');

      expect(setting.storedValue, '2606:4700:4700::1111');
      expect(setting.dohEndpoint, Uri.parse('https://[2606:4700:4700::1111]/dns-query'));
    });

    test('accepts a bracketed IPv6 literal carrying a port', () {
      final ResolverSetting setting = ResolverSetting.parse('[2606:4700:4700::1111]:443');

      expect(setting.storedValue, '[2606:4700:4700::1111]:443');
      expect(setting.dohEndpoint, Uri.parse('https://[2606:4700:4700::1111]:443/dns-query'));
    });

    test('accepts an https URL as the literal endpoint', () {
      final ResolverSetting setting = ResolverSetting.parse('https://my-resolver.example/dns-query');

      expect(setting.storedValue, 'https://my-resolver.example/dns-query');
      expect(setting.dohEndpoint, Uri.parse('https://my-resolver.example/dns-query'));
    });

    test('rejects a plain http URL, since DoH is https only', () {
      expect(ResolverSetting.parse('http://1.1.1.1/dns-query'), ResolverSetting.system);
    });

    test('rejects an out-of-range IPv4 octet', () {
      expect(ResolverSetting.parse('999.1.1.1'), ResolverSetting.system);
    });

    test('rejects a port outside 1-65535', () {
      expect(ResolverSetting.parse('1.1.1.1:70000'), ResolverSetting.system);
    });

    test('rejects an empty string', () {
      expect(ResolverSetting.parse(''), ResolverSetting.system);
    });
  });

  group('storedValue and dohEndpoint on the named constants', () {
    test('the system resolver has no stored value and no override endpoint', () {
      expect(ResolverSetting.system.storedValue, isNull);
      expect(ResolverSetting.system.dohEndpoint, isNull);
    });
  });
}
