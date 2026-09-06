import 'package:flutter/material.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';

/// Wraps [child] in the widget stack a `className`-styled widget needs before
/// it can resolve anything.
///
/// Without a [WindTheme] ancestor the parser has no colour scale, no spacing
/// unit and no breakpoint table, so every class silently resolves to nothing
/// and the assertion under test passes for the wrong reason. Every widget test
/// in this project goes through here.
///
/// [WindTheme] sits inside [MaterialApp] on purpose: it keeps the wrapper
/// usable for leaf widgets. Any test that exercises dark mode needs the
/// opposite nesting, because [WindTheme] rebuilds on
/// `didChangePlatformBrightness` and that rebuild does not reach a
/// [MaterialApp] above it. Write that wrapper when the first such test exists.
///
/// Pass [themeData] to exercise the project's own tokens; the default is
/// Wind's stock scales, which is what you want when the test is about layout
/// rather than about branding.
///
/// ### Example
/// ```dart
/// await tester.pumpWidget(wrapWithTheme(const WText('Hi', className: 'text-lg')));
/// ```
Widget wrapWithTheme(Widget child, {WindThemeData? themeData}) {
  return MaterialApp(
    home: WindTheme(
      data: themeData ?? WindThemeData(),
      child: Scaffold(body: child),
    ),
  );
}
