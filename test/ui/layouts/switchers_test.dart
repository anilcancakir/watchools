import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/ui/layouts/layout_switcher.dart';
import 'package:watchools/ui/layouts/library_switcher.dart';

import '../../support/screen.dart';

/// The two bake-off switchers.
///
/// Scaffolding, and tested anyway for one reason: they are the only way to
/// reach six of the seven layouts, so a switcher that stops switching makes the
/// whole comparison silently untestable. They go when a direction is chosen.
void main() {
  /// Both switchers are `Positioned`, so they need the `Stack` their own views
  /// give them. Without it the pump throws ParentDataWidget, which is worth
  /// knowing: it is the same mistake the guide view made with a `WDiv` carrying
  /// `relative`, since a multi-child WDiv composes a Column whatever its
  /// position class says.
  Widget inStack(Widget child) => Stack(children: <Widget>[const SizedBox.expand(), child]);

  setUp(WindParser.clearCache);

  group('the line-up switcher', () {
    testWidgets('names all four directions and switches to each', (WidgetTester tester) async {
      final GuideController controller = GuideController();

      for (final Size size in <Size>[desktop, mobile]) {
        for (final (BrowseLayout which, String label) in <(BrowseLayout, String)>[
          (BrowseLayout.marquee, 'Vitrin'),
          (BrowseLayout.stage, 'Sahne'),
          (BrowseLayout.mosaic, 'Mozaik'),
          (BrowseLayout.signal, 'Sinyal'),
        ]) {
          await pumpScreen(tester, inStack(LayoutSwitcher(controller: controller)), size: size);
          await tester.tap(find.text(label));
          await tester.pump();

          expect(controller.layout, which, reason: '$label at ${size.width}');
        }
      }
    });

    testWidgets('each button says what its direction claims', (WidgetTester tester) async {
      final GuideController controller = GuideController();
      await pumpScreen(tester, inStack(LayoutSwitcher(controller: controller)));

      // The claim is in the semantic label rather than on screen, because a
      // pill wide enough to carry it would stop being scaffolding.
      expect(find.bySemanticsLabel('Sinyal: Yoğun liste ve zaman ekseni'), findsOneWidget);
      expect(find.bySemanticsLabel('Mozaik: Kanal amblemi ızgarası'), findsOneWidget);
    });
  });

  group('the catalogue switcher', () {
    testWidgets('names all three directions and switches to each', (WidgetTester tester) async {
      final LibraryController controller = LibraryController();

      for (final Size size in <Size>[desktop, mobile]) {
        for (final (LibraryLayout which, String label) in <(LibraryLayout, String)>[
          (LibraryLayout.ledger, 'Defter'),
          (LibraryLayout.showcase, 'Sergi'),
          (LibraryLayout.wall, 'Duvar'),
        ]) {
          await pumpScreen(tester, inStack(LibrarySwitcher(controller: controller)), size: size);
          await tester.tap(find.text(label));
          await tester.pump();

          expect(controller.layout, which, reason: '$label at ${size.width}');
        }
      }
    });

    testWidgets('switching closes an open detail', (WidgetTester tester) async {
      // The layouts disagree about when the detail is a screen, so a detail
      // opened in one used to follow you into another and hide its browse
      // surface behind a back button.
      final LibraryController controller = LibraryController();
      controller.openDetail(controller.titles.first);

      await pumpScreen(tester, inStack(LibrarySwitcher(controller: controller)));
      await tester.tap(find.text('Defter'));
      await tester.pump();

      expect(controller.detailOpen, isFalse);
    });
  });
}
