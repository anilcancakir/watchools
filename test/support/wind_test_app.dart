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
/// Pass [brightness] to pin which half of every `'<light> dark:<dark>'` alias
/// resolves. The app is dark-first, so a test that does not pin it asserts
/// against the light half and will not catch a dark-mode regression.
///
/// `syncWithSystem` is forced off alongside it. Wind documents this as
/// divergence F05: a declarative `brightness` is overridden by the system
/// value unless sync is disabled, so setting brightness alone leaves the test
/// resolving whatever the host machine is set to.
Widget wrapWithTheme(Widget child, {WindThemeData? themeData, Brightness brightness = Brightness.light}) {
  final WindThemeData base = themeData ?? WindThemeData();

  return MaterialApp(
    home: WindTheme(
      data: base.copyWith(brightness: brightness, syncWithSystem: false),
      child: Scaffold(body: child),
    ),
  );
}
