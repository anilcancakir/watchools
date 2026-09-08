import 'dart:async';

import 'package:flutter/foundation.dart';

/// What time the guide thinks it is.
///
/// The live screen's whole argument is that it moves: a progress bar through
/// the current programme, a countdown to the next one, a now line down the
/// grid. All three read one number, and until this existed that number was a
/// compile-time constant, so nothing moved.
///
/// The unit is minutes since the schedule's midnight, matching [Programme].
/// It is NEVER wrapped: a schedule that runs to 00:30 ends at 1470, and a clock
/// that has passed midnight reports 1445 rather than 5. Wrapping would be the
/// obvious thing and it breaks three places at once. `Programme.contains` would
/// answer false for every block spanning midnight, `windowStart` would go
/// negative and drag the time axis with it, and `Programme.startLabel` already
/// takes the hour modulo 24 (`programme.dart:70`), so 1500 renders as `01:00`
/// on its own and needs no help.
abstract class GuideClock extends ChangeNotifier {
  /// Minutes since the schedule's midnight, monotonic and never wrapped.
  int get minute;
}

/// A clock that does not move.
///
/// The default, and it stays the default until a real EPG arrives. The fixtures
/// are one evening, so a wall clock would show an empty guide for the nineteen
/// hours a day that evening is not on, and every screenshot and every dusk walk
/// would depend on the hour it ran at.
///
/// It is a [ChangeNotifier] that never notifies, which is what lets the
/// controller subscribe to whatever clock it is handed without asking which
/// kind it is.
class FixedGuideClock extends GuideClock {
  @override
  final int minute;

  /// Creates a clock stopped at [minute], 20:12 by default.
  ///
  /// The default is the hour the fixtures are written around: mid-programme on
  /// most channels, close enough to the half hour that the "starts shortly"
  /// rail has something in it, and inside the 19:30 to 00:30 window the grid
  /// draws.
  FixedGuideClock([this.minute = 20 * 60 + 12]);
}

/// A clock that starts at an anchor and advances with real time.
///
/// Anchored rather than absolute, because the fixtures are one evening. Reading
/// the wall clock directly would show 14:30 on a schedule that starts at 19:30
/// and the screen would be correctly, uselessly empty. Anchoring keeps the
/// fixture's evening and makes it move, which is the property the design
/// argument actually needs. When a provider's real schedule arrives the anchor
/// becomes the wall clock and nothing else here changes.
///
/// The tick is aligned to the minute boundary rather than fired every sixty
/// seconds from whenever it started. Nothing on screen resolves below a minute:
/// the grid draws six pixels per minute, so a per-second tick would move the
/// now line by a tenth of a pixel, and the countdown is written in minutes. An
/// aligned tick also means the countdown changes when the minute changes rather
/// than up to fifty nine seconds later.
class TickingGuideClock extends GuideClock {
  /// The minute this clock reported when it started.
  final int anchor;

  /// Where real time comes from.
  ///
  /// Injectable because a [Stopwatch] and a bare `DateTime.now()` both read the
  /// hardware clock, which `fakeAsync` does not virtualise: it drives timers and
  /// leaves wall time alone, so a test that elapses five virtual minutes gets
  /// five notifications from a clock still reporting its anchor. A function is
  /// the smallest seam that fixes that and costs no dependency.
  final DateTime Function() _now;

  late final DateTime _startedAt;
  Timer? _timer;

  /// Creates a clock that reports [anchor] now and one more minute each minute.
  TickingGuideClock({this.anchor = 20 * 60 + 12, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _startedAt = _now();
    _scheduleNext();
  }

  @override
  int get minute => anchor + _elapsed.inMinutes;

  /// How long this clock has been running.
  ///
  /// Read from the time source rather than accumulated per tick, so a device
  /// that suspended its timers overnight comes back with the right minute
  /// instead of the one it went to sleep on.
  Duration get _elapsed => _now().difference(_startedAt);

  /// Fires on the next whole minute, then re-arms.
  ///
  /// A repeating one-minute [Timer.periodic] would drift: each callback is
  /// scheduled from the last one's completion, so a slow frame pushes every
  /// later tick. Re-arming against the elapsed remainder pins each tick to the
  /// boundary it belongs to.
  void _scheduleNext() {
    final Duration remainder = Duration(microseconds: _elapsed.inMicroseconds % Duration.microsecondsPerMinute);

    _timer = Timer(const Duration(minutes: 1) - remainder, () {
      notifyListeners();
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
