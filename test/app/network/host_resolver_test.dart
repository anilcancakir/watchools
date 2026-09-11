import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/network/host_resolver.dart';
import 'package:watchools/app/network/resolver_setting.dart';

/// A rung a test drives: it answers, it fails, or it never answers at all.
///
/// The hang is a [Completer] nobody completes rather than a `Future.delayed`,
/// because a lookup that eventually returns proves nothing about a timeout. The
/// timeout has to be the thing that ends the wait, and only a future that never
/// settles can demonstrate that.
class _ScriptedLookup implements HostLookup {
  /// What [lookup] hands back, or null to fail the way a real rung fails.
  final HostAnswer? answer;

  /// Whether [lookup] returns a future that never settles.
  final bool hangs;

  /// Every host this rung was asked about, in order. The ladder assertions are
  /// all about which rungs were consulted and which were not.
  final List<String> calls = <String>[];

  final Completer<HostAnswer> _never = Completer<HostAnswer>();

  _ScriptedLookup({this.answer, this.hangs = false});

  @override
  Future<HostAnswer> lookup(String host) {
    calls.add(host);

    if (hangs) return _never.future;

    final HostAnswer? scripted = answer;

    if (scripted == null) {
      return Future<HostAnswer>.error(const HostLookupException('scripted rung failure'));
    }

    return Future<HostAnswer>.value(scripted);
  }
}

void main() {
  // Short enough that the hanging-rung tests cost milliseconds rather than the
  // production default's two seconds, and long enough that a scripted rung
  // which answers immediately is never cut by it.
  const Duration rungTimeout = Duration(milliseconds: 30);

  const HostAnswer systemAnswer = HostAnswer(<String>['185.15.58.224']);
  const HostAnswer dohAnswer = HostAnswer(<String>['104.20.23.154']);

  group('the ladder', () {
    test('stops at the system rung when its answer is good, never consulting DoH', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: systemAnswer);
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');
      expect(system.calls, <String>['panel.example.com']);
      expect(doh.calls, isEmpty);
    });

    test('abandons a system lookup that never answers and takes the DoH rung instead', () async {
      final _ScriptedLookup system = _ScriptedLookup(hangs: true);
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
      expect(system.calls, <String>['panel.example.com']);
      expect(doh.calls, <String>['panel.example.com']);
    });

    test('escalates a system rung that throws', () async {
      final _ScriptedLookup system = _ScriptedLookup();
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.google,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
    });

    test('returns null when both rungs fail, leaving the classification to the caller', () async {
      final _ScriptedLookup system = _ScriptedLookup();
      final _ScriptedLookup doh = _ScriptedLookup();
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), isNull);
      expect(system.calls, hasLength(1));
      expect(doh.calls, hasLength(1));
    });

    test('has no second rung at all when the setting names no endpoint', () async {
      final _ScriptedLookup system = _ScriptedLookup();
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.system,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), isNull);
      expect(doh.calls, isEmpty);
    });

    test('treats an empty answer as a rung that did not resolve the host', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>[]));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
    });
  });

  group('the tamper check', () {
    test('escalates a loopback answer for a real host, the documented Turkish shape', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['127.0.0.1']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
      expect(doh.calls, <String>['panel.example.com']);
    });

    test('keeps a loopback answer for localhost, where it is the truth', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['127.0.0.1']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('localhost'), '127.0.0.1');
      expect(doh.calls, isEmpty);
    });

    test('keeps a loopback answer when the host was already an IP literal', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['127.0.0.1']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('127.0.0.1'), '127.0.0.1');
      expect(doh.calls, isEmpty);
    });

    test('escalates an unspecified and a link-local answer the same way', () async {
      for (final String blackhole in <String>['0.0.0.0', '169.254.7.7', '::1', 'fe80::1']) {
        final _ScriptedLookup system = _ScriptedLookup(answer: HostAnswer(<String>[blackhole]));
        final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
        final HostResolver resolver = HostResolver(
          setting: ResolverSetting.cloudflare,
          system: system,
          doh: doh,
          timeout: rungTimeout,
        );

        expect(await resolver.resolve('panel.example.com'), '104.20.23.154', reason: '$blackhole should escalate');
      }
    });

    test('does not refuse a private-range answer, which a LAN or WireGuard panel needs', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['192.168.1.40']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.local'), '192.168.1.40');
      expect(doh.calls, isEmpty);
    });

    test('skips a blackhole address to take a real one from the same answer', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['127.0.0.1', '185.15.58.224']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');
      expect(doh.calls, isEmpty);
    });

    test('refuses an answer that is not an address at all, such as a leaked CNAME target', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: const HostAnswer(<String>['dyna.wikimedia.org.']));
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
    });
  });

  group('the TTL cache', () {
    test('a second resolve inside the TTL consults no rung at all', () async {
      DateTime now = DateTime(2026, 9, 11, 20, 12);
      final _ScriptedLookup system = _ScriptedLookup(answer: systemAnswer);
      final _ScriptedLookup doh = _ScriptedLookup(answer: dohAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
        clock: () => now,
      );

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');

      now = now.add(const Duration(minutes: 4));

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');
      expect(system.calls, hasLength(1));
      expect(doh.calls, isEmpty);
    });

    test('a resolve after the ceiling consults the rungs again', () async {
      DateTime now = DateTime(2026, 9, 11, 20, 12);
      final _ScriptedLookup system = _ScriptedLookup(answer: systemAnswer);
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.system,
        system: system,
        timeout: rungTimeout,
        clock: () => now,
      );

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');

      now = now.add(HostResolver.ttlCeiling + const Duration(seconds: 1));

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');
      expect(system.calls, hasLength(2));
    });

    test("caches a DoH answer for the record's own TTL rather than the ceiling", () async {
      DateTime now = DateTime(2026, 9, 11, 20, 12);
      final _ScriptedLookup system = _ScriptedLookup();
      final _ScriptedLookup doh = _ScriptedLookup(
        answer: const HostAnswer(<String>['104.20.23.154'], ttl: Duration(seconds: 159)),
      );
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.cloudflare,
        system: system,
        doh: doh,
        timeout: rungTimeout,
        clock: () => now,
      );

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');

      // Past the record's 159 s TTL but well inside the five minute ceiling, so
      // an implementation that ignored the answer's TTL would still be serving
      // this from cache here.
      now = now.add(const Duration(seconds: 200));

      expect(await resolver.resolve('panel.example.com'), '104.20.23.154');
      expect(doh.calls, hasLength(2));
    });

    test('clamps a TTL longer than the ceiling, so a resolver cannot pin us to an address', () async {
      DateTime now = DateTime(2026, 9, 11, 20, 12);
      final _ScriptedLookup system = _ScriptedLookup(
        answer: const HostAnswer(<String>['185.15.58.224'], ttl: Duration(days: 1)),
      );
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.system,
        system: system,
        timeout: rungTimeout,
        clock: () => now,
      );

      await resolver.resolve('panel.example.com');

      now = now.add(HostResolver.ttlCeiling + const Duration(seconds: 1));

      expect(resolver.cached('panel.example.com'), isNull);
    });

    test('honours a TTL of zero by not caching at all', () async {
      final _ScriptedLookup system = _ScriptedLookup(
        answer: const HostAnswer(<String>['185.15.58.224'], ttl: Duration.zero),
      );
      final HostResolver resolver = HostResolver(setting: ResolverSetting.system, system: system, timeout: rungTimeout);

      expect(await resolver.resolve('panel.example.com'), '185.15.58.224');
      expect(resolver.cached('panel.example.com'), isNull);
    });

    test('caches nothing when every rung failed', () async {
      final _ScriptedLookup system = _ScriptedLookup();
      final HostResolver resolver = HostResolver(setting: ResolverSetting.system, system: system, timeout: rungTimeout);

      expect(await resolver.resolve('panel.example.com'), isNull);
      expect(resolver.cached('panel.example.com'), isNull);
    });
  });

  group('cached', () {
    test('reads nothing before the first resolve and the answer afterwards', () async {
      final _ScriptedLookup system = _ScriptedLookup(answer: systemAnswer);
      final HostResolver resolver = HostResolver(setting: ResolverSetting.system, system: system, timeout: rungTimeout);

      expect(resolver.cached('panel.example.com'), isNull);

      await resolver.resolve('panel.example.com');

      expect(resolver.cached('panel.example.com'), '185.15.58.224');
      expect(system.calls, hasLength(1));
    });

    test('keeps the setting the user picked, for the screen that shows both', () {
      final HostResolver resolver = HostResolver(
        setting: ResolverSetting.google,
        system: _ScriptedLookup(answer: systemAnswer),
      );

      expect(resolver.setting, ResolverSetting.google);
    });
  });
}
