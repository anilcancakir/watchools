import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:fluttersdk_wind/src/theme/defaults/colors.dart' as wind_colors;

import 'support/wind_test_app.dart';

/// Guards the local path dependency on Wind.
///
/// `pub get` succeeding only proves the package resolves. These tests prove it
/// renders and that its parser actually applies a class, which is the failure
/// we would otherwise discover in the middle of design work.
void main() {
  // The parser cache is static and outlives a single test, so a stale entry
  // from an earlier case can make a later one pass for the wrong reason.
  setUp(WindParser.clearCache);

  testWidgets('renders a Wind widget through the local path dependency',
      (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(const WText('watchools', className: 'text-lg font-bold')),
    );

    expect(find.text('watchools'), findsOneWidget);
  });

  testWidgets('resolves a background class to the theme token it names',
      (tester) async {
    const targetKey = ValueKey('wiring-target');

    await tester.pumpWidget(
      wrapWithTheme(
        const WDiv(
          key: targetKey,
          className: 'bg-red-500 p-4',
          child: WText('styled'),
        ),
      ),
    );

    final resolved = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(targetKey),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color)
        .nonNulls;

    // Asserting the exact token, not merely "some colour": a corrupted alias
    // table or a parser resolving `bg-red-100` would satisfy a presence check.
    expect(
      resolved.map((color) => color.toARGB32()),
      contains(wind_colors.colors['red']![500]!.toARGB32()),
      reason: 'bg-red-500 did not resolve to the red-500 token',
    );
  });
}
