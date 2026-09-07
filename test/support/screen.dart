import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/config/watchools_theme.dart';

/// The two widths every screen in this project has to survive, matching the
/// end-to-end walk's own profiles so a failure here and a failure there mean
/// the same thing.
const Size desktop = Size(1440, 900);

/// A phone, the width at which four separate layout bugs were found.
const Size mobile = Size(414, 896);

/// Pumps [child] as a whole screen at [size], in dark mode, on the app's theme,
/// and fails if the tree threw while building or painting.
///
/// Not `wrapWithTheme`: that wrapper is for a leaf widget and leaves the surface
/// at the test default of 800x600, which is neither of the widths this app is
/// designed against and sits on the wrong side of `md` from both. A layout test
/// at 800 wide tests a third layout nobody ships.
///
/// A layout that throws during build or paint records a `FlutterError` without
/// stopping the frame, so a widget test would otherwise pass against a screen
/// with a red box on it. That is the half worth gating, and it is what caught
/// the marquee layout's `LayoutBuilder does not support returning intrinsic
/// dimensions` on an empty result set.
///
/// **Overflow is deliberately ignored, and has to be.** `flutter_test`
/// substitutes a font whose every glyph is a square of the font size: measured,
/// four characters at `fontSize: 14` come out at exactly 56 logical pixels, so
/// text here is roughly one and a half to two times wider than the same string
/// in Schibsted Grotesk. Under those metrics almost every row carrying a label
/// overflows, and none of it says anything about the shipped layout. I chased
/// four such phantoms through the navigation rail before measuring the font.
///
/// Real-font overflow belongs to `tool/dusk/*_e2e.sh`, which drives the actual
/// engine and reads dusk's `overflow: true` annotation. Its own limit is worth
/// knowing too: dusk marks a node only when an INTERACTIVE widget sits inside
/// the overflowing flex, so a row of plain text that overflows is invisible to
/// both gates and only a screenshot will catch it.
///
/// The view is restored by `addTearDown`, so a test cannot leak its width into
/// the next one.
Future<void> pumpScreen(WidgetTester tester, Widget child, {Size size = desktop}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: WindTheme(
        data: buildWatchoolsWindTheme().copyWith(brightness: Brightness.dark, syncWithSystem: false),
        child: Scaffold(body: child),
      ),
    ),
  );

  // A second pump lets the image futures settle. Every remote image in these
  // fixtures fails under `flutter_test`, which answers every request with a
  // 400, and that is exactly the fallback path worth exercising.
  await tester.pump();

  _drainExceptions(size);
}

/// Empties the pending-exception queue, failing on anything that is not an
/// overflow.
///
/// Drained in a loop rather than once, because `takeException` returns one at a
/// time and a single frame can record several; leaving any behind fails the
/// next assertion in the test for something that happened before it.
void _drainExceptions(Size size) {
  final List<Object> real = <Object>[];

  for (
    Object? thrown = TestWidgetsFlutterBinding.instance.takeException();
    thrown != null;
    thrown = TestWidgetsFlutterBinding.instance.takeException()
  ) {
    if (thrown is FlutterError && thrown.message.contains('overflowed by')) continue;
    real.add(thrown);
  }

  if (real.isEmpty) return;

  for (final Object error in real) {
    if (error is FlutterError) {
      for (final DiagnosticsNode node in error.diagnostics) {
        debugPrint(node.toStringDeep());
      }
    }
  }

  fail('threw while building or painting at ${size.width.toInt()}x${size.height.toInt()}: ${real.first}');
}
