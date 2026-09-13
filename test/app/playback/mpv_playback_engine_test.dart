import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/app/models/background_playback.dart';
import 'package:watchools/app/playback/mpv_playback_engine.dart';
import 'package:watchools/app/playback/playback_engine.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools_player/watchools_player.dart';

/// A credential whose secrets tell every encoding apart.
///
/// Alphanumeric secrets would prove nothing about redaction: all four spellings
/// `XtreamCredentials.redact` enumerates collapse into one, so a test that used
/// them would pass with three of the four missing. A `@` and a space are what
/// separate `Uri.encodeComponent`, `Uri.encodeQueryComponent` and the
/// `Uri(pathSegments:)` escaping a stream URL actually carries, and a `@` in a
/// password is the leak that reached a log line intact once already.
final XtreamCredentials _credentials = XtreamCredentials(
  baseUrl: 'http://panel.example:8080',
  username: 'b@b',
  password: 'p@ss word',
  userAgent: 'watchools/test',
);

/// The stream URL for that credential, built through the same
/// `Uri(pathSegments:)` constructor `XtreamStreamUrl._url` uses, so the
/// spelling under test is the one that reaches mpv rather than one hand-typed
/// here: `http://panel.example:8080/live/b@b/p@ss%20word/10002.ts`.
///
/// Note what that is not. `@` is legal in an RFC 3986 path segment, so it
/// survives into the wire spelling while the space does not, and the two
/// secrets are therefore spelled by two different rules in one URL. Neither
/// `Uri.encodeComponent` nor `Uri.encodeQueryComponent` produces this, which
/// is the whole reason `redact` derives a fourth form from this constructor.
final Uri _source = Uri(
  scheme: 'http',
  host: 'panel.example',
  port: 8080,
  pathSegments: <String>['live', _credentials.username, _credentials.password, '10002.ts'],
);

/// The surface a consumer hands over once, before the first load.
const PlaybackSurface _surface = PlaybackSurface(platformViewId: 3);

/// One tick as the native side spells it, over the wire.
///
/// `session` defaults to 1 for every load on purpose: `MpvEngine.start` calls
/// `mpv_create` per load and refuses a second while a core is alive, so every
/// load runs on a fresh core whose first `playlist_entry_id` is 1. The
/// transport's stamp therefore does not increase between loads, which is the
/// measurement behind the engine stamping its own.
Map<String, Object?> _tickEvent({
  required double atSeconds,
  required double? timePos,
  int session = 1,
  bool paused = false,
  bool? underrun = false,
  bool? demuxerIdle = false,
}) => <String, Object?>{
  'event': 'tick',
  'session': session,
  'monotonicNs': (atSeconds * 1e9).round(),
  'timePos': timePos,
  'paused': paused,
  'coreIdle': false,
  // The measured 80 KB of a healthy continuous stream, which does not grow.
  'forwardBytes': 81920,
  'inputRate': 1266000,
  'underrun': underrun,
  'demuxerIdle': demuxerIdle,
};

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  const String eventChannel = 'watchools_player/events';
  const MethodChannel commandChannel = MethodChannel('watchools_player');
  const StandardMethodCodec codec = StandardMethodCodec();

  final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late FakeLogManager log;
  late List<bool> wakelockCalls;

  /// The lifecycle chain [AppLifecycleListener] asserts, foreground first.
  ///
  /// `resumed <-> inactive <-> hidden <-> paused`
  /// (`app_lifecycle_listener.dart:222-269`, one assert per member). `detached`
  /// sits past `paused` and nothing here needs it.
  const List<AppLifecycleState> chain = <AppLifecycleState>[
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];

  /// Where the binding currently sits in [chain], for the whole file.
  ///
  /// File-wide rather than per case because the binding is: see the tearDown.
  int depth = 0;

  /// Drives the binding to [target], one valid transition at a time.
  ///
  /// `handleAppLifecycleStateChanged` is public and fans out to every observer
  /// (`binding.dart:1329-1334`), which is what a plain `test()` has instead of
  /// a tester. One step at a time because a jump asserts: an engine's listener
  /// tracks its own previous state and throws `Invalid state transition` rather
  /// than synthesising the states in between.
  ///
  /// The trailing wait is what lets the engine's branch finish. Its
  /// `onPause` is a [VoidCallback], so the work it starts is a future nobody
  /// holds, and an assertion in the same microtask would read the state before
  /// it.
  Future<void> lifecycle(AppLifecycleState target) async {
    final int destination = chain.indexOf(target);

    while (depth != destination) {
      depth += depth < destination ? 1 : -1;
      binding.handleAppLifecycleStateChanged(chain[depth]);
    }

    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls = <MethodCall>[];
    log = Log.fake();
    wakelockCalls = <bool>[];

    // The event channel answers `listen` and `cancel`, which is what carries
    // `onListen` far enough to install the message handler events arrive on.
    messenger.setMockMethodCallHandler(const MethodChannel(eventChannel), (MethodCall call) async => null);
    messenger.setMockMethodCallHandler(commandChannel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    // The binding's lifecycle state outlives a case in this file. `postTest`,
    // which resets it, is registered only by the `WidgetTester` harness
    // (`widget_tester.dart:183`), which this file does not use and must not:
    // `push` waits on a real `Future.delayed`, and that harness's fake clock
    // stalls it. Left at `paused`, the next case's engine seeds its listener
    // from the binding (`app_lifecycle_listener.dart:78`) and either misses the
    // transition it never makes or throws `Invalid state transition` on its
    // first `resumed`.
    //
    // A declared tearDown rather than an `addTearDown`: declared ones are
    // registered before the body runs (`declarer.dart:241-248`) and tearDowns
    // run last-in first-out (`invoker.dart:296`), so this walks back up after
    // `engine.dispose` has removed the listener rather than past a live one.
    await lifecycle(AppLifecycleState.resumed);

    messenger.setMockMethodCallHandler(const MethodChannel(eventChannel), null);
    messenger.setMockMethodCallHandler(commandChannel, null);
    Log.unfake();
  });

  /// The method names the platform received, in order.
  List<String> methods() => calls.map((MethodCall call) => call.method).toList();

  /// Pushes one event the way the platform does and lets it be delivered.
  ///
  /// `receiveBroadcastStream`'s controller is asynchronous, so an assertion
  /// made in the same microtask as the push would read the state before it.
  Future<void> push(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(eventChannel, codec.encodeSuccessEnvelope(event), (ByteData? _) {});
    await Future<void>.delayed(Duration.zero);
  }

  /// An engine whose upstream handler is installed, disposed with the test.
  ///
  /// The handler goes in from an async `onListen`, so a push issued in the same
  /// microtask as the constructor would reach a channel nobody is holding.
  ///
  /// [background] is the choice the injected closure reports, read fresh on
  /// every lifecycle event rather than stored, so a case needs neither a
  /// database nor a vault to reach an arm.
  Future<MpvPlaybackEngine> engine({BackgroundPlayback background = BackgroundPlayback.stop}) async {
    final MpvPlaybackEngine engine = MpvPlaybackEngine(
      redact: _credentials.redact,
      toggleWakelock: ({required bool enable}) async => wakelockCalls.add(enable),
      backgroundPlayback: () => background,
    );

    addTearDown(engine.dispose);
    await Future<void>.delayed(Duration.zero);

    return engine;
  }

  /// An engine with a surface and one open load, which is where every health
  /// and tick case starts.
  Future<MpvPlaybackEngine> loaded({BackgroundPlayback background = BackgroundPlayback.stop}) async {
    final MpvPlaybackEngine started = await engine(background: background);

    await started.attach(_surface);
    await started.load(_source);
    calls.clear();

    return started;
  }

  group('the contract, over the plugin', () {
    test('is a PlaybackEngine and describes no session before a load', () async {
      final MpvPlaybackEngine started = await engine();

      expect(started, isA<PlaybackEngine>());
      expect(started.health, PlaybackHealth.idle);
      expect(started.session, isNull);
    });

    test('a load before a surface fails loudly rather than sending a call with no native peer', () async {
      final MpvPlaybackEngine started = await engine();

      await expectLater(started.load(_source), throwsStateError);
      expect(calls, isEmpty);
    });

    test('a load stops whatever core is alive before opening the next one', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source, userAgent: 'watchools/test');
      await started.load(_source);

      // `stop` leads even the first load: `MpvEngine.start` refuses while a
      // core is alive, and a hot restart leaves the native plugin, its factory
      // and its core standing while the Dart side starts over.
      expect(methods(), <String>['stop', 'play', 'stop', 'play']);
      expect(calls.first.arguments, isNull);
      expect(calls[1].arguments, <String, Object?>{
        'viewId': 3,
        'url': 'http://panel.example:8080/live/b@b/p@ss%20word/10002.ts',
        'userAgent': 'watchools/test',
      });
    });

    test('pause and resume are one native call with two arguments', () async {
      final MpvPlaybackEngine started = await loaded();

      await started.pause();
      await started.resume();

      expect(methods(), <String>['setPaused', 'setPaused']);
      expect(calls.map((MethodCall call) => call.arguments), <bool>[true, false]);
      // Neither invents a verdict: health moves when a tick is read and at no
      // other moment, exactly as mpv behaves.
      expect(started.health, PlaybackHealth.idle);
    });
  });

  group('redaction, the single filter', () {
    test('a log line naming the stream URL loses both secrets and reaches no consumer', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<PlaybackTick> seen = <PlaybackTick>[];
      final StreamSubscription<PlaybackTick> reader = started.ticks.listen(seen.add);

      // FFmpeg's own reconnect warning, which is the only signal a subscription
      // token is lapsing and therefore cannot be switched off. The URL in it is
      // the one the engine handed the platform, not a retyped one, so the
      // spelling this asserts against cannot drift from the spelling that
      // leaks.
      await push(<String, Object?>{
        'event': 'log',
        'level': 'warn',
        'text': 'http: Will reconnect at 0 to $_source, error=End of file.',
      });

      expect(log.entries, hasLength(1));
      expect(log.entries.single.level, 'warning');
      expect(log.entries.single.message, isNot(contains('p@ss%20word')));
      expect(log.entries.single.message, isNot(contains('p%40ss%20word')));
      expect(log.entries.single.message, isNot(contains('p@ss word')));
      expect(log.entries.single.message, isNot(contains('b@b')));
      expect(log.entries.single.message, contains('http://panel.example:8080/live/***/***/10002.ts'));
      // Nothing textual reaches a consumer at all: the interface has no member
      // that could carry it.
      expect(seen, isEmpty);
      expect(started.session, isNull);

      await reader.cancel();
    });

    test('an error line is reported at error rather than downgraded to debug', () async {
      final MpvPlaybackEngine started = await loaded();

      // mpv spells this `error`, and the Log facade's console driver maps an
      // unknown level to debug, so the level is mapped here rather than passed
      // through.
      await push(<String, Object?>{
        'event': 'log',
        'level': 'error',
        'text': 'ffmpeg/demuxer: http: Will reconnect at 0, error=Immediate exit requested',
      });

      expect(log.entries.single.level, 'error');
      expect(started.health, PlaybackHealth.idle);
    });

    test('a platform failure naming the URL arrives redacted', () async {
      final MpvPlaybackEngine started = await engine();

      messenger.setMockMethodCallHandler(commandChannel, (MethodCall call) async {
        if (call.method != 'play') return null;

        throw PlatformException(code: 'mpv', message: 'could not open $_source');
      });

      await started.attach(_surface);

      await expectLater(
        started.load(_source),
        throwsA(
          isA<PlatformException>()
              .having((PlatformException failure) => failure.code, 'code', 'mpv')
              .having((PlatformException failure) => failure.message, 'message', isNot(contains('p@ss%20word')))
              .having((PlatformException failure) => failure.message, 'message', isNot(contains('b@b')))
              .having(
                (PlatformException failure) => failure.message,
                'message',
                contains('http://panel.example:8080/live/***/***/10002.ts'),
              ),
        ),
      );
      // The failed load left no session behind to describe.
      expect(started.session, isNull);
      expect(started.health, PlaybackHealth.idle);
    });
  });

  group('one upstream subscription, fanned out', () {
    test('two consumers of the engine stream both receive every tick', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<int> first = <int>[];
      final List<int> second = <int>[];
      final StreamSubscription<PlaybackTick> a = started.ticks.listen(
        (PlaybackTick tick) => first.add(tick.monotonicNs),
      );
      final StreamSubscription<PlaybackTick> b = started.ticks.listen(
        (PlaybackTick tick) => second.add(tick.monotonicNs),
      );

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      await push(_tickEvent(atSeconds: 1.5, timePos: 10.5));

      expect(first, <int>[1000000000, 1500000000]);
      expect(second, first);

      await a.cancel();
      await b.cancel();
    });

    test('dispose stops the core and cancels the subscription, so a later event reaches nobody', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<PlaybackTick> seen = <PlaybackTick>[];
      final StreamSubscription<PlaybackTick> reader = started.ticks.listen(seen.add);

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      await started.dispose();
      await push(_tickEvent(atSeconds: 1.5, timePos: 10.5));
      // A log line, and it is the assertion that carries this test. A tick
      // after dispose is refused by the closed session as well as by the
      // cancelled subscription, so it passes with the cancel deleted; nothing
      // gates a log line except the subscription itself, so an entry appearing
      // here is a subscription still live. Verified by deleting the cancel and
      // watching this fail.
      await push(<String, Object?>{'event': 'log', 'level': 'warn', 'text': 'http: Will reconnect at 0'});

      expect(methods(), contains('stop'));
      expect(seen, hasLength(1));
      expect(log.entries, isEmpty);
      expect(started.health, PlaybackHealth.idle);

      await reader.cancel();
    });
  });

  group('the session stamp, which the transport cannot supply', () {
    test('each load raises the stamp, though the transport reuses playlist_entry_id 1', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<int> stamps = <int>[];
      final StreamSubscription<PlaybackTick> reader = started.ticks.listen(
        (PlaybackTick tick) => stamps.add(tick.session),
      );

      await push(_tickEvent(atSeconds: 1, timePos: 300));
      expect(started.session, 1);

      await started.load(_source);
      // A fresh core restarts at position zero while its stamp is still 1, so
      // an engine forwarding the transport's stamp would hand the detector a
      // position that went backwards inside one session and read a healthy
      // channel as frozen.
      await push(_tickEvent(atSeconds: 2, timePos: 0.5));

      expect(stamps, <int>[1, 2]);
      expect(started.session, 2);
      expect(started.health, PlaybackHealth.playing);

      await reader.cancel();
    });

    test('every counter survives the re-stamp', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<PlaybackTick> seen = <PlaybackTick>[];
      final StreamSubscription<PlaybackTick> reader = started.ticks.listen(seen.add);

      await push(<String, Object?>{
        'event': 'tick',
        'session': 1,
        'monotonicNs': 123456789,
        'timePos': 15.5,
        'paused': true,
        'coreIdle': true,
        'forwardBytes': 81920,
        'inputRate': 190235,
        'underrun': true,
        'demuxerIdle': true,
      });

      final PlaybackTick tick = seen.single;

      expect(tick.session, 1);
      expect(tick.monotonicNs, 123456789);
      expect(tick.timePos, 15.5);
      expect(tick.paused, isTrue);
      expect(tick.coreIdle, isTrue);
      expect(tick.forwardBytes, 81920);
      expect(tick.inputRate, 190235);
      expect(tick.underrun, isTrue);
      expect(tick.demuxerIdle, isTrue);

      await reader.cancel();
    });
  });

  group('health, from the detector and nowhere else', () {
    test('is idle between a load and its first tick, and playing once one advances', () async {
      final MpvPlaybackEngine started = await loaded();

      expect(started.health, PlaybackHealth.idle);

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      expect(started.health, PlaybackHealth.playing);

      await push(_tickEvent(atSeconds: 1.5, timePos: 10.5));
      expect(started.health, PlaybackHealth.playing);
    });

    test('a frozen position past the grace is a stall', () async {
      final MpvPlaybackEngine started = await loaded();

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      await push(_tickEvent(atSeconds: 6, timePos: 10, underrun: true));
      expect(started.health, PlaybackHealth.starving);

      await push(_tickEvent(atSeconds: 14, timePos: 10, underrun: true));
      expect(started.health, PlaybackHealth.stalled);
    });

    test('a tick arriving after stop reaches nobody and revives no verdict', () async {
      final MpvPlaybackEngine started = await loaded();
      final List<PlaybackTick> seen = <PlaybackTick>[];
      final StreamSubscription<PlaybackTick> reader = started.ticks.listen(seen.add);

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      await started.stop();
      // The straggler every real transport produces: the core is terminated,
      // but a payload already handed to the main queue still arrives.
      await push(_tickEvent(atSeconds: 1.5, timePos: 10.5));

      expect(methods(), <String>['stop']);
      expect(seen, hasLength(1));
      expect(started.health, PlaybackHealth.idle);

      await reader.cancel();
    });
  });

  group('the wakelock, held for the core\'s lifetime', () {
    test('a load enables the hold exactly once, not once per tick', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source);

      expect(wakelockCalls, <bool>[true]);
      wakelockCalls.clear();

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      await push(_tickEvent(atSeconds: 1.5, timePos: 10.5));

      // Enabling happened once, on load, and nothing on the tick path repeats
      // it: `_receive` never reaches the seam.
      expect(wakelockCalls, isEmpty);

      await started.stop();
    });

    test('stop releases the hold', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source);
      wakelockCalls.clear();

      await started.stop();

      expect(wakelockCalls, <bool>[false]);
    });

    test('dispose releases the hold', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source);
      wakelockCalls.clear();

      await started.dispose();

      expect(wakelockCalls, <bool>[false]);
    });

    test('a load that never opened a core holds nothing', () async {
      final MpvPlaybackEngine started = await engine();

      messenger.setMockMethodCallHandler(commandChannel, (MethodCall call) async {
        if (call.method != 'play') return null;

        throw PlatformException(code: 'mpv', message: 'could not open the stream');
      });

      await started.attach(_surface);
      await expectLater(started.load(_source), throwsA(isA<PlatformException>()));

      // Nothing was ever held, so nothing is owed. The enable sits after the
      // platform call precisely so that a load which fails holds nothing.
      expect(wakelockCalls, isEmpty);
    });

    test('a channel change that fails releases the hold the previous channel had', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source);

      expect(wakelockCalls, <bool>[true]);
      wakelockCalls.clear();

      messenger.setMockMethodCallHandler(commandChannel, (MethodCall call) async {
        if (call.method != 'play') return null;

        throw PlatformException(code: 'mpv', message: 'could not open the stream');
      });

      await expectLater(started.load(_source), throwsA(isA<PlatformException>()));

      // The leak this closes: `load` stops the previous core before opening
      // the next one, so a failure here ends with nothing playing while the
      // display is still held awake. Neither `stop` nor `dispose` would ever
      // release it, because both guard on the same flag and the screen has no
      // reason to call either after a channel change it never saw succeed.
      expect(wakelockCalls, <bool>[false]);
    });

    test('a second load without an intervening stop does not leak a second hold', () async {
      final MpvPlaybackEngine started = await engine();

      await started.attach(_surface);
      await started.load(_source);
      await started.load(_source);
      wakelockCalls.clear();

      await started.stop();

      // One release is all a boolean hold can ever owe, regardless of how
      // many loads opened it.
      expect(wakelockCalls, <bool>[false]);
    });
  });

  // The `true` every case here starts from is the hold `loaded()` took, kept in
  // the assertion rather than cleared so the release is read against it.
  group('backgrounding, on the choice the user made', () {
    test('the default tears the core down and drops the display hold', () async {
      final MpvPlaybackEngine started = await loaded();

      await lifecycle(AppLifecycleState.paused);

      expect(methods(), <String>['stop']);
      expect(wakelockCalls, <bool>[true, false]);

      // The session is closed, so the straggler a terminated core still
      // produces is dropped rather than reviving a verdict.
      await push(_tickEvent(atSeconds: 1, timePos: 10));
      expect(started.health, PlaybackHealth.idle);
    });

    test('audio keeps the core and drops only the display hold', () async {
      final MpvPlaybackEngine started = await loaded(background: BackgroundPlayback.audio);

      await lifecycle(AppLifecycleState.paused);

      // Nothing crossed to the platform. Stopping the core is the one thing
      // this choice exists to prevent, and the display hold is what a
      // backgrounded app has no business keeping.
      expect(calls, isEmpty);
      expect(wakelockCalls, <bool>[true, false]);

      // The load is still open, which a closed session would not be: a tick
      // arriving while the app is away is still accepted.
      await push(_tickEvent(atSeconds: 1, timePos: 10));
      expect(started.health, PlaybackHealth.playing);
    });

    test('pictureInPicture is the same arm as audio, and that is the point', () async {
      final MpvPlaybackEngine started = await loaded(background: BackgroundPlayback.pictureInPicture);

      await lifecycle(AppLifecycleState.paused);

      // Everything that separates the two is platform work on targets that do
      // not exist yet (Android's `PictureInPictureParams`, on iOS an
      // AVFoundation engine libmpv cannot feed). The Dart half of both is
      // "do not stop the core".
      expect(calls, isEmpty);
      expect(wakelockCalls, <bool>[true, false]);

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      expect(started.health, PlaybackHealth.playing);
    });

    test('coming back to the foreground reloads nothing', () async {
      final MpvPlaybackEngine started = await loaded();

      await lifecycle(AppLifecycleState.paused);
      calls.clear();
      wakelockCalls.clear();

      await lifecycle(AppLifecycleState.resumed);

      // The tempting case, and the wrong one: the core was stopped on the way
      // out, so a reload here would retake the account's single connection slot
      // (measured `max_connections: 1`) and evict whichever device picked it up
      // while the user was away, which is the harm stopping exists to prevent.
      // The user asking for a picture is what calls `load`.
      expect(calls, isEmpty);
      expect(wakelockCalls, isEmpty);
      expect(started.health, PlaybackHealth.idle);
    });

    test('the macOS occlusion sequence is not a backgrounding', () async {
      final MpvPlaybackEngine started = await loaded();

      // `resumed -> inactive -> hidden` and no further, which is the whole
      // sequence a desktop embedder can deliver: `paused` "is only entered on
      // iOS and Android" (`platform_dispatcher.dart:2444`). This is the only
      // mechanical proof that no macOS behaviour changed, and the reason no
      // `Platform.isAndroid` check is written anywhere.
      await lifecycle(AppLifecycleState.hidden);

      expect(calls, isEmpty);
      expect(wakelockCalls, <bool>[true]);

      await push(_tickEvent(atSeconds: 1, timePos: 10));
      expect(started.health, PlaybackHealth.playing);
    });

    test('a disposed engine hears no lifecycle event at all', () async {
      final MpvPlaybackEngine started = await loaded();

      await started.dispose();
      calls.clear();
      wakelockCalls.clear();

      await lifecycle(AppLifecycleState.paused);

      // The binding holds an observer by a strong reference for the process's
      // life (`binding.dart:859-878`), so an engine that did not remove its own
      // would answer this with a platform call after its own teardown. In this
      // file it would answer the NEXT case's backgrounding too.
      expect(calls, isEmpty);
      expect(wakelockCalls, isEmpty);
      expect(started.health, PlaybackHealth.idle);
    });

    test('a second dispose is the no-op the interface promises', () async {
      final MpvPlaybackEngine started = await loaded();

      await started.dispose();

      // Promise 7: `stop` and `dispose` are idempotent, and
      // `PlaybackController.detach` calls into an engine the platform may
      // already have torn down. `AppLifecycleListener.dispose` throws on a
      // second call (`app_lifecycle_listener.dart:179-187` asserts it was not
      // disposed), so the engine lets go of its listener rather than holding
      // one it cannot dispose twice. Every case in this file also disposes from
      // its own tearDown, so without this the whole file would go red.
      await expectLater(started.dispose(), completes);
    });
  });
}
