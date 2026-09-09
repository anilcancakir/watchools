import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/playback/fake_playback_engine.dart';
import 'package:watchools/app/playback/playback_engine.dart';
import 'package:watchools_player/watchools_player.dart';

/// The surface a consumer hands over once, before the first load.
const PlaybackSurface _surface = PlaybackSurface(platformViewId: 3);

/// One provider URL. Nothing below reads it: the interface takes a [Uri] and
/// knows nothing about what built it.
final Uri _source = Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.ts');

/// The measured tick shapes, as one builder.
///
/// Nine required fields and only four of them decide a verdict, so the healthy
/// continuous shape is the default and each case below names only what it is
/// about. `forwardBytes` is the measured 80 KB of a healthy stream rather than
/// anything growing, because on this transport it does not grow
/// (`watchools_player.dart:216`).
///
/// [timePos] is required rather than defaulted to null: a tick carrying no
/// position is a case one of these tests is about, not an omission.
PlaybackTick _tick({
  required int session,
  required double atSeconds,
  required double? timePos,
  bool paused = false,
  bool? underrun = false,
  bool? demuxerIdle = false,
}) => PlaybackTick(
  session: session,
  monotonicNs: (atSeconds * 1e9).round(),
  timePos: timePos,
  paused: paused,
  coreIdle: false,
  forwardBytes: 81920,
  inputRate: 1266000,
  underrun: underrun,
  demuxerIdle: demuxerIdle,
);

/// An engine with a surface and an open load, which is the state every health
/// case starts from.
Future<FakePlaybackEngine> _loaded() async {
  final FakePlaybackEngine engine = FakePlaybackEngine();

  await engine.attach(_surface);
  await engine.load(_source);

  return engine;
}

void main() {
  group('the interface, satisfied without a platform', () {
    test('a fake is a PlaybackEngine and reports idle before anything is loaded', () {
      final PlaybackEngine engine = FakePlaybackEngine();

      expect(engine, isA<PlaybackEngine>());
      expect(engine.health, PlaybackHealth.idle);
      expect(engine.session, isNull);
    });

    test('records every command in the order the consumer called them', () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();

      await engine.attach(_surface);
      await engine.load(_source, userAgent: 'Watchools/1.0');
      await engine.pause();
      await engine.resume();
      await engine.stop();
      await engine.dispose();

      expect(engine.commands, <FakePlaybackCommand>[
        FakePlaybackCommand.attach,
        FakePlaybackCommand.load,
        FakePlaybackCommand.pause,
        FakePlaybackCommand.resume,
        FakePlaybackCommand.stop,
        FakePlaybackCommand.dispose,
      ]);
      expect(engine.surface, _surface);
      expect(engine.source, _source);
      expect(engine.userAgent, 'Watchools/1.0');
    });

    test('pause and resume move no verdict of their own', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      await engine.pause();

      expect(engine.health, PlaybackHealth.playing);

      engine.emit(_tick(session: 1, atSeconds: 0.5, timePos: 10.0, paused: true));

      expect(engine.health, PlaybackHealth.paused);
    });

    test('loading without a surface is a programming error rather than a silent no-op', () {
      final FakePlaybackEngine engine = FakePlaybackEngine();

      expect(() => engine.load(_source), throwsStateError);
    });

    test('a surface compares by its identifier, which is what a runtime-built one needs', () {
      final PlaybackSurface built = PlaybackSurface(platformViewId: int.parse('3'));

      expect(built, _surface);
      expect(built.hashCode, _surface.hashCode);
      expect(built, isNot(const PlaybackSurface(platformViewId: 4)));
      expect(built.toString(), contains('3'));
    });
  });

  group('health, driven by a scripted tick sequence', () {
    test('idle while a load has produced no position yet', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: null));

      expect(engine.health, PlaybackHealth.idle);
    });

    test('playing once the position advances', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 0.5, timePos: 10.5));

      expect(engine.health, PlaybackHealth.playing);
    });

    test('paused, whatever the position does', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 0.5, timePos: 10.0, paused: true));

      expect(engine.health, PlaybackHealth.paused);
    });

    test('notPresenting for the measured idle-display shape, never stalled', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));

      // The display sleeps here: position frozen, the reader satisfied, the
      // buffer full (`player-layer.md:587`, measured). Held well past the
      // grace, because this shape must never accumulate toward a stall.
      for (final double at in <double>[1, 5, 20, 60]) {
        engine.emit(_tick(session: 1, atSeconds: at, timePos: 10.0, demuxerIdle: true));

        expect(engine.health, PlaybackHealth.notPresenting);
      }
    });

    test('starving while frozen and out of data inside the grace', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 10, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 18, timePos: 10.0, underrun: true));

      // Eight seconds is the measured live-window starvation. A verdict of
      // stalled here would switch variants on a healthy channel.
      expect(engine.health, PlaybackHealth.starving);
    });

    test('stalled only once the freeze reaches the grace', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 10, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 21.9, timePos: 10.0, underrun: true));

      expect(engine.health, PlaybackHealth.starving);

      engine.emit(_tick(session: 1, atSeconds: 22, timePos: 10.0, underrun: true));

      expect(engine.health, PlaybackHealth.stalled);
    });

    test('an unreported underrun is never read as health', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 30, timePos: 10.0, underrun: null, demuxerIdle: null));

      expect(engine.health, PlaybackHealth.stalled);
    });

    test('one sequence reaches every member of PlaybackHealth', () async {
      final FakePlaybackEngine engine = await _loaded();
      final List<PlaybackTick> script = <PlaybackTick>[
        _tick(session: 1, atSeconds: 0, timePos: null),
        _tick(session: 1, atSeconds: 0.5, timePos: 10.0),
        _tick(session: 1, atSeconds: 1, timePos: 10.0, paused: true),
        _tick(session: 1, atSeconds: 1.5, timePos: 10.5),
        _tick(session: 1, atSeconds: 2, timePos: 10.5, demuxerIdle: true),
        _tick(session: 1, atSeconds: 3, timePos: 10.5, underrun: true),
        _tick(session: 1, atSeconds: 14.1, timePos: 10.5, underrun: true),
      ];
      final Set<PlaybackHealth> reached = <PlaybackHealth>{};

      for (final PlaybackTick tick in script) {
        engine.emit(tick);
        reached.add(engine.health);
      }

      expect(reached, PlaybackHealth.values.toSet());
    });
  });

  group('the session stamp', () {
    test('health is idle between a load and its first tick', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 7, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 7, atSeconds: 0.5, timePos: 10.5));

      expect(engine.health, PlaybackHealth.playing);

      await engine.load(_source);

      expect(engine.health, PlaybackHealth.idle);
      expect(engine.session, 7);
    });

    test('stop and dispose return health to idle', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 1, atSeconds: 0.5, timePos: 10.5));
      await engine.stop();

      expect(engine.health, PlaybackHealth.idle);

      await engine.dispose();

      expect(engine.health, PlaybackHealth.idle);
    });

    test('a tick from the load that was replaced is not read as the current one', () async {
      final FakePlaybackEngine engine = await _loaded();
      final List<int> seen = <int>[];
      final StreamSubscription<PlaybackTick> subscription = engine.ticks.listen(
        (PlaybackTick tick) => seen.add(tick.session),
      );

      engine.emit(_tick(session: 7, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 7, atSeconds: 1, timePos: 10.0, underrun: true));

      expect(engine.health, PlaybackHealth.starving);

      await engine.load(_source);

      // In flight when the load landed: the previous load's last sample, which
      // a reader without the stamp takes for the new load's first.
      engine.emit(_tick(session: 7, atSeconds: 2, timePos: 10.0, underrun: true));

      expect(engine.health, PlaybackHealth.idle);
      expect(engine.session, 7);

      engine.emit(_tick(session: 8, atSeconds: 3, timePos: 20.0));

      expect(engine.health, PlaybackHealth.playing);
      expect(engine.session, 8);

      await pumpEventQueue();

      expect(seen, <int>[7, 7, 8]);

      await subscription.cancel();
    });

    test('a new session resets the freeze anchor', () async {
      final FakePlaybackEngine engine = await _loaded();

      engine.emit(_tick(session: 7, atSeconds: 0, timePos: 10.0));
      engine.emit(_tick(session: 7, atSeconds: 1, timePos: 10.0, underrun: true));

      expect(engine.health, PlaybackHealth.starving);

      await engine.load(_source);
      engine.emit(_tick(session: 8, atSeconds: 3, timePos: 20.0));

      // Frozen eleven seconds after the new session's own anchor and fourteen
      // after the old one. Carrying the old anchor across would read this as a
      // stall on a stream that has been running for three seconds.
      engine.emit(_tick(session: 8, atSeconds: 14, timePos: 20.0, underrun: true));

      expect(engine.health, PlaybackHealth.starving);
    });
  });

  group('the ticks stream', () {
    test('is broadcast, so a second reader does not take it from the first', () async {
      final FakePlaybackEngine engine = await _loaded();
      final List<double?> first = <double?>[];
      final List<double?> second = <double?>[];
      final StreamSubscription<PlaybackTick> a = engine.ticks.listen((PlaybackTick t) => first.add(t.timePos));
      final StreamSubscription<PlaybackTick> b = engine.ticks.listen((PlaybackTick t) => second.add(t.timePos));

      engine.emit(_tick(session: 1, atSeconds: 0, timePos: 10.0));
      await pumpEventQueue();

      expect(first, <double>[10.0]);
      expect(second, <double>[10.0]);

      await a.cancel();
      await b.cancel();
    });

    test('closes on dispose', () async {
      final FakePlaybackEngine engine = await _loaded();
      bool closed = false;
      final StreamSubscription<PlaybackTick> subscription = engine.ticks.listen(
        (PlaybackTick tick) {},
        onDone: () => closed = true,
      );

      await engine.dispose();
      await pumpEventQueue();

      expect(closed, isTrue);

      await subscription.cancel();
    });
  });
}
