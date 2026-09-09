import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/programme.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/provider/provider_session.dart';
import 'package:watchools/app/support/guide_clock.dart';
import 'package:watchools/app/support/guide_fixture.dart';

/// The line-up controller, which holds every claim the end-to-end walk can only
/// assert through a semantics tree.
///
/// Worth unit testing rather than leaving to the walk: the walk needs a running
/// app, twelve seconds a case and a browser that occasionally dies, and it can
/// only see what a layout chose to render. These run in milliseconds and see
/// the answer itself.
void main() {
  late GuideController controller;

  setUp(() => controller = GuideController());

  group('filtering', () {
    test('starts on the whole line-up', () {
      expect(controller.group, 'Tümü');
      expect(controller.query, '');
      expect(controller.matches.length, controller.channels.length);
    });

    test('a category narrows to that category and Tümü widens again', () {
      controller.selectGroup('Spor');
      expect(controller.matches.every((Channel c) => c.group == 'Spor'), isTrue);
      expect(controller.matches.length, lessThan(controller.channels.length));

      controller.selectGroup('Tümü');
      expect(controller.matches.length, controller.channels.length);
    });

    test('Favoriler shows only starred channels', () {
      controller.selectGroup('Favoriler');
      expect(controller.matches, isEmpty);

      controller.toggleFavourite(controller.channels.first);
      expect(controller.matches.length, 1);
      expect(controller.matches.first.favourite, isTrue);
    });

    test('search covers the name, the number and the programme on now', () {
      final Channel first = controller.channels.first;

      controller.search(first.name);
      expect(controller.matches, contains(first));

      controller.search(first.numberLabel);
      expect(controller.matches, contains(first));

      final Programme? now = first.programmeAt(controller.now);
      expect(now, isNotNull, reason: 'the fixture leads with a channel that is on air');
      controller.search(now!.title);
      expect(controller.matches, contains(first));
    });

    test('search is case and whitespace insensitive', () {
      controller.search('  SPOR  ');
      final int loud = controller.matches.length;
      controller.search('spor');

      expect(controller.matches.length, loud);
      expect(loud, greaterThan(0));
    });

    test('a category and a query compose rather than replace', () {
      controller.selectGroup('Spor');
      final int inSpor = controller.matches.length;
      controller.search('zzzzzz');

      expect(controller.matches, isEmpty);
      expect(inSpor, greaterThan(0));
    });
  });

  group('the frame caches', () {
    test('hand back the same list until something changes', () {
      expect(controller.matches, same(controller.matches));
      expect(controller.sections, same(controller.sections));
    });

    test('are dropped by every mutation that changes what is visible', () {
      final List<Channel> before = controller.matches;

      controller.search('spor');
      expect(controller.matches, isNot(same(before)));

      final List<Channel> filtered = controller.matches;
      controller.selectGroup('Haber');
      expect(controller.matches, isNot(same(filtered)));

      final List<Channel> byGroup = controller.matches;
      controller.toggleFavourite(controller.channels.first);
      expect(controller.matches, isNot(same(byGroup)));
    });
  });

  group('sections', () {
    test('follow the provider order rather than the alphabet', () {
      final List<String> names = controller.sections.map(((String, List<Channel>) s) => s.$1).toList();
      final List<String> sorted = List<String>.of(names)..sort();

      expect(names, isNot(sorted), reason: 'the fixture is deliberately not in alphabetical order');
      expect(names.first, controller.channels.first.group);
    });

    test('cover every match exactly once', () {
      final int counted = controller.sections.fold(0, (int n, (String, List<Channel>) s) => n + s.$2.length);

      expect(counted, controller.matches.length);
    });
  });

  group('the counts every layout renders', () {
    test('countLabel says kanal without a query and sonuç with one', () {
      expect(controller.countLabel, endsWith('kanal'));

      controller.search('spor');
      expect(controller.countLabel, endsWith('sonuç'));

      // Whitespace is not a query. Two of the four layouts used to disagree
      // about this, which is why it lives on the controller.
      controller.search('   ');
      expect(controller.countLabel, endsWith('kanal'));
    });

    test('noGuideNote counts the matches with no schedule and hides at zero', () {
      expect(controller.withoutSchedule, greaterThan(0));
      expect(controller.noGuideNote, contains('${controller.withoutSchedule}'));

      // A group whose every channel carries a schedule has nothing to say.
      controller.selectGroup('Ulusal');
      expect(controller.withoutSchedule, 0);
      expect(controller.noGuideNote, isNull);
    });

    test('scheduled is the subset the time axis can draw', () {
      expect(controller.scheduled.every((Channel c) => c.hasSchedule), isTrue);
      expect(controller.scheduled.length + controller.withoutSchedule, controller.matches.length);
    });
  });

  group('selection', () {
    test('starts on the first channel and its current programme', () {
      expect(controller.channel, controller.channels.first);
      expect(controller.programme, controller.channels.first.programmeAt(controller.now));
    });

    test('selecting a channel points the programme at what is on now', () {
      final Channel target = controller.channels.firstWhere((Channel c) => !c.hasSchedule);
      controller.selectChannel(target);

      expect(controller.channel, target);
      expect(controller.programme, isNull, reason: 'a channel with no EPG has nothing on now');
    });

    test('selecting a programme keeps both, which the time axis needs', () {
      final Channel target = controller.channels.firstWhere((Channel c) => c.hasSchedule);
      final Programme last = target.schedule.last;
      controller.selectProgramme(target, last);

      expect(controller.channel, target);
      expect(controller.programme, same(last));
    });

    test('starring the selected channel keeps the selection on the new instance', () {
      final Channel target = controller.channel!;
      controller.toggleFavourite(target);

      expect(controller.channel!.favourite, isTrue);
      expect(controller.channel!.name, target.name);
      expect(controller.channel, isNot(same(target)), reason: 'Channel is immutable, so this is a new object');
    });

    test('starring twice returns to unstarred', () {
      final Channel target = controller.channels.first;
      controller.toggleFavourite(target);
      controller.toggleFavourite(controller.channels.first);

      expect(controller.channels.first.favourite, isFalse);
    });
  });

  group('the view switch', () {
    test('arrives on Şimdi and holds a switch to Zaman', () {
      expect(controller.mode, GuideMode.now);

      controller.showMode(GuideMode.grid);
      expect(controller.mode, GuideMode.grid);
    });

    test('switching view keeps the filters, which is why both read one controller', () {
      controller.selectGroup('Spor');
      controller.search('e');
      final int matched = controller.matches.length;

      controller.showMode(GuideMode.grid);

      expect(controller.group, 'Spor');
      expect(controller.query, 'e');
      expect(controller.matches.length, matched);
    });

    test('switching view keeps the selected channel and its programme', () {
      final Channel target = controller.channels.firstWhere((Channel c) => c.hasSchedule);
      controller.selectChannel(target);
      final Programme? live = controller.programme;

      controller.showMode(GuideMode.grid);

      expect(controller.channel, same(target));
      expect(controller.programme, same(live));
    });
  });

  group('the editorial rails', () {
    test('the two live rails answer questions only a schedule can', () {
      final List<String> titles = controller.rails.map((GuideRail r) => r.title).toList();

      expect(titles, contains('Daha yeni başladı'));
      expect(titles, contains('Birazdan başlıyor'));
    });

    test('the soon rail is named for the horizon it actually uses', () {
      // The rail was called `Yarım saat içinde` while the horizon was 45
      // minutes, so at 20:12 its first card was a 20:55 programme and the title
      // contradicted its own contents.
      final GuideRail soon = controller.rails.firstWhere((GuideRail r) => r.title == 'Birazdan başlıyor');

      final int furthest = soon.channels
          .map((Channel c) => c.nextAfter(controller.now)!.startMinute - controller.now)
          .reduce((int a, int b) => a > b ? a : b);

      expect(furthest, greaterThan(30), reason: 'otherwise the old half-hour name was accurate');
    });

    test('a channel with no guide appears in exactly one rail', () {
      final Channel blindChannel = controller.channels.firstWhere((Channel c) => !c.hasSchedule);
      final List<GuideRail> carrying = controller.rails
          .where((GuideRail r) => r.channels.contains(blindChannel))
          .toList();

      expect(carrying.map((GuideRail r) => r.title), <String>['Akış bilgisi olmayan kanallar']);

      // No exemption for the provider-group rails. They used to be built over
      // every match, so each no-EPG channel appeared twice on one screen: once
      // in its group and once in the rail that exists to name it. The old
      // version of this test exempted exactly the rails that were wrong.
      for (final GuideRail rail in controller.rails) {
        if (rail.title == 'Akış bilgisi olmayan kanallar') continue;

        expect(rail.channels.every((Channel c) => c.hasSchedule), isTrue, reason: rail.title);
      }
    });

    test('an empty rail is dropped rather than rendered', () {
      // Nothing is starred on first run, so the favourites rail must be absent
      // rather than present and empty. An empty ROW is a claim about the
      // schedule that is not true; an empty SLOT inside a row is a hole and is
      // designed instead.
      expect(controller.rails.any((GuideRail r) => r.title == 'Favorilerin'), isFalse);

      controller.toggleFavourite(controller.channels.first);

      expect(controller.rails.any((GuideRail r) => r.title == 'Favorilerin'), isTrue);
    });

    test('a starred channel with no guide still reaches the favourites rail', () {
      // The one list a viewer curates by hand, and it used to drop exactly the
      // channels they are most likely to have curated: the star was collected
      // BELOW the no-schedule branch, so a music or a regional channel with no
      // EPG could be starred and never appear. Starring a channel that HAS a
      // schedule could not catch it, which is what the previous test did.
      final Channel blindChannel = controller.channels.firstWhere((Channel c) => !c.hasSchedule);
      controller.toggleFavourite(blindChannel);

      final GuideRail starred = controller.rails.firstWhere((GuideRail r) => r.title == 'Favorilerin');

      expect(starred.channels.map((Channel c) => c.name), contains(blindChannel.name));
    });

    test('the rails follow the filter', () {
      controller.selectGroup('Spor');

      for (final GuideRail rail in controller.rails) {
        expect(rail.channels.every((Channel c) => c.group == 'Spor'), isTrue, reason: rail.title);
      }
    });

    test('the cache is dropped when the filter moves', () {
      final int before = controller.rails.length;
      controller.search('zzzzz');

      expect(controller.rails.length, isNot(before));
      expect(controller.rails, isEmpty);
    });
  });

  group('the clock', () {
    /// A clock the test moves by hand, standing in for the ticking one.
    ///
    /// The real [TickingGuideClock] is tested against virtual time in
    /// `guide_clock_test.dart`. What matters here is only what the controller
    /// does when a clock says the minute changed, so a notifier the test drives
    /// directly is the shorter route to it.
    late _StubClock clock;

    setUp(() {
      clock = _StubClock(20 * 60 + 12);
      controller = GuideController(clock: clock);
    });

    test('defaults to a clock that does not move', () {
      expect(GuideController().clock, isA<FixedGuideClock>());
    });

    test('the window follows the clock rather than a written constant', () {
      expect(controller.windowStart, 19 * 60 + 30);

      clock.set(22 * 60 + 5);

      expect(controller.windowStart, 21 * 60 + 30);
      expect(controller.now - controller.windowStart, lessThan(60));
    });

    test('a tick repaints', () {
      int notifications = 0;
      controller.addListener(() => notifications++);

      clock.set(20 * 60 + 13);

      expect(notifications, 1);
    });

    test('a tick drops the rails, which are built from now', () {
      final List<GuideRail> before = controller.rails;
      expect(identical(controller.rails, before), isTrue, reason: 'the cache holds while nothing moves');

      clock.set(20 * 60 + 13);

      expect(identical(controller.rails, before), isFalse);
    });

    test('a tick moves the selection onto whatever is on now', () {
      // The billboard's subject is the programme, not the channel, so a channel
      // that rolls into its next programme has to bring the hero with it. Before
      // the clock existed the selection was written once and could not go stale.
      final Channel channel = controller.channels.firstWhere((Channel c) => c.schedule.length > 1);
      controller.selectChannel(channel);

      final Programme first = channel.programmeAt(controller.now)!;
      clock.set(first.endMinute);

      expect(controller.programme, isNot(first));
      expect(controller.programme, channel.programmeAt(first.endMinute));
    });

    test('a clock it was handed is not its to dispose', () {
      // A test drives one stub across several controllers, so disposing an
      // injected clock on the first `onClose` would break the second.
      controller.onClose();

      clock.set(20 * 60 + 20);

      expect(clock.minute, 20 * 60 + 20, reason: 'the stub still works');
    });

    test('a clock it built itself is disposed with it', () {
      final GuideController owner = GuideController();
      final GuideClock own = owner.clock;

      owner.onClose();

      // The observable consequence of `dispose`: a disposed `ChangeNotifier`
      // throws on `addListener`. Latent while the default holds no resource,
      // and the difference between a cancelled and a leaked timer the day the
      // default becomes `TickingGuideClock`.
      expect(() => own.addListener(() {}), throwsFlutterError);
    });

    test('it stops listening when the controller closes', () {
      // Asserted on the CLOCK's listener count rather than on whether the
      // controller notified. `MagicController.onClose` sets `_disposed`, and
      // `refreshUI` returns early on it, so deleting the `removeListener` line
      // from `onClose` leaves a version of this test that watches for
      // notifications entirely green while the listener leaks.
      expect(clock.listeners, 1);

      controller.onClose();

      expect(clock.listeners, 0);
    });
  });

  group('the window the guide draws', () {
    test('starts on the half hour before now', () {
      expect(controller.windowStart, lessThan(controller.now));
      expect(controller.now - controller.windowStart, lessThan(60));
      expect(controller.windowStart % 30, 0);
    });

    test('covers prime time end to end rather than fitting a viewport', () {
      // Five hours, 19:30 to 00:30. It was three and a half while the axis had
      // to fit a laptop without scrolling; the grid scrolls now, so the window
      // is a question about the evening rather than about the screen.
      expect(GuideController.windowMinutes, 300);
      expect(controller.windowStart + GuideController.windowMinutes, greaterThan(controller.now));

      // The last programme in the fixture has to fall inside it, or the grid
      // draws a window with an empty right half and nothing says why.
      final int lastEnd = guideFixture
          .expand((Channel c) => c.schedule)
          .map((Programme p) => p.endMinute)
          .reduce((int a, int b) => a > b ? a : b);

      expect(controller.windowStart + GuideController.windowMinutes, greaterThanOrEqualTo(lastEnd));
    });
  });

  group('the provider session', () {
    test('a session with no credentials still yields the fixture line-up', () {
      // This is the perf harness's own path: `tool/dusk/perf.sh` starts the
      // app with no `Vault` entry, so `hasCredentials` is false and the
      // compile-time `WATCHOOLS_SCALE` fixture must still be what renders.
      final GuideController fromSession = GuideController(session: ProviderSession());

      expect(fromSession.channels.length, guideFixture.length);
      expect(fromSession.channels.first.name, guideFixture.first.name);
    });

    test('an empty provider catalogue does not throw', () {
      final GuideController empty = GuideController(session: _FakeProviderSession(channels: const <Channel>[]));

      // Mutation check: reverting `channel`/`programme` to the old
      // `late ... = channels.first` shape makes this throw a `StateError`
      // instead of returning null.
      expect(() => empty.channel, returnsNormally);
      expect(empty.channel, isNull);
      expect(empty.programme, isNull);
      expect(empty.matches, isEmpty);
    });

    test('provider channels reach matches and groups', () {
      final List<Channel> twoChannels = <Channel>[
        const Channel(number: 1, name: 'Anadolu Spor', group: 'Spor', status: ChannelStatus.idle, streamId: 10),
        const Channel(number: 2, name: 'Anadolu Haber', group: 'Haber', status: ChannelStatus.idle, streamId: 11),
      ];
      final GuideController fromSession = GuideController(session: _FakeProviderSession(channels: twoChannels));

      expect(fromSession.matches.length, 2);
      expect(fromSession.groups, containsAll(<String>['Spor', 'Haber']));
    });

    test('a fault on the session surfaces without emptying matches', () {
      final List<Channel> oneChannel = <Channel>[
        const Channel(number: 1, name: 'Anadolu Spor', group: 'Spor', status: ChannelStatus.idle, streamId: 10),
      ];
      final GuideController fromSession = GuideController(
        session: _FakeProviderSession(channels: oneChannel, fault: ProviderFault.throttled),
      );

      expect(fromSession.fault, ProviderFault.throttled);
      expect(fromSession.matches, isNotEmpty);
    });

    test('starring on the provider path routes through the session', () {
      const Channel channel = Channel(
        number: 1,
        name: 'Anadolu Spor',
        group: 'Spor',
        status: ChannelStatus.idle,
        streamId: 10,
      );
      final _FakeProviderSession session = _FakeProviderSession(channels: <Channel>[channel]);
      final GuideController fromSession = GuideController(session: session);

      fromSession.toggleFavourite(channel);

      expect(session.favouriteCalls, <({int streamId, bool favourite})>[(streamId: 10, favourite: true)]);
    });

    test('now reads the session clock once a refresh has anchored one', () {
      final GuideController fromSession = GuideController(
        session: _FakeProviderSession(channels: const <Channel>[], clock: FixedGuideClock(9 * 60)),
      );

      expect(fromSession.now, 9 * 60);
    });

    test('the tick subscription moves onto the session clock, so a minute change repaints', () {
      // Reading the right minute is not the same as being told when it
      // changes. Without the move, `now` would report a live value that
      // nothing repainted, and the progress bars, the countdown and the
      // grid's now line would sit at whatever minute the last unrelated
      // rebuild happened to catch.
      final _StubClock sessionClock = _StubClock(9 * 60);
      final _StubClock fixtureClock = _StubClock(20 * 60 + 12);
      final GuideController controller = GuideController(
        clock: fixtureClock,
        session: _FakeProviderSession(
          channels: const <Channel>[
            Channel(number: 1, name: 'Anadolu Spor', group: 'Spor', status: ChannelStatus.idle, streamId: 10),
          ],
          clock: sessionClock,
        ),
      );

      // Reading the line-up is what observes the session, which is where the
      // subscription moves.
      expect(controller.channels, hasLength(1));
      expect(sessionClock.listeners, 1);
      expect(fixtureClock.listeners, 0, reason: 'the subscription moved rather than doubling up');

      int repaints = 0;
      controller.addListener(() => repaints++);
      sessionClock.set(9 * 60 + 1);

      expect(repaints, 1);
      expect(controller.now, 9 * 60 + 1);
    });
  });
}

/// A clock the test sets by hand.
class _StubClock extends GuideClock {
  int _minute;

  _StubClock(this._minute);

  /// How many listeners are attached.
  ///
  /// Counted here because `ChangeNotifier.hasListeners` is `@protected` and
  /// only legal inside a subclass instance member, and a test asserting that
  /// the controller detached has to see the count from outside.
  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  int get minute => _minute;

  void set(int value) {
    _minute = value;
    notifyListeners();
  }
}

/// A session double that reports whatever the test built it with, so the
/// provider path is exercised without a network, a `Vault` entry or SQLite.
class _FakeProviderSession extends ProviderSession {
  _FakeProviderSession({required this.channels, this.fault, this.clock});

  @override
  final List<Channel> channels;

  @override
  bool get hasCredentials => true;

  @override
  final ProviderFault? fault;

  @override
  final GuideClock? clock;

  /// Every call [GuideController.toggleFavourite] made, in order.
  final List<({int streamId, bool favourite})> favouriteCalls = <({int streamId, bool favourite})>[];

  @override
  void setChannelFavourite({required int streamId, required bool favourite}) {
    favouriteCalls.add((streamId: streamId, favourite: favourite));
  }
}
