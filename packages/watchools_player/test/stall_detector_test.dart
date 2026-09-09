import 'package:flutter_test/flutter_test.dart';
import 'package:watchools_player/watchools_player.dart';

/// Every case here is a measured shape rather than an invented one. The table
/// they come from is in `.ac/research/player-layer.md`, "Three ways a playback
/// clock freezes", and the numbers are from the mock panel and the real
/// provider.
void main() {
  /// Builds a tick at `atSeconds` on mpv's monotonic clock.
  ///
  /// `underrun` and `demuxerIdle` are nullable on purpose: they sit under mpv's
  /// "might be changed or removed" heading, so a build without them reports
  /// null, and null must never read as healthy.
  PlayerTick tickAt(
    double atSeconds, {
    required double? position,
    bool paused = false,
    bool? underrun,
    bool? demuxerIdle,
    int session = 1,
    int? forwardBytes,
  }) {
    return PlayerTick(
      session: session,
      monotonicNs: (atSeconds * 1000000000).round(),
      timePos: position,
      paused: paused,
      coreIdle: false,
      forwardBytes: forwardBytes,
      inputRate: null,
      underrun: underrun,
      demuxerIdle: demuxerIdle,
    );
  }

  test('an advancing position is playing', () {
    final StallDetector detector = StallDetector();

    expect(detector.read(tickAt(0, position: 0.1)), PlaybackHealth.playing);
    expect(detector.read(tickAt(0.5, position: 0.6)), PlaybackHealth.playing);
    expect(detector.read(tickAt(1.0, position: 1.1)), PlaybackHealth.playing);
    expect(detector.frozenFor, Duration.zero);
  });

  test(
    'a frozen position with a full buffer is not presenting, never a stall',
    () {
      // The measured idle-display shape: 106 consecutive ticks at time-pos 0.08
      // with the buffer climbing to 11.7 MB, `underrun` false and `demuxerIdle`
      // true. No variant switch fixes an asleep display, so this must not
      // accumulate no matter how long it lasts.
      final StallDetector detector = StallDetector();
      detector.read(tickAt(0, position: 0.08));

      for (int i = 1; i <= 120; i += 1) {
        final PlaybackHealth health = detector.read(
          tickAt(
            i * 0.5,
            position: 0.08,
            underrun: false,
            demuxerIdle: true,
            forwardBytes: 2600000 + i * 100000,
          ),
        );
        expect(health, PlaybackHealth.notPresenting, reason: 'tick $i');
      }

      expect(detector.frozenFor, Duration.zero);
    },
  );

  test('a legitimate live starvation stays under the grace and recovers', () {
    // The measured healthy shape against a three segment window: about eight
    // seconds of `underrun` true with `fw-bytes` 0, then playback continues
    // from where it stopped. A three second threshold would switch variants
    // here, which is why the default grace is twelve.
    final StallDetector detector = StallDetector();
    detector.read(tickAt(0, position: 15.5));

    for (double t = 0.5; t <= 8.0; t += 0.5) {
      expect(
        detector.read(
          tickAt(
            t,
            position: 15.5,
            underrun: true,
            demuxerIdle: false,
            forwardBytes: 0,
          ),
        ),
        PlaybackHealth.starving,
        reason: 'at $t s',
      );
    }
    expect(detector.frozenFor, const Duration(seconds: 8));

    // The window advances and the client catches up.
    expect(
      detector.read(
        tickAt(8.5, position: 16.3, underrun: false, demuxerIdle: false),
      ),
      PlaybackHealth.playing,
    );
    expect(detector.frozenFor, Duration.zero);
  });

  test('a freeze past the grace is a stall', () {
    final StallDetector detector = StallDetector();
    detector.read(tickAt(0, position: 15.5));

    PlaybackHealth health = PlaybackHealth.idle;
    for (double t = 0.5; t <= 12.0; t += 0.5) {
      health = detector.read(
        tickAt(
          t,
          position: 15.5,
          underrun: true,
          demuxerIdle: false,
          forwardBytes: 0,
        ),
      );
    }

    expect(health, PlaybackHealth.stalled);
    expect(detector.frozenFor, const Duration(seconds: 12));
  });

  test('an unknown underrun is not treated as healthy', () {
    // Null means the field was absent, which means unknown. Defaulting it to
    // false would route a real stall into `notPresenting` and the ladder would
    // never act.
    final StallDetector detector = StallDetector(
      grace: const Duration(seconds: 3),
    );
    detector.read(tickAt(0, position: 5.0));

    expect(
      detector.read(tickAt(1, position: 5.0, demuxerIdle: true)),
      PlaybackHealth.starving,
    );
    expect(
      detector.read(tickAt(4, position: 5.0, demuxerIdle: true)),
      PlaybackHealth.stalled,
    );
  });

  test('a pause is not a stall, and resuming does not carry the freeze', () {
    final StallDetector detector = StallDetector(
      grace: const Duration(seconds: 3),
    );
    detector.read(tickAt(0, position: 5.0));

    for (double t = 1; t <= 20; t += 1) {
      expect(
        detector.read(tickAt(t, position: 5.0, paused: true)),
        PlaybackHealth.paused,
      );
    }

    // One second, not twenty one: the freeze is measured from the last paused
    // tick, so none of the pause counts toward the grace. It is not zero
    // because the position genuinely has not advanced since the resume, and
    // that second is real.
    expect(
      detector.read(tickAt(21, position: 5.0, underrun: true)),
      PlaybackHealth.starving,
    );
    expect(detector.frozenFor, const Duration(seconds: 1));
  });

  test('a session change resets the freeze', () {
    // What the variant ladder depends on. Without it the new variant inherits
    // the old one's freeze and is condemned on its first tick, which walks the
    // ladder to the bottom on a single fault.
    final StallDetector detector = StallDetector(
      grace: const Duration(seconds: 3),
    );
    detector.read(tickAt(0, position: 15.5));
    detector.read(tickAt(5, position: 15.5, underrun: true));
    expect(detector.health, PlaybackHealth.stalled);

    expect(
      detector.read(tickAt(6, position: 0.1, underrun: true, session: 2)),
      PlaybackHealth.playing,
    );
    expect(detector.frozenFor, Duration.zero);
  });

  test('a session with no position yet is idle rather than stalled', () {
    final StallDetector detector = StallDetector(
      grace: const Duration(seconds: 1),
    );

    expect(detector.read(tickAt(0, position: null)), PlaybackHealth.idle);
    expect(detector.read(tickAt(5, position: null)), PlaybackHealth.idle);
  });
}
