import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/app/network/host_resolver.dart';
import 'package:watchools/app/network/resolver_setting.dart';
import 'package:watchools/app/protocol/xtream/xtream_client.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/catalogue_store.dart';
import 'package:watchools/app/provider/provider_session.dart';

import '../../support/throwing_vault.dart';

/// A scriptable double for the Xtream panel.
///
/// One mutable field per action, read fresh on every call, so a test can
/// change what the "next" handshake answers with mid-session (the shape
/// [ProviderSession] needs to tell a fresh `expired` from a `throttled` or
/// `evicted` denial on an account it already knows). [handshakeCalls] and
/// [requestedShortEpgStreamIds] are what the connection-gate and the
/// EPG-bound tests read back.
class _MockPanel {
  Object? handshakeBody = const <String, dynamic>{'auth': 0};
  int handshakeStatusCode = 200;
  List<Map<String, dynamic>> liveCategories = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> liveStreams = const <Map<String, dynamic>>[];
  Map<int, List<Map<String, dynamic>>> shortEpgByStreamId = <int, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> vodCategories = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> vodStreams = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> seriesCategories = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> series = const <Map<String, dynamic>>[];

  int handshakeCalls = 0;
  final List<int> requestedShortEpgStreamIds = <int>[];

  /// Whether the VOD half of a refresh ever ran.
  ///
  /// The larger half by request count (four calls against the channel half's
  /// two plus the EPG loop), so a test that asserts a refresh was abandoned
  /// reads this rather than only counting EPG calls.
  bool requestedVodStreams = false;

  /// Called as each `get_short_epg` request arrives, before it is answered.
  ///
  /// The seam a test uses to stand in for "the user tapped a channel while the
  /// refresh was in flight": the EPG loop is the longest stretch of sequential
  /// requests in the app, so it is where a mid-refresh event is both most
  /// likely and cheapest to script.
  void Function(int streamId)? onShortEpg;

  /// Called as the `get_live_streams` request arrives, before it is answered.
  ///
  /// The other window a mid-refresh event can land in, and the wider one:
  /// this is the single longest response in a refresh, 2,976 rows on a real
  /// subscription, and everything the channel half reads off the session's
  /// nullable fields used to be read after it. [onShortEpg] could not reach
  /// that window, which is why moving the reads out of the EPG loop looked
  /// like a fix and left the widest case open.
  void Function()? onLiveStreams;

  MagicResponse handle(MagicRequest request) {
    final String action = request.queryParameters?['action'] as String? ?? '';

    if (action.isEmpty) {
      handshakeCalls++;
      return MagicResponse(data: handshakeBody, statusCode: handshakeStatusCode);
    }

    switch (action) {
      case 'get_live_categories':
        return MagicResponse(data: liveCategories, statusCode: 200);
      case 'get_live_streams':
        onLiveStreams?.call();
        return MagicResponse(data: liveStreams, statusCode: 200);
      case 'get_short_epg':
        final int streamId = int.parse('${request.queryParameters?['stream_id']}');
        requestedShortEpgStreamIds.add(streamId);
        onShortEpg?.call(streamId);
        return MagicResponse(
          data: <String, dynamic>{'epg_listings': shortEpgByStreamId[streamId] ?? const <Map<String, dynamic>>[]},
          statusCode: 200,
        );
      case 'get_vod_categories':
        return MagicResponse(data: vodCategories, statusCode: 200);
      case 'get_vod_streams':
        requestedVodStreams = true;
        return MagicResponse(data: vodStreams, statusCode: 200);
      case 'get_series_categories':
        return MagicResponse(data: seriesCategories, statusCode: 200);
      case 'get_series':
        return MagicResponse(data: series, statusCode: 200);
      default:
        return MagicResponse(data: const <dynamic>[], statusCode: 200);
    }
  }
}

/// A rung that answers with [address], or fails the way a real rung fails when
/// it is null.
///
/// [calls] is what turns "the session pushed the new choice in" into something
/// observable: a DoH rung that was never authorised is never consulted at all.
class _ScriptedLookup implements HostLookup {
  /// The single address this rung answers with, or null to throw.
  final String? address;

  /// Every host this rung was asked about, in order.
  final List<String> calls = <String>[];

  _ScriptedLookup([this.address]);

  @override
  Future<HostAnswer> lookup(String host) async {
    calls.add(host);

    final String? answer = address;

    if (answer == null) throw const HostLookupException('scripted rung failure');

    return HostAnswer(<String>[answer]);
  }
}

/// A handshake `user_info` + `server_info` body, in the wire's own drifted
/// shape: `auth` bare, everything else quoted, per
/// `explore-mock-surface.md`.
Map<String, dynamic> _handshake({
  required int auth,
  String? status,
  String? expDate,
  int maxConnections = 1,
  int activeConnections = 0,
}) => <String, dynamic>{
  'user_info': <String, dynamic>{
    'auth': auth,
    'status': status,
    'exp_date': expDate,
    'max_connections': '$maxConnections',
    'active_cons': '$activeConnections',
    'allowed_output_formats': <String>['m3u8', 'ts'],
  },
  'server_info': <String, dynamic>{'timestamp_now': 1700000000, 'time_now': '2023-11-14 00:00:00'},
};

Map<String, dynamic> _liveCategory(String id, String name) => <String, dynamic>{
  'category_id': id,
  'category_name': name,
};

Map<String, dynamic> _liveEntry({
  required int streamId,
  required int number,
  required String name,
  required String categoryId,
  String? epgChannelId,
}) => <String, dynamic>{
  'num': number,
  'name': name,
  'stream_id': streamId,
  'category_id': categoryId,
  'epg_channel_id': epgChannelId,
  'tv_archive': 0,
};

Map<String, dynamic> _shortEpgListing({required String start, required String end, required String title}) =>
    <String, dynamic>{'start': start, 'end': end, 'title': base64.encode(utf8.encode(title))};

Map<String, dynamic> _vodCategory(String id, String name) => <String, dynamic>{
  'category_id': id,
  'category_name': name,
};

Map<String, dynamic> _vodEntry({required int streamId, required String name, required String categoryId}) =>
    <String, dynamic>{'num': 1, 'name': name, 'stream_id': streamId, 'category_id': categoryId};

void main() {
  MagicTest.init();

  final XtreamCredentials credentials = XtreamCredentials(
    baseUrl: 'http://panel.example:8080',
    username: 'demo',
    password: 'demo',
    userAgent: 'watchools/test',
  );

  late _MockPanel panel;
  late FakeNetworkDriver driver;

  setUp(() {
    DatabaseManager().setConnection(sqlite3.openInMemory());

    panel = _MockPanel();
    driver = FakeNetworkDriver(stubs: panel.handle);
    Magic.singleton(XtreamClient.driverKey, () => driver);
  });

  tearDown(() {
    DatabaseManager().dispose();
    Vault.unfake();
  });

  /// Seeds the fake vault with [credentials], the way step 1's own tests do.
  Future<void> seedCredentials() async {
    Vault.fake();
    await credentials.save();
  }

  group('start(), with no stored credentials', () {
    test('reports none rather than throwing', () async {
      Vault.fake();
      final ProviderSession session = ProviderSession();

      await session.start();
      await session.refresh();

      expect(session.hasCredentials, isFalse);
      expect(session.fault, isNull);
      expect(session.channels, isEmpty);
      expect(session.titles, isEmpty);
      driver.assertNothingSent();
    });
  });

  group('classification, from the handshake alone', () {
    test('statusCode 0 reports unreachable', () async {
      await seedCredentials();
      panel.handshakeStatusCode = 0;
      panel.handshakeBody = null;

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      expect(session.fault, ProviderFault.unreachable);
    });

    test('rejected credentials report expired', () async {
      await seedCredentials();
      panel.handshakeBody = const <String, dynamic>{'auth': 0};

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      expect(session.fault, ProviderFault.expired);
    });

    test('a lapsed account reports expired even though the catalogue lists parse fine', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(
        auth: 1,
        status: 'Active',
        expDate: '${DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000}',
      );
      // Stubbed to parse successfully, proving the session does not read
      // catalogue-parse success as evidence of health.
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[_liveEntry(streamId: 1, number: 1, name: 'Kanal 1', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      expect(session.fault, ProviderFault.expired);
      // The dead subscription is never used to fetch a line-up.
      expect(session.channels, isEmpty);
    });

    test('a healthy handshake clears a previously reported fault', () async {
      await seedCredentials();
      panel.handshakeBody = const <String, dynamic>{'auth': 0};

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();
      expect(session.fault, ProviderFault.expired);

      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      await session.refresh();

      expect(session.fault, isNull);
    });

    test('a denial on an account already known active and at its connection limit reports evicted', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, activeConnections: 1);

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();
      expect(session.fault, isNull);

      panel.handshakeBody = 'blocked';
      await session.refresh();

      expect(session.fault, ProviderFault.evicted);
    });

    test('a denial on an account already known active and below its connection limit reports throttled', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();
      expect(session.fault, isNull);

      panel.handshakeBody = 'blocked';
      await session.refresh();

      expect(session.fault, ProviderFault.throttled);
    });
  });

  group('streamUrlFor, which is how a URL leaves without the credential doing so', () {
    test('derives the live URL from the credential and the account it already holds', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Ulusal')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 10002, number: 2, name: '02 H.264 AAC | RAW TS', categoryId: '1'),
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      final Channel channel = session.channels.firstWhere((Channel each) => each.streamId != null);

      // Asked of the builder rather than typed out, because a hand-written
      // expectation agrees with itself instead of with the thing under test.
      // Wave 1 leaked a password through exactly that gap.
      expect(session.streamUrlFor(channel), isNotNull);
      expect(session.streamUrlFor(channel)?.pathSegments.first, 'live');
      expect(session.streamUrlFor(channel)?.pathSegments, contains('demo'));
    });

    test('is null before a handshake, because no account has said what it permits', () async {
      await seedCredentials();

      final ProviderSession session = ProviderSession();
      await session.start();

      const Channel channel = Channel(
        number: 2,
        name: '02 H.264 AAC | RAW TS',
        group: 'RAW TS',
        status: ChannelStatus.live,
        streamId: 10002,
      );

      expect(session.hasCredentials, isTrue);
      expect(session.streamUrlFor(channel), isNull);
    });

    test('is null for a channel with no provider identity, rather than throwing', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      const Channel fixtureBuilt = Channel(number: 2, name: 'TRT 1', group: 'Ulusal', status: ChannelStatus.live);

      expect(session.streamUrlFor(fixtureBuilt), isNull);
    });

    test('is null with no credential at all, which is the fixture path', () {
      Vault.fake();

      expect(
        ProviderSession().streamUrlFor(
          const Channel(number: 1, name: 'x', group: 'y', status: ChannelStatus.live, streamId: 1),
        ),
        isNull,
      );
    });
  });

  group('the development credential', () {
    // The way in on macOS, where `Vault` is the Keychain and a sandboxed build
    // cannot write to it at all: every `Vault.put` fails with OSStatus -34018
    // ("A required entitlement isn't present"), measured through the running
    // app with and without the sandbox. Without a fallback there is no
    // credential, so `hasCredentials` is false forever, all four screens show
    // the fixture, and nothing is playable because a fixture channel carries
    // no `streamId`.
    final XtreamCredentials development = XtreamCredentials(
      baseUrl: 'http://127.0.0.1:3300',
      username: 'demo',
      password: 'demo',
      userAgent: 'Watchools/1.0',
    );

    test('is used when the vault is empty', () async {
      Vault.fake();

      final ProviderSession session = ProviderSession(developmentCredential: () => development);
      await session.start();

      expect(session.hasCredentials, isTrue);
      expect(session.playbackUserAgent, 'Watchools/1.0');
    });

    test('loses to a stored credential, so it can never replace a real one', () async {
      // The ordering is the security half. A define left in a shell profile
      // must not silently take over from the credential a user configured, so
      // the vault is read first and the fallback only fires on a null.
      await seedCredentials();

      final ProviderSession session = ProviderSession(developmentCredential: () => development);
      await session.start();

      expect(session.hasCredentials, isTrue);
      // `seedCredentials` writes the suite's own record, whose user agent
      // differs from the development one. Asserting the agent rather than the
      // password, because nothing here may read a password back.
      expect(session.playbackUserAgent, isNot('Watchools/1.0'));
    });

    test('an unreadable stored payload is still a fault, not a fallback', () async {
      // `expired` is the honest reading of a payload this build cannot parse,
      // and it must stay that way: falling back to a development credential
      // here would hide a real user's broken vault entry behind a working
      // local panel, on the one path whose button goes to provider settings.
      Vault.fake();
      await Vault.put(XtreamCredentials.vaultKey, '{"base_url": 42}');

      final ProviderSession session = ProviderSession(developmentCredential: () => development);
      await session.start();

      expect(session.fault, ProviderFault.expired);
      expect(session.hasCredentials, isFalse);
    });

    test('defaults to the compile-time defines, which a test process does not have', () async {
      // The app's own wiring, with no seam passed. A `flutter test` run carries
      // no `--dart-define`, so this is also the assertion that a build given
      // none has no credential.
      Vault.fake();

      final ProviderSession session = ProviderSession();
      await session.start();

      expect(session.hasCredentials, isFalse);
    });
  });

  group('refresh(), gated on playback', () {
    // `start()` is local only, so `refresh()` has to be invoked explicitly
    // here or the assertion below could not fail: nothing would have tried
    // to send a request in the first place.
    test('is a no-op while playing, sending no request at all', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      final ProviderSession session = ProviderSession(isPlaying: () => true);
      await session.start();
      await session.refresh();

      expect(session.hasCredentials, isTrue);
      expect(session.fault, isNull);
      driver.assertSentCount(0);
    });

    test('stops mid-refresh when playback starts, rather than only refusing to start', () async {
      // The case the door alone does not cover, and the one that happens on
      // every launch: `AppServiceProvider.boot()` fires an unawaited
      // `refresh()` at cold start, so a user who taps a channel a few seconds
      // in is playing while a batch of a handshake, four list fetches and up
      // to `epgFetchLimit` sequential EPG calls is still in flight, against an
      // account whose measured `max_connections` is 1.
      //
      // The predicate flips the moment the first EPG request is made, which is
      // the earliest point a test can stand in for "the user tapped a channel".
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 301, number: 1, name: 'Kanal 1', categoryId: '1', epgChannelId: 'ch1'),
        _liveEntry(streamId: 302, number: 2, name: 'Kanal 2', categoryId: '1', epgChannelId: 'ch2'),
        _liveEntry(streamId: 303, number: 3, name: 'Kanal 3', categoryId: '1', epgChannelId: 'ch3'),
      ];
      for (final int streamId in <int>[301, 302, 303]) {
        panel.shortEpgByStreamId[streamId] = <Map<String, dynamic>>[
          _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme'),
        ];
      }

      bool playing = false;
      final ProviderSession session = ProviderSession(isPlaying: () => playing);
      await session.start();

      // Flip on the first EPG request. `requestedShortEpgStreamIds` is what
      // the fake panel records, so reading it is how the test observes where
      // the loop got to.
      panel.onShortEpg = (int _) => playing = true;

      await session.refresh();

      // One EPG request went out before the flip and the loop then broke, so
      // the other two never left. Asserted as a length rather than as a set,
      // because the point is that it stopped, not which channel it stopped on.
      expect(panel.requestedShortEpgStreamIds, hasLength(1));

      // And the VOD half never ran at all. That is four more requests, which
      // is the larger half of what a refresh costs.
      expect(panel.requestedVodStreams, isFalse);
    });
  });

  group('the short-EPG merge', () {
    test('a channel with an epg_channel_id gains a schedule; one with none is never requested', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 101, number: 1, name: 'Kanal 1', categoryId: '1', epgChannelId: 'ch1'),
        _liveEntry(streamId: 102, number: 2, name: 'Kanal 2', categoryId: '1'),
      ];
      panel.shortEpgByStreamId[101] = <Map<String, dynamic>>[
        _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme A'),
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      final Channel withEpg = session.channels.firstWhere((Channel c) => c.streamId == 101);
      final Channel withoutEpg = session.channels.firstWhere((Channel c) => c.streamId == 102);

      expect(withEpg.schedule, isNotEmpty);
      expect(withoutEpg.schedule, isEmpty);
      expect(panel.requestedShortEpgStreamIds, contains(101));
      expect(panel.requestedShortEpgStreamIds, isNot(contains(102)));
      // The anchored clock a healthy refresh built, exposed for step 10 to
      // hand the guide screens on the provider path.
      expect(session.clock, isNotNull);
    });

    test('the bound is respected: only the first epgFetchLimit channels are ever considered', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 201, number: 1, name: 'Kanal 1', categoryId: '1', epgChannelId: 'ch1'),
        _liveEntry(streamId: 202, number: 2, name: 'Kanal 2', categoryId: '1', epgChannelId: 'ch2'),
      ];
      panel.shortEpgByStreamId[201] = <Map<String, dynamic>>[
        _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme A'),
      ];
      panel.shortEpgByStreamId[202] = <Map<String, dynamic>>[
        _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme B'),
      ];

      final ProviderSession session = ProviderSession(epgFetchLimit: 1);
      await session.start();
      await session.refresh();

      expect(panel.requestedShortEpgStreamIds, <int>[201]);
    });

    test('the bound counts channels that HAVE an epg id, not positions in the line-up', () async {
      // The shape of a real line-up: 91% of channels carry no
      // `epg_channel_id` at all. Bounding an index over the unfiltered list
      // spends a slot on every channel it then skips, so a limit of two here
      // would reach only stream 303 and stop, leaving the two live screens
      // with one schedule between them. The bound has to apply to candidates.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 301, number: 1, name: 'No EPG 1', categoryId: '1'),
        _liveEntry(streamId: 302, number: 2, name: 'No EPG 2', categoryId: '1'),
        _liveEntry(streamId: 303, number: 3, name: 'Has EPG 1', categoryId: '1', epgChannelId: 'ch3'),
        _liveEntry(streamId: 304, number: 4, name: 'No EPG 3', categoryId: '1'),
        _liveEntry(streamId: 305, number: 5, name: 'Has EPG 2', categoryId: '1', epgChannelId: 'ch5'),
      ];
      for (final int streamId in <int>[303, 305]) {
        panel.shortEpgByStreamId[streamId] = <Map<String, dynamic>>[
          _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme'),
        ];
      }

      final ProviderSession session = ProviderSession(epgFetchLimit: 2);
      await session.start();
      await session.refresh();

      expect(panel.requestedShortEpgStreamIds, <int>[303, 305]);
      expect(session.channels.where((Channel c) => c.schedule.isNotEmpty), hasLength(2));
    });
  });

  group('user state, surviving a refresh', () {
    test('a favourite set before a refresh is still set after it', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Spor')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 301, number: 1, name: 'Kanal 1', categoryId: '1'),
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      session.setChannelFavourite(streamId: 301, favourite: true);
      expect(session.channels.firstWhere((Channel c) => c.streamId == 301).favourite, isTrue);

      await session.refresh();

      expect(session.channels.firstWhere((Channel c) => c.streamId == 301).favourite, isTrue);
    });

    test('a title favourite and progress survive a refresh through the store', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.vodCategories = <Map<String, dynamic>>[_vodCategory('1', 'Aksiyon')];
      panel.vodStreams = <Map<String, dynamic>>[_vodEntry(streamId: 401, name: 'Film 1', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      session.setTitleFavourite(kind: TitleKind.movie, providerId: 401, favourite: true);
      session.setTitleProgress(kind: TitleKind.movie, providerId: 401, progress: 0.5);

      await session.refresh();

      final TitleItem title = session.titles.firstWhere((TitleItem t) => t.providerId == 401);
      expect(title.favourite, isTrue);
      expect(title.progress, 0.5);
    });
  });

  group('the guards a real caller trips', () {
    test('two overlapping refreshes are one refresh', () async {
      // `DB.transaction` issues a literal `BEGIN TRANSACTION` on the one
      // shared connection, so two overlapping refreshes nest a `BEGIN`,
      // sqlite3 rejects it, and the inner `rollback()` discards the outer
      // transaction's rows too. Reachable by double-tapping the fault panel's
      // retry, which cannot repaint into a disabled state because the
      // controller notifies only after the refresh returns.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveStreams = <Map<String, dynamic>>[_liveEntry(streamId: 601, number: 1, name: 'Kanal', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();

      await Future.wait<void>(<Future<void>>[session.refresh(), session.refresh(), session.refresh()]);

      expect(panel.handshakeCalls, 1, reason: 'three calls, one refresh');
    });

    test('a refresh after the first one completes is a second refresh', () async {
      // The guard must not latch: the retry button has to work twice.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);

      final ProviderSession session = ProviderSession();
      await session.start();

      await session.refresh();
      await session.refresh();

      expect(panel.handshakeCalls, 2);
    });

    test('a keychain read failure becomes unreachable, not a boot failure', () async {
      // `MagicVaultService.get` wraps every PlatformException as
      // MagicVaultException on reads (`magic_vault_service.dart:48-54`), and
      // `FakeVaultService` cannot simulate that: every one of its overrides is
      // a no-throw body. `ThrowingVaultService` is the double built for this
      // exact shape. `start()` is awaited inside `Magic.init()`, which
      // `main()` awaits before `runApp()`, so an uncaught exception here
      // means no UI at all.
      ThrowingVaultService.install(VaultFailure.get);

      final ProviderSession session = ProviderSession();

      await expectLater(session.start(), completes);
      expect(session.fault, ProviderFault.unreachable);
      expect(session.hasCredentials, isFalse);
    });

    test('an unreadable stored credential becomes a fault, not a boot failure', () async {
      // `start()` is awaited inside `Magic.init()`, which `main()` awaits
      // before `runApp()`. A `FormatException` propagating from here aborts
      // the boot with no UI at all, and with no onboarding screen the user has
      // no way to clear the bad value.
      Vault.fake(<String, String>{XtreamCredentials.vaultKey: 'not a credential at all'});

      final ProviderSession session = ProviderSession();

      await expectLater(session.start(), completes);
      expect(session.hasCredentials, isFalse);
      expect(session.fault, ProviderFault.expired);
      driver.assertNothingSent();
    });
  });

  group('both title ID spaces', () {
    test('a movie and a series carrying the same number stay distinct titles', () async {
      // `stream_id` and `series_id` are different spaces and the numbers
      // collide, which is the whole reason `providerId` is only meaningful
      // beside `kind`. Fetching one space would fix /baslik to it, and the
      // retrofit would be a route change plus a store migration.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.vodCategories = <Map<String, dynamic>>[_vodCategory('1', 'Aksiyon')];
      panel.vodStreams = <Map<String, dynamic>>[_vodEntry(streamId: 500, name: 'Film', categoryId: '1')];
      panel.seriesCategories = <Map<String, dynamic>>[_vodCategory('9', 'Diziler')];
      panel.series = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Dizi', 'series_id': 500, 'category_id': '9'},
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      final TitleItem movie = session.titles.firstWhere((TitleItem t) => t.kind == TitleKind.movie);
      final TitleItem series = session.titles.firstWhere((TitleItem t) => t.kind == TitleKind.series);

      expect(session.titles, hasLength(2));
      expect(movie.providerId, 500);
      expect(series.providerId, 500);
      expect(movie.name, 'Film');
      expect(series.name, 'Dizi');
      expect(movie.category, 'Aksiyon');
      expect(series.category, 'Diziler');
    });

    test('an empty get_series is a real answer, not a gap', () async {
      // One of the four captured real panels answers `get_series` with
      // exactly `[]`, so the series half contributing nothing is an expected
      // shape rather than an error to surface.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.vodStreams = <Map<String, dynamic>>[_vodEntry(streamId: 501, name: 'Film', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      expect(session.titles, hasLength(1));
      expect(session.fault, isNull);
    });

    test('a series favourite is keyed on its own space, not the movie one', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.vodStreams = <Map<String, dynamic>>[_vodEntry(streamId: 500, name: 'Film', categoryId: '1')];
      panel.series = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Dizi', 'series_id': 500, 'category_id': '1'},
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      session.setTitleFavourite(kind: TitleKind.series, providerId: 500, favourite: true);
      await session.refresh();

      expect(session.titles.firstWhere((TitleItem t) => t.kind == TitleKind.series).favourite, isTrue);
      expect(session.titles.firstWhere((TitleItem t) => t.kind == TitleKind.movie).favourite, isFalse);
    });
  });

  group('the resolver choice, pushed into the one registered HostResolver', () {
    /// A resolver whose DoH rung is a recording double, so "which rung the next
    /// resolve consults" is a readable fact rather than a network call.
    (HostResolver, _ScriptedLookup) escalatingResolver() {
      final _ScriptedLookup doh = _ScriptedLookup('203.0.113.5');

      return (HostResolver(setting: ResolverSetting.system, system: _ScriptedLookup(), doh: doh), doh);
    }

    test('start() hands the stored credential its choice, so a restart keeps it', () async {
      Vault.fake();
      await XtreamCredentials(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'demo',
        userAgent: 'watchools/test',
        resolver: 'cloudflare',
      ).save();

      final (HostResolver resolver, _ScriptedLookup doh) = escalatingResolver();
      final ProviderSession session = ProviderSession(applyResolverSetting: resolver.updateSetting);

      // The composition root builds the resolver synchronously in `register()`,
      // long before any vault read, so this is the only moment a STORED choice
      // can reach it.
      await session.start();

      expect(session.providerResolution, (host: 'panel.example', setting: ResolverSetting.cloudflare));
      expect(await resolver.resolve('panel.example'), '203.0.113.5');
      expect(doh.calls, <String>['panel.example']);
    });

    test('adopt() with a different resolver changes which rung the next resolve consults', () async {
      Vault.fake();

      final (HostResolver resolver, _ScriptedLookup doh) = escalatingResolver();
      final ProviderSession session = ProviderSession(applyResolverSetting: resolver.updateSetting);
      await session.start();

      // Nothing stored, so nothing to escalate to: the system rung fails and
      // that is the whole ladder.
      expect(await resolver.resolve('panel.example'), isNull);
      expect(doh.calls, isEmpty);

      await session.adopt(
        XtreamCredentials(
          baseUrl: 'http://panel.example:8080',
          username: 'demo',
          password: 'demo',
          userAgent: 'watchools/test',
          resolver: 'google',
        ),
      );

      // Without this push the user would keep resolving through the previous
      // choice until the process restarts.
      expect(await resolver.resolve('panel.example'), '203.0.113.5');
      expect(doh.calls, <String>['panel.example']);
    });

    test('reports no resolution at all before a credential is loaded', () async {
      Vault.fake();

      final ProviderSession session = ProviderSession();
      await session.start();

      expect(session.providerResolution, isNull);
    });

    test('signOut() drops the address resolved for the panel being left', () async {
      Vault.fake();

      final (HostResolver resolver, _ScriptedLookup doh) = escalatingResolver();
      final ProviderSession session = ProviderSession(applyResolverSetting: resolver.updateSetting);
      await session.start();
      await session.adopt(
        XtreamCredentials(
          baseUrl: 'http://panel.example:8080',
          username: 'demo',
          password: 'demo',
          userAgent: 'watchools/test',
          resolver: 'cloudflare',
        ),
      );

      expect(await resolver.resolve('panel.example'), '203.0.113.5');

      await session.signOut();

      // The setting alone is inert once there is no credential to pin, so what
      // this asserts is the cache: without the push, the entry resolved for the
      // account just signed out would still answer here, which is a live
      // address for a panel the user no longer has.
      expect(await resolver.resolve('panel.example'), isNull);
      expect(doh.calls, <String>[
        'panel.example',
      ], reason: 'the DoH rung is gone with the setting, so it is not asked again');
    });
  });

  group('adopt(), accepting a credential at runtime', () {
    test('hasCredentials becomes true, the vault holds the record, and streamUrlFor works once refreshed', () async {
      Vault.fake();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Ulusal')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 10002, number: 2, name: '02 H.264 AAC | RAW TS', categoryId: '1'),
      ];

      final ProviderSession session = ProviderSession();
      await session.start();
      expect(session.hasCredentials, isFalse);

      await session.adopt(credentials);
      // adopt() never touches the network: the account is still unknown, so
      // streamUrlFor stays null until the caller decides to refresh.
      expect(session.hasCredentials, isTrue);
      await session.refresh();

      final Channel channel = session.channels.firstWhere((Channel each) => each.streamId != null);
      expect(session.streamUrlFor(channel), isNotNull);
      expect(await Vault.get(XtreamCredentials.vaultKey), isNotNull);
    });
  });

  group('signOut(), forgetting the current provider', () {
    test('a refresh already in flight cannot write the catalogue back afterwards', () async {
      // `AppServiceProvider.boot()` fires `refresh()` unawaited at cold start,
      // so a user who signs out a few seconds in leaves a batch of requests
      // running against the account they just left. Without a guard before the
      // held-catalogue assignment, the fetch completes and puts that account's
      // line-up back into a session that no longer has its credential:
      // `hasCredentials` false while `channels` is full, which is the half
      // state `signOut` exists to prevent.
      //
      // The sign-out is triggered from inside the EPG loop through the panel
      // double's own seam, which is the only point in a refresh where a test
      // can interleave.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Ulusal')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 801, number: 1, name: 'Kanal 1', categoryId: '1', epgChannelId: 'ch1'),
      ];
      panel.shortEpgByStreamId[801] = <Map<String, dynamic>>[
        _shortEpgListing(start: '2024-01-01 20:00:00', end: '2024-01-01 21:00:00', title: 'Programme'),
      ];

      final ProviderSession session = ProviderSession(developmentCredential: () => null);
      await session.start();

      panel.onShortEpg = (int _) => session.signOut();

      await session.refresh();

      expect(session.hasCredentials, isFalse, reason: 'the sign-out happened');
      expect(session.channels, isEmpty, reason: 'the in-flight refresh must not write back');

      // `panel.requestedVodStreams` and not `session.titles`, which was the
      // assertion here and could not fail: this double serves no VOD entries,
      // so `titles` is empty whether or not anything guards the write-back.
      // The VOD half is four requests against an account the user has just
      // left, so the assertion that carries weight is that they were never
      // sent.
      expect(panel.requestedVodStreams, isFalse, reason: 'a signed-out session must not fetch the VOD half');
    });

    test('a refresh already in flight cannot write back over a credential adopted while it ran', () async {
      // The case a null check misses, and the sharper of the two: a sign-out
      // nulls `_credentials`, so `_credentials == null` catches it, but
      // submitting a SECOND credential on `/saglayici` within those same
      // seconds leaves it non-null. The old guard then passed and `/` showed
      // the PREVIOUS account's channels under the new credential, none of them
      // playable because `adopt` nulls `_account`.
      //
      // Triggered from the `get_live_streams` seam rather than the EPG one:
      // that is the widest window in a refresh and the one the clock and
      // midnight reads used to sit behind.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Ulusal')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 901, number: 1, name: 'Eski hesap kanalı', categoryId: '1'),
      ];

      final XtreamCredentials other = XtreamCredentials(
        baseUrl: 'http://other.example:8080',
        username: 'someone-else',
        password: 'other',
        userAgent: 'watchools/test',
      );

      final ProviderSession session = ProviderSession(developmentCredential: () => null);
      await session.start();

      bool adopted = false;
      panel.onLiveStreams = () {
        if (adopted) return;
        adopted = true;
        session.adopt(other);
      };

      await session.refresh();

      // The adopted credential is the one standing, and its own account key
      // has no rows, so the line-up must be empty rather than the previous
      // account's.
      expect(session.hasCredentials, isTrue);
      expect(session.channels, isEmpty, reason: "the previous account's line-up must not be written back");
    });

    test('a sign-out inside the longest response does not crash the refresh', () async {
      // The window everything in the channel half reads its nullable fields
      // across. `get_live_streams` is the single longest response in a
      // refresh, 2,976 rows on a real subscription, and `_clock!` and
      // `_midnight!` used to be read immediately after it: `signOut` nulls
      // both, so a sign-out landing here threw `Null check operator used on a
      // null value` into the future `boot()` fires unawaited, a few seconds
      // into launch with no catch anywhere.
      //
      // Two earlier attempts narrowed this rather than closing it, first by
      // extending the EPG loop's own break, then by capturing before the loop
      // but still after this response. Both left this exact case open, and
      // `onShortEpg` cannot reach it because the EPG loop never starts.
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveCategories = <Map<String, dynamic>>[_liveCategory('1', 'Ulusal')];
      panel.liveStreams = <Map<String, dynamic>>[
        _liveEntry(streamId: 902, number: 1, name: 'Kanal', categoryId: '1', epgChannelId: 'ch1'),
      ];

      final ProviderSession session = ProviderSession(developmentCredential: () => null);
      await session.start();

      panel.onLiveStreams = () => session.signOut();

      // The assertion is that this completes at all. `refresh()` is what
      // `boot()` fires unawaited, so a throw here is the unhandled async error
      // the user would have seen instead of a UI.
      await session.refresh();

      expect(session.hasCredentials, isFalse);
      expect(session.channels, isEmpty);
    });

    test('clears the credential, the vault entry, and the held catalogue', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveStreams = <Map<String, dynamic>>[_liveEntry(streamId: 701, number: 1, name: 'Kanal', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();
      expect(session.channels, isNotEmpty);

      await session.signOut();

      expect(session.hasCredentials, isFalse);
      expect(session.channels, isEmpty);
      expect(session.titles, isEmpty);
      expect(await Vault.get(XtreamCredentials.vaultKey), isNull);
    });

    test('leaves the cached catalogue rows in place, because accountKey excludes the password', () async {
      await seedCredentials();
      panel.handshakeBody = _handshake(auth: 1, maxConnections: 2);
      panel.liveStreams = <Map<String, dynamic>>[_liveEntry(streamId: 801, number: 1, name: 'Kanal', categoryId: '1')];

      final ProviderSession session = ProviderSession();
      await session.start();
      await session.refresh();

      final String account = CatalogueStore.accountKey(credentials);
      expect(const CatalogueStore().channelsFor(account), isNotEmpty);

      await session.signOut();
      // Read the store directly rather than through the session: this is the
      // assertion that discriminates a real survival from adopt() simply
      // restoring whatever an empty table gives back.
      expect(const CatalogueStore().channelsFor(account), isNotEmpty);

      await session.adopt(credentials);
      expect(session.channels, isNotEmpty);
    });
  });
}
