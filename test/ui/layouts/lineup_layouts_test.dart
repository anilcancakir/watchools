import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/ui/layouts/marquee_layout.dart';
import 'package:watchools/ui/layouts/mosaic_layout.dart';
import 'package:watchools/ui/layouts/signal_layout.dart';
import 'package:watchools/ui/layouts/stage_layout.dart';

import '../../support/screen.dart';

/// The four competing line-up layouts, at both widths.
///
/// These cover the same ground as `tool/dusk/lineup_e2e.sh` and are not
/// redundant with it. The walk drives the real engine through a browser, which
/// is the only thing that can catch a CanvasKit crash or a semantics label a
/// screen reader would miss; it also needs a running app, twelve seconds a case
/// and a browser that occasionally dies. These run in a second, gate every
/// commit, and catch the class of bug that actually recurred here: a layout
/// that throws or overflows at one of the two widths.
void main() {
  late GuideController controller;

  /// Builds a layout for the current controller state.
  Widget layout(BrowseLayout which) => switch (which) {
    BrowseLayout.signal => SignalLayout(controller: controller),
    BrowseLayout.marquee => MarqueeLayout(controller: controller),
    BrowseLayout.stage => StageLayout(controller: controller),
    BrowseLayout.mosaic => MosaicLayout(controller: controller),
  };

  setUp(() {
    // Wind's parser cache is static and outlives a single test, so without
    // this a test can pass against the previous test's resolution.
    WindParser.clearCache();
    controller = GuideController();
  });

  for (final (String name, Size size) in <(String, Size)>[('desktop', desktop), ('mobile', mobile)]) {
    group('at $name', () {
      for (final BrowseLayout which in BrowseLayout.values) {
        group(which.name, () {
          testWidgets('renders the line-up without an error', (WidgetTester tester) async {
            await pumpScreen(tester, layout(which), size: size);
            expect(find.byType(WDiv), findsWidgets);
          });

          testWidgets('offers a search field', (WidgetTester tester) async {
            await pumpScreen(tester, layout(which), size: size);

            expect(find.byType(WInput), findsAtLeast(1));
          });

          testWidgets('states how much of the line-up has no guide', (WidgetTester tester) async {
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.noGuideNote, isNotNull);
            expect(find.textContaining('akış yok', findRichText: true), findsWidgets);
          });

          testWidgets('survives an empty result set', (WidgetTester tester) async {
            // The case that crashed the marquee layout outright:
            // `SliverFillRemaining(hasScrollBody: false)` asks for an intrinsic
            // height and Wind's `h-full` column path carries a `LayoutBuilder`.
            controller.search('zzzzzz');
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.matches, isEmpty);
            expect(find.text('Sonuç yok'), findsOneWidget);
          });

          testWidgets('survives a favourites-only filter with nothing starred', (WidgetTester tester) async {
            controller.selectGroup('Favoriler');
            await pumpScreen(tester, layout(which), size: size);

            expect(find.text('Henüz favori yok'), findsOneWidget);
          });

          testWidgets('renders a starred line-up', (WidgetTester tester) async {
            for (final int i in <int>[0, 1, 2]) {
              controller.toggleFavourite(controller.channels[i]);
            }
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.matches.where((Channel c) => c.favourite).length, 3);
          });

          testWidgets('renders a single-result search', (WidgetTester tester) async {
            controller.search(controller.channels.first.name);
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.matches, isNotEmpty);
          });
        });
      }
    });
  }

  group('the signal layout specifically', () {
    testWidgets('offers the mode toggle on a desktop and not on a phone', (WidgetTester tester) async {
      // A three hour time axis needs room. Below `md` there is none, so the
      // phone gets the list and no toggle: offering a mode that renders as a
      // wall of clipped blocks is worse than not offering it.
      await pumpScreen(tester, layout(BrowseLayout.signal));
      expect(find.text('Rehber'), findsOneWidget);
      expect(find.text('Liste'), findsOneWidget);

      await pumpScreen(tester, layout(BrowseLayout.signal), size: mobile);
      expect(find.text('Rehber'), findsNothing);
    });

    testWidgets('draws the row list in list mode at both widths', (WidgetTester tester) async {
      controller.showMode(GuideMode.list);

      for (final Size size in <Size>[desktop, mobile]) {
        await pumpScreen(tester, layout(BrowseLayout.signal), size: size);
        expect(find.text(controller.channels.first.name), findsWidgets);
      }
    });
  });

  group('the stage layout specifically', () {
    testWidgets('splits into two panes on a desktop and one on a phone', (WidgetTester tester) async {
      await pumpScreen(tester, layout(BrowseLayout.stage));
      // The jump rail only exists beside a preview pane, and its three-letter
      // section labels are what it is.
      expect(find.text('ULU'), findsOneWidget);

      await pumpScreen(tester, layout(BrowseLayout.stage), size: mobile);
      expect(find.text('ULU'), findsNothing);
    });
  });
}
