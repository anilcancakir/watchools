import 'dart:async';

import 'package:watchools_player/watchools_player.dart';

import 'playback_engine.dart';

/// One call a consumer made, so a test can assert order rather than only state.
///
/// Order is the half that matters: a screen that disposes before it stops
/// leaves the provider connection open, and the measured connection budget on a
/// real subscription is one.
enum FakePlaybackCommand { attach, load, pause, resume, stop, dispose }

/// A [PlaybackEngine] with no platform under it, driven entirely by [emit].
///
/// A deliverable rather than a test helper, and the difference is not
/// bookkeeping: `lib/app/playback/` is inside the coverage denominator, CI
/// builds no native target, and three of the six coming implementations cannot
/// run on this machine at all. So this is the only engine an automated run can
/// exercise, and it is what lets the interface, the health policy and every
/// future consumer of playback be tested.
///
/// It **invents no verdict of its own**. [emit] is the whole input: [health]
/// moves when a tick is read and at no other moment, so [pause] changes nothing
/// until a tick arrives carrying `paused`, exactly as mpv behaves. A fake that
/// flipped its own state on a command would let a consumer's test pass against
/// behaviour no real engine has.
///
/// It feeds a real [StallDetector] rather than answering a verdict directly.
/// Asserting a verdict would test this class and nothing else; feeding the
/// detector exercises the measured policy, which is the 12 s grace, the eight
/// second starvation it has to exceed, and the anchor at the last **advancing**
/// tick. The detector lives for the engine's life rather than per load, for the
/// same reason a real engine's would: the grace is a user-exposed setting, and
/// the detector already resets its own anchor on a session change.
///
/// ### Example
///
/// ```dart
/// final FakePlaybackEngine engine = FakePlaybackEngine();
///
/// await engine.attach(const PlaybackSurface(platformViewId: 0));
/// await engine.load(Uri.parse('http://panel.example/live/u/p/1.ts'));
///
/// // Nine required fields, of which four decide the verdict.
/// engine.emit(PlaybackTick(session: 1, monotonicNs: 0, timePos: 10.0, paused: false, /* ... */));
/// ```
class FakePlaybackEngine implements PlaybackEngine {
  final List<FakePlaybackCommand> _commands = <FakePlaybackCommand>[];

  final StreamController<PlaybackTick> _ticks = StreamController<PlaybackTick>.broadcast();

  final StallDetector _detector = StallDetector();

  PlaybackSurface? _surface;
  Uri? _source;
  String? _userAgent;
  int? _session;

  /// Whether a tick of the **current** load has been read.
  ///
  /// Separate from [_session], which keeps the last stamp seen even across a
  /// load so a straggler can still be recognised. This one is what makes
  /// [health] idle between a load and its first tick: the detector's last
  /// verdict is about the stream that was just replaced.
  bool _reading = false;

  /// What the consumer called, in order.
  List<FakePlaybackCommand> get commands => List<FakePlaybackCommand>.unmodifiable(_commands);

  /// The surface handed over at [attach], or null while none has been.
  PlaybackSurface? get surface => _surface;

  /// The most recent [load]'s arguments, kept after [stop] so a test can assert
  /// what was opened rather than only that something was.
  Uri? get source => _source;
  String? get userAgent => _userAgent;

  @override
  Stream<PlaybackTick> get ticks => _ticks.stream;

  @override
  int? get session => _session;

  @override
  PlaybackHealth get health => _reading ? _detector.health : PlaybackHealth.idle;

  @override
  Future<void> attach(PlaybackSurface surface) {
    _surface = surface;

    return _record(FakePlaybackCommand.attach);
  }

  /// Throws [StateError] when no surface has been attached.
  ///
  /// Loud here rather than trusted, because the real failure is silent: an
  /// engine with no surface opens the stream, advances its counters and reports
  /// health while rendering into nothing. That is a consumer bug this fake
  /// exists to catch, and the only place it can be caught cheaply.
  @override
  Future<void> load(Uri source, {String? userAgent}) {
    if (_surface == null) {
      throw StateError('FakePlaybackEngine: attach a surface before load; an engine without one renders nowhere.');
    }

    _source = source;
    _userAgent = userAgent;
    _reading = false;

    return _record(FakePlaybackCommand.load);
  }

  @override
  Future<void> pause() => _record(FakePlaybackCommand.pause);

  @override
  Future<void> resume() => _record(FakePlaybackCommand.resume);

  @override
  Future<void> stop() {
    _reading = false;

    return _record(FakePlaybackCommand.stop);
  }

  @override
  Future<void> dispose() {
    _commands.add(FakePlaybackCommand.dispose);
    _reading = false;

    return _ticks.close();
  }

  /// Reads one tick as if the platform had delivered it.
  ///
  /// Synchronous on purpose: [health] is settled by the time this returns, so a
  /// scripted sequence needs no event-queue pump between its steps, while the
  /// tick itself reaches [ticks] the way any stream event does.
  ///
  /// A stale tick is dropped rather than reported, so a scripted sequence can
  /// reproduce the one shape that only a real transport produces: the previous
  /// load's last samples arriving after the new load.
  ///
  /// Throws [StateError] after [dispose], because a tick nobody can hear is a
  /// script bug rather than a state to absorb. Named here rather than left to
  /// the stream's own `Cannot add new events after calling close`, which says
  /// nothing about which object or which call ordering produced it.
  void emit(PlaybackTick tick) {
    if (_ticks.isClosed) {
      throw StateError(
        'FakePlaybackEngine: emit after dispose; the tick stream is closed and no consumer can hear it.',
      );
    }

    if (_isStale(tick)) return;

    _session = tick.session;
    _reading = true;
    _detector.read(tick);
    _ticks.add(tick);
  }

  /// Whether [tick] belongs to a load that has already been replaced.
  ///
  /// Two rules rather than one, and the difference is the whole point of the
  /// stamp. While the current load's ticks are being read, a stamp equal to the
  /// last one is the ordinary case and only a lower one is a straggler. Between
  /// a [load] and its first tick, an equal stamp is a straggler too: the load
  /// that carried it is the one just replaced, and that is exactly the moment
  /// the samples in flight arrive.
  bool _isStale(PlaybackTick tick) {
    final int? session = _session;

    if (session == null) return false;

    return _reading ? tick.session < session : tick.session <= session;
  }

  /// Records [command] and answers as a platform round trip that succeeded.
  Future<void> _record(FakePlaybackCommand command) {
    _commands.add(command);

    return Future<void>.value();
  }
}
