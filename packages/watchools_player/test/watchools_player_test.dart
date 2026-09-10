import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchools_player/watchools_player.dart';

/// Guards the one property of the event stream that a reader depends on and
/// cannot check for itself: that two consumers both receive every event.
///
/// This is not a hypothetical. `EventChannel.receiveBroadcastStream` builds a
/// new `StreamController` per call whose `onListen` runs
/// `binaryMessenger.setMessageHandler(name, ...)`, and a messenger holds one
/// handler per channel name, so an `events` getter that called it per access
/// let the second consumer silently take the stream from the first. The variant
/// ladder and a mini player are two consumers by construction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String channel = 'watchools_player/events';
  const StandardMethodCodec codec = StandardMethodCodec();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the `listen` and `cancel` calls the stream makes on subscribe, so
  /// `onListen` reaches the point where it installs the message handler.
  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(channel),
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(channel), null);
  });

  /// Pushes one event the way the platform does, through the handler the
  /// stream's `onListen` registered.
  Future<void> emit(Map<String, Object?> event) {
    return messenger.handlePlatformMessage(
      channel,
      codec.encodeSuccessEnvelope(event),
      (ByteData? _) {},
    );
  }

  test('two consumers both receive every event', () async {
    final List<String> first = <String>[];
    final List<String> second = <String>[];

    final StreamSubscription<PlayerEvent> a = WatchoolsPlayer.events.listen(
      (PlayerEvent event) => first.add(event.name),
    );
    final StreamSubscription<PlayerEvent> b = WatchoolsPlayer.events.listen(
      (PlayerEvent event) => second.add(event.name),
    );
    // Let both subscriptions' onListen complete before anything is pushed:
    // the handler is installed inside an async callback.
    await Future<void>.delayed(Duration.zero);

    await emit(<String, Object?>{'event': 'videoReconfig'});
    await emit(<String, Object?>{'event': 'endFile', 'reason': 0, 'error': 0});

    expect(first, <String>['videoReconfig', 'endFile']);
    expect(second, <String>['videoReconfig', 'endFile']);

    await a.cancel();
    await b.cancel();
  });

  test('an end on a live stream is a clean EOF, which is a fault', () {
    final PlayerEvent event = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'endFile',
      'reason': 0,
      'error': 0,
    });

    expect(event.isEnd, isTrue);
    // Measured against the real panel and reproduced by the mock: a lapsed
    // stream token arrives as mpv's EOF with no error, so a reader keyed to
    // `error != 0` sees a normal finish.
    expect(event.reason, 0);
    expect(event.error, 0);
  });

  test('a dropped-event gap is distinguishable from quiet', () {
    final PlayerEvent gap = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'eventsLost',
    });
    final PlayerEvent log = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'log',
      'level': 'warn',
      'text': 'http: Will reconnect at 0 in 1 second(s), error=End of file.',
    });

    expect(gap.isGap, isTrue);
    expect(log.isGap, isFalse);
    expect(log.level, 'warn');
  });

  test('a tick carries the counters and its session', () {
    final PlayerEvent event = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'tick',
      'session': 3,
      'monotonicNs': 123456789,
      'timePos': 15.5,
      'paused': false,
      'coreIdle': false,
      'forwardBytes': 81920,
      'inputRate': 190235,
      'underrun': false,
      'demuxerIdle': false,
    });

    expect(event.session, 3);
    expect(event.tick, isNotNull);
    expect(event.tick!.timePos, 15.5);
    expect(event.tick!.forwardBytes, 81920);
    expect(event.tick!.underrun, isFalse);
  });

  test('an absent cache field reads as unknown, never as healthy', () {
    // `underrun`, `idle` and `eof` sit under mpv's "might be changed or
    // removed" heading, so a build without them must not report health the
    // core never asserted.
    final PlayerTick tick = PlayerTick.fromNative(<Object?, Object?>{
      'session': 1,
      'monotonicNs': 1,
      'paused': false,
      'coreIdle': false,
    });

    expect(tick.underrun, isNull);
    expect(tick.demuxerIdle, isNull);
    expect(tick.forwardBytes, isNull);
    expect(tick.timePos, isNull);
    // And the two that are not optional still read, so a missing optional does
    // not take the whole sample with it.
    expect(tick.paused, isFalse);
    expect(tick.session, 1);
  });

  test('a non-tick event carries its session but no counters', () {
    final PlayerEvent event = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'endFile',
      'session': 7,
      'reason': 0,
      'error': 0,
    });

    expect(event.session, 7);
    expect(event.tick, isNull);
    expect(event.isEnd, isTrue);
  });

  test('an unknown event name survives the trip', () {
    // The native set grows with the variant ladder, and a build pairing a new
    // engine with an older Dart side must not drop what it cannot name.
    final PlayerEvent event = PlayerEvent.fromNative(<Object?, Object?>{
      'event': 'somethingLater',
    });

    expect(event.name, 'somethingLater');
    expect(event.isEnd, isFalse);
  });

  test('setPaused sends the flag as-is on the method channel', () async {
    MethodCall? received;
    const MethodChannel command = MethodChannel('watchools_player');
    messenger.setMockMethodCallHandler(command, (MethodCall call) async {
      received = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(command, null));

    await WatchoolsPlayer.setPaused(true);

    expect(received?.method, 'setPaused');
    expect(received?.arguments, true);
  });
}
