import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/app/protocol/xtream/xtream_client.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/provider_session.dart';

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
        return MagicResponse(data: liveStreams, statusCode: 200);
      case 'get_short_epg':
        final int streamId = int.parse('${request.queryParameters?['stream_id']}');
        requestedShortEpgStreamIds.add(streamId);
        return MagicResponse(
          data: <String, dynamic>{'epg_listings': shortEpgByStreamId[streamId] ?? const <Map<String, dynamic>>[]},
          statusCode: 200,
        );
      case 'get_vod_categories':
        return MagicResponse(data: vodCategories, statusCode: 200);
      case 'get_vod_streams':
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
}
