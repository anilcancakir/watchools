import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:magic/magic.dart' show MagicController;
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/ui/layouts/now_layout.dart';
import 'package:watchools/ui/layouts/showcase_layout.dart';
import 'package:watchools/ui/layouts/support/guide_empty.dart';
import 'package:watchools/ui/layouts/support/library_empty.dart';
import 'package:watchools/ui/layouts/time_layout.dart';

import '../../support/screen.dart';

/// Can you keep typing after a query stops matching anything?
///
/// Reported from a browser and reproduced there first: typing `z`, `q`, `x`,
/// `v` into `Şimdi` left the field holding `zq`, because `q` emptied the
/// line-up and every keystroke after it went nowhere. The same four keys in
/// `Zaman` produced `zqxv`.
///
/// The difference was structural. `Şimdi` and `Vitrin` put the search field in
/// one parent when the list had results and a different one when it did not, so
/// the keystroke that emptied the list rebuilt that position and took the
/// input's state with it. `Zaman` already kept its toolbar outside the branch,
/// which is why it was never affected and why it is the control below.
///
/// What each case asserts is the SAME `FocusNode` instance before and after,
/// not merely that something on screen holds focus. A rebuilt field would get a
/// fresh node, and a fresh node that happened to be focused would pass a
/// weaker assertion while the bug was still there. Identity is the property the
/// fix actually provides.
///
/// Every case also asserts that the empty state is on screen, and that line is
/// load-bearing rather than belt and braces. The first version of this file
/// pumped the layout bare, and a bare layout listens to nothing: `search()`
/// notified a controller with no subscriber, no frame rebuilt anything, and all
/// four cases passed while measuring nothing at all. `_listening` is what makes
/// the tree react the way the shipped `MagicStatefulView` does, and the
/// `GuideEmpty` assertion is what proves it did.
void main() {
  setUp(WindParser.clearCache);

  /// Rebuilds [child] whenever [controller] notifies, which is what
  /// `MagicStatefulViewState` does in the running app and what `pumpScreen`
  /// alone does not do.
  Widget listening(MagicController controller, Widget Function() child) {
    return ListenableBuilder(listenable: controller, builder: (BuildContext context, Widget? _) => child());
  }

  /// The focus node the one text field on screen is really using.
  ///
  /// Read off `EditableText` rather than `WInput.focusNode`, which is null
  /// unless a caller passed one in and would make this find nothing.
  FocusNode inputNode(WidgetTester tester) {
    return tester.widget<EditableText>(find.byType(EditableText)).focusNode;
  }

  /// A term no fixture channel or title can match.
  const String nonsense = 'zqxv';

  testWidgets('Şimdi survives the query that empties the line-up', (tester) async {
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)));

    final FocusNode before = inputNode(tester);
    before.requestFocus();
    await tester.pump();
    expect(before.hasFocus, isTrue, reason: 'the field took focus');

    controller.search(nonsense);
    await tester.pump();

    expect(find.byType(GuideEmpty), findsOneWidget, reason: 'the branch actually swapped');
    expect(identical(inputNode(tester), before), isTrue);
    expect(before.hasFocus, isTrue);
  });

  testWidgets('and survives the way back to results', (tester) async {
    // The reverse crossing. A viewer who over-typed and starts deleting hits
    // the branch a second time, and losing the field there is the half that
    // makes it feel broken rather than merely dead.
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)));

    controller.search(nonsense);
    await tester.pump();
    expect(find.byType(GuideEmpty), findsOneWidget);

    final FocusNode before = inputNode(tester);
    before.requestFocus();
    await tester.pump();

    controller.search('');
    await tester.pump();

    expect(find.byType(GuideEmpty), findsNothing, reason: 'the branch swapped back');
    expect(identical(inputNode(tester), before), isTrue);
    expect(before.hasFocus, isTrue);
  });

  testWidgets('Vitrin survives it too', (tester) async {
    final LibraryController controller = LibraryController();
    await pumpScreen(tester, listening(controller, () => ShowcaseLayout(controller: controller)));

    final FocusNode before = inputNode(tester);
    before.requestFocus();
    await tester.pump();

    controller.search(nonsense);
    await tester.pump();

    expect(find.byType(LibraryEmpty), findsOneWidget, reason: 'the branch actually swapped');
    expect(identical(inputNode(tester), before), isTrue);
    expect(before.hasFocus, isTrue);
  });

  testWidgets('Zaman, the control, was never affected', (tester) async {
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => TimeLayout(controller: controller)));

    final FocusNode before = inputNode(tester);
    before.requestFocus();
    await tester.pump();

    controller.search(nonsense);
    await tester.pump();

    expect(find.byType(GuideEmpty), findsOneWidget, reason: 'the branch actually swapped');
    expect(identical(inputNode(tester), before), isTrue);
    expect(before.hasFocus, isTrue);
  });
}
