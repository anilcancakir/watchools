import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/programme.dart';

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

      final Programme? now = first.programmeAt(GuideController.now);
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
      expect(controller.programme, controller.channels.first.programmeAt(GuideController.now));
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
      final Channel target = controller.channel;
      controller.toggleFavourite(target);

      expect(controller.channel.favourite, isTrue);
      expect(controller.channel.name, target.name);
      expect(controller.channel, isNot(same(target)), reason: 'Channel is immutable, so this is a new object');
    });

    test('starring twice returns to unstarred', () {
      final Channel target = controller.channels.first;
      controller.toggleFavourite(target);
      controller.toggleFavourite(controller.channels.first);

      expect(controller.channels.first.favourite, isFalse);
    });
  });

  group('the bake-off state', () {
    test('layout and mode switch and hold', () {
      expect(controller.layout, BrowseLayout.signal);
      controller.showLayout(BrowseLayout.mosaic);
      expect(controller.layout, BrowseLayout.mosaic);

      expect(controller.mode, GuideMode.guide);
      controller.showMode(GuideMode.list);
      expect(controller.mode, GuideMode.list);
    });

    test('switching layout keeps the filters, which is the whole point', () {
      controller.selectGroup('Spor');
      controller.search('e');
      final int matched = controller.matches.length;

      controller.showLayout(BrowseLayout.stage);

      expect(controller.group, 'Spor');
      expect(controller.query, 'e');
      expect(controller.matches.length, matched);
    });
  });

  group('the window the guide draws', () {
    test('starts on the half hour before now', () {
      expect(GuideController.windowStart, lessThan(GuideController.now));
      expect(GuideController.now - GuideController.windowStart, lessThan(60));
      expect(GuideController.windowStart % 30, 0);
    });

    test('is wide enough to hold the fixture evening', () {
      expect(GuideController.windowMinutes, 210);
      expect(GuideController.windowStart + GuideController.windowMinutes, greaterThan(GuideController.now));
    });
  });
}
