import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/config/watchools_theme.dart';

import '../support/wind_test_app.dart';

/// Every className token the app spends, asserted to resolve to something.
///
/// This file exists because `flutter analyze` cannot see any of it. Wind drops
/// an unrecognised token silently, and only prints a `debugPrint` hint when the
/// token's FAMILY is unknown: a token whose family is recognised but whose
/// value is not is claimed by that parser and dropped with no warning at all.
///
/// Three real defects got through review and a green end-to-end walk before
/// this test existed, and each looked plausible enough on screen to survive:
///
///   * `text-primary` had no alias, so it fell through to the raw `primary`
///     `MaterialColor`, which is seeded on the LIGHT gold and has no `dark:`
///     half. Every gold label rendered `#A36200` on a dark surface while
///     `bg-primary` beside it rendered `#F59B14`.
///   * `ring-focus-ring` cannot match Wind's ring colour regex, which does not
///     admit a hyphenated name. Only the width applied, and the colour came
///     from `WindThemeData.ringColor`, whose default is Tailwind blue-500.
///   * `n-3` is not a Wind token; the line clamp is `line-clamp-3`. Nine texts
///     had no `maxLines` and no ellipsis.
///
/// Add a row here whenever a view spends a token the generator does not emit.
void main() {
  final WindThemeData theme = buildWatchoolsWindTheme();

  /// Parses [className] against the app's own theme, in dark mode.
  Future<WindStyle> resolve(WidgetTester tester, String className) async {
    late WindStyle style;

    await tester.pumpWidget(
      wrapWithTheme(
        Builder(
          builder: (BuildContext context) {
            style = WindParser.parse(className, context);

            return const SizedBox.shrink();
          },
        ),
        themeData: theme,
        brightness: Brightness.dark,
      ),
    );

    return style;
  }

  setUp(WindParser.clearCache);

  group('colour tokens the generator does not emit', () {
    testWidgets('text-primary resolves to the dark-mode gold', (WidgetTester tester) async {
      final WindStyle style = await resolve(tester, 'text-primary');

      expect(style.color, const Color(0xFFF59B14));
    });

    testWidgets('bg-primary-hover resolves', (WidgetTester tester) async {
      final WindStyle style = await resolve(tester, 'bg-primary-hover');

      expect(style.decoration?.color, const Color(0xFFFAB338));
    });

    testWidgets('the scrim weights resolve to translucent black', (WidgetTester tester) async {
      expect((await resolve(tester, 'bg-scrim')).decoration?.color, const Color(0x73000000));
      expect((await resolve(tester, 'bg-scrim-strong')).decoration?.color, const Color(0xB8000000));
    });
  });

  group('the focus ring', () {
    testWidgets('ring-focus-ring carries the audited blue, not Wind default', (WidgetTester tester) async {
      final WindStyle style = await resolve(tester, 'ring-2 ring-focus-ring');

      expect(style.ringWidth, 2);
      expect(style.ringColor, const Color(0xFF7FB2FF));
      // The bug this asserts against: Wind's own default, which rendered
      // identically in both modes and looked deliberate.
      expect(style.ringColor, isNot(const Color(0xFF3B82F6)));
    });

    testWidgets('focus is not the brand colour', (WidgetTester tester) async {
      final WindStyle ring = await resolve(tester, 'ring-focus-ring');
      final WindStyle brand = await resolve(tester, 'text-primary');

      // On a D-pad surface focus moves on every keypress and selection does
      // not. A user who cannot tell "where am I" from "what is chosen" is lost.
      expect(ring.ringColor, isNot(brand.color));
    });
  });

  group('line clamp', () {
    testWidgets('line-clamp-N sets maxLines and an ellipsis', (WidgetTester tester) async {
      final WindStyle style = await resolve(tester, 'line-clamp-3');

      expect(style.maxLines, 3);
      expect(style.textOverflow, TextOverflow.ellipsis);
    });

    testWidgets('n-N, which the app used to spend, resolves to nothing', (WidgetTester tester) async {
      // Kept as a regression marker rather than as an aspiration. `n-3` is a
      // token this app invented and spent in nine places; Wind implements
      // `line-clamp-{n}` and nothing else, and an unrecognised token drops
      // silently, so nine texts had no `maxLines` and the analyser could not
      // see it. The earlier claim that Wind's own docs promised `n-{n}` was a
      // misread of a table cell and is retracted in
      // `.ac/research/ecosystem-defects.md`; this assertion stands on its own.
      final WindStyle style = await resolve(tester, 'n-3');

      expect(style.maxLines, isNull);
    });
  });

  group('the destructive family, which is a button colour and not a text one', () {
    testWidgets('bg-destructive-container resolves, which is what tints the fault disc', (WidgetTester tester) async {
      final WindStyle style = await resolve(tester, 'bg-destructive-container');

      expect(style.decoration?.color, const Color(0xFF4A1216));
    });

    testWidgets('text-destructive resolves to nothing, and that shapes the design', (WidgetTester tester) async {
      // A regression marker in the same spirit as `n-3`. DESIGN.md defines
      // `destructive` as a button colour (`button-destructive`: a background
      // plus its foreground), so `design:sync` emits `bg-destructive`,
      // `bg-destructive-container` and `text-on-destructive` and no text tone.
      // `ProviderNotice` therefore encloses its icon in a tinted disc instead
      // of tinting the glyph, and this assertion is what stops that being
      // "simplified" back to a `text-destructive` that silently does nothing.
      final WindStyle style = await resolve(tester, 'text-destructive');

      expect(style.color, isNull);
    });

    testWidgets('warning is indistinguishable from the brand, so a fault cannot wear it', (WidgetTester tester) async {
      // Doctrine rule 4 reserves the amber for the primary action, progress and
      // live status. This is the measurement behind it: in dark mode `warning`
      // is #F0A93A while `primary` is #F59B14 and `accent` is #FAB338, so a
      // warning-tinted panel above an amber primary button reads as part of the
      // button rather than as a warning.
      // Asserted on hue rather than on the channels. Channel deltas need a
      // threshold nobody can defend, while hue is the claim itself: these are
      // two values of one colour, and a viewer reads hue long before they read
      // a few percent of lightness.
      final WindStyle warning = await resolve(tester, 'bg-warning');
      final WindStyle brand = await resolve(tester, 'bg-primary');
      final WindStyle accent = await resolve(tester, 'bg-accent');

      final double warningHue = HSLColor.fromColor(warning.decoration!.color!).hue;
      final double brandHue = HSLColor.fromColor(brand.decoration!.color!).hue;
      final double accentHue = HSLColor.fromColor(accent.decoration!.color!).hue;

      expect((warningHue - brandHue).abs(), lessThan(2), reason: 'warning and the brand are one hue');
      expect((warningHue - accentHue).abs(), lessThan(2), reason: 'and so is the accent');

      // Distinct tokens, so this is not asserting an identity. They are three
      // values of the same amber, which is the whole problem.
      expect(warning.decoration!.color, isNot(brand.decoration!.color));
    });
  });

  group('the status tokens every layout spends', () {
    testWidgets('the playback states resolve in dark mode', (WidgetTester tester) async {
      expect((await resolve(tester, 'bg-live')).decoration?.color, const Color(0xFFE83730));
      expect((await resolve(tester, 'bg-catchup')).decoration?.color, const Color(0xFF30ABE8));
      expect((await resolve(tester, 'text-epg-now')).color, const Color(0xFFF59B14));
      expect((await resolve(tester, 'bg-inverse')).decoration?.color, const Color(0xFFF2F4F6));
      expect((await resolve(tester, 'text-on-inverse')).color, const Color(0xFF0E0F11));
    });
  });
}
