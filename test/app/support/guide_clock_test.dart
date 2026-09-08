import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/support/guide_clock.dart';

void main() {
  group('FixedGuideClock', () {
    test('reports the hour the fixtures are written around', () {
      expect(FixedGuideClock().minute, 20 * 60 + 12);
    });

    test('never notifies, so a controller can subscribe without asking', () {
      // The property that lets `GuideController` hold one listener path for
      // both clocks. A fixed clock that could not be listened to would push a
      // null check into every call site.
      final FixedGuideClock clock = FixedGuideClock();
      int notifications = 0;
      clock.addListener(() => notifications++);

      expect(clock.minute, clock.minute);
      expect(notifications, 0);
    });
  });

  group('TickingGuideClock', () {
    /// Builds a clock whose time source IS the fake zone's elapsed time, so
    /// `async.elapse` moves the timers and the reported minute together.
    TickingGuideClock ticking(FakeAsync async, {int anchor = 600}) {
      final DateTime start = DateTime(2026, 9, 8, 10);

      return TickingGuideClock(anchor: anchor, now: () => start.add(async.elapsed));
    }

    test('starts on its anchor', () {
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        addTearDown(clock.dispose);

        expect(clock.minute, 600);
      });
    });

    test('advances one minute per minute', () {
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        addTearDown(clock.dispose);

        async.elapse(const Duration(minutes: 1));
        expect(clock.minute, 601);

        async.elapse(const Duration(minutes: 4));
        expect(clock.minute, 605);
      });
    });

    test('does not move within a minute', () {
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        addTearDown(clock.dispose);

        async.elapse(const Duration(seconds: 59));

        expect(clock.minute, 600);
      });
    });

    test('notifies once per minute rather than once per tick of anything', () {
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        addTearDown(clock.dispose);
        int notifications = 0;
        clock.addListener(() => notifications++);

        async.elapse(const Duration(minutes: 5));

        expect(notifications, 5);
      });
    });

    test('re-arms against elapsed time rather than drifting', () {
      // A `Timer.periodic` schedules each callback from the last one's
      // completion, so a slow frame pushes every later tick and the clock drifts
      // away from the minute boundary it is supposed to sit on. Re-arming
      // against the remainder pins each tick to its own boundary, which this
      // measures by asking for the notification count after an hour: a drifting
      // clock loses one somewhere.
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        addTearDown(clock.dispose);
        int notifications = 0;
        clock.addListener(() => notifications++);

        async.elapse(const Duration(hours: 1));

        expect(notifications, 60);
        expect(clock.minute, 660);
      });
    });

    test('passes midnight without wrapping', () {
      // The decision the whole unit rests on. 23:50 plus twenty minutes is
      // 1450, not 10. Wrapping would make `Programme.contains` answer false for
      // every block spanning midnight and drag `windowStart` negative;
      // `Programme.startLabel` already takes the hour modulo 24, so 1450 renders
      // as `00:10` with no help from here.
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async, anchor: 23 * 60 + 50);
        addTearDown(clock.dispose);

        async.elapse(const Duration(minutes: 20));

        expect(clock.minute, 1450);
      });
    });

    test('stops when disposed', () {
      fakeAsync((FakeAsync async) {
        final TickingGuideClock clock = ticking(async);
        int notifications = 0;
        clock.addListener(() => notifications++);

        async.elapse(const Duration(minutes: 2));
        expect(notifications, 2);

        clock.dispose();
        async.elapse(const Duration(minutes: 5));

        // A live timer after dispose notifies a disposed ChangeNotifier, which
        // throws. The minute itself keeps moving, and that is correct: the
        // clock reads the world rather than accumulating ticks, so a disposed
        // one is simply nobody's business rather than frozen.
        expect(notifications, 2);
      });
    });
  });
}
