import '../watchools_player.dart';

/// What the counters say about a session, once.
///
/// Deliberately not "ok or broken". Three of these are measured shapes that a
/// naive detector collapses into one, and two of the three are not faults:
/// see `.ac/research/player-layer.md`, "Three ways a playback clock freezes".
enum PlaybackHealth {
  /// No session, or none that has produced a position yet.
  idle,

  /// Position advancing.
  playing,

  /// The user paused. Every freeze threshold is gated on this, because a paused
  /// stream stops advancing by design.
  paused,

  /// Frozen with a **full** buffer and the demuxer satisfied.
  ///
  /// Measured: an idle display stops `gpu-next` presenting, because it presents
  /// through the display link, and a TV screensaver reaches the same state. This
  /// is never a provider fault and must never reach the variant ladder, which
  /// is the whole reason this enum has more than two members.
  notPresenting,

  /// Frozen and out of data, within the grace period.
  ///
  /// Legitimate on a live stream: a client that has drained everything the
  /// window advertises waits here. Measured at about eight seconds in every
  /// twenty four against a three segment window.
  starving,

  /// Frozen and out of data for longer than any legitimate starvation.
  ///
  /// The only state the ladder acts on. Indistinguishable from [starving] by
  /// every field the tick carries, which is why the discriminator is time.
  stalled,
}

/// Turns a stream of ticks into a health verdict.
///
/// Owns the policy, and the native side owns none of it, for three reasons: the
/// grace period is a user-exposed setting, the same policy has to hold across
/// six engines, and CI builds no native target so a decision made in Swift would
/// never be exercised by an automated run.
///
/// Time comes from the tick's own `monotonicNs` rather than a wall clock. That
/// makes every test deterministic without injecting a clock, and it means a tick
/// delayed by a blocked platform thread cannot be mistaken for elapsed playback
/// time.
class StallDetector {
  /// How long a freeze may last before it counts as a stall.
  ///
  /// The default has to **exceed the longest legitimate starvation**, and the
  /// measured one is about eight seconds against a three segment live window,
  /// so three seconds (which an earlier version of the spec proposed) would
  /// switch variants on a healthy channel. Twelve is that measurement plus
  /// room, and it is a setting rather than a constant because a provider with a
  /// longer window starves for longer.
  final Duration grace;

  PlaybackHealth _health = PlaybackHealth.idle;
  int? _session;
  double? _lastPosition;

  /// `monotonicNs` of the last tick whose position had advanced.
  ///
  /// The anchor is the last **advancing** tick rather than the first frozen
  /// one, because the position stopped somewhere between the two and only this
  /// end of that interval is known. Anchoring at the first frozen tick made a
  /// single frozen sample read zero however long the gap before it was, which
  /// under-reports by up to one tick interval; this over-reports by the same
  /// amount, and that is the direction that cannot hide a fault.
  int? _advancedAt;

  StallDetector({this.grace = const Duration(seconds: 12)});

  /// The most recent verdict.
  PlaybackHealth get health => _health;

  /// How long the current freeze has lasted, or zero when not frozen.
  Duration get frozenFor => _frozenFor ?? Duration.zero;
  Duration? _frozenFor;

  /// Reads one tick and returns the verdict it produces.
  ///
  /// A session change resets everything: a ladder that reopens during a stall
  /// would otherwise carry the previous variant's freeze into the new one and
  /// step again immediately.
  PlaybackHealth read(PlayerTick tick) {
    if (tick.session != _session) {
      _session = tick.session;
      _lastPosition = null;
      _advancedAt = null;
      _frozenFor = null;
    }

    if (tick.paused) {
      _advancedAt = tick.monotonicNs;
      _frozenFor = null;
      _lastPosition = tick.timePos;
      return _health = PlaybackHealth.paused;
    }

    final double? position = tick.timePos;
    if (position == null) {
      return _health = PlaybackHealth.idle;
    }

    final double? previous = _lastPosition;
    _lastPosition = position;

    // A double compared for exact equality would call a stream advancing by a
    // rounding error healthy, and mpv reports a frozen position as the same
    // value to the bit anyway. A millisecond is well below one frame.
    if (previous == null || position - previous > 0.001) {
      _advancedAt = tick.monotonicNs;
      _frozenFor = null;
      return _health = PlaybackHealth.playing;
    }

    // Frozen with the buffer full and the demuxer satisfied: nothing is being
    // consumed because nothing is presenting. Does not accumulate toward a
    // stall, because no variant switch fixes an asleep display.
    if (tick.underrun == false && tick.demuxerIdle == true) {
      _advancedAt = tick.monotonicNs;
      _frozenFor = null;
      return _health = PlaybackHealth.notPresenting;
    }

    final int since = _advancedAt ??= tick.monotonicNs;
    _frozenFor = Duration(microseconds: (tick.monotonicNs - since) ~/ 1000);

    return _health = _frozenFor! >= grace
        ? PlaybackHealth.stalled
        : PlaybackHealth.starving;
  }
}
