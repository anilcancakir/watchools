import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/config/watchools_status_tokens.dart';
import 'package:watchools/config/watchools_theme.dart';
import 'package:watchools/config/wind_theme.g.dart';

import '../support/wind_test_app.dart';

/// The relative luminance of an `#RRGGBB` string, per WCAG 2.1.
double _luminance(String hex) {
  final List<double> channels = <int>[1, 3, 5].map<double>((int i) {
    final double c = int.parse(hex.substring(i, i + 2), radix: 16) / 255;

    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }).toList();

  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

/// The WCAG contrast ratio between two `#RRGGBB` strings.
double _contrast(String a, String b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);

  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Pulls the dark half out of an alias value shaped `'<util>-[#L] dark:<util>-[#D]'`.
String _darkHex(String alias) => RegExp(r'dark:[a-z-]+-\[(#[0-9A-Fa-f]{6})\]').firstMatch(alias)!.group(1)!;

/// Pulls the light half out of the same shape.
String _lightHex(String alias) => RegExp(r'^[a-z-]+-\[(#[0-9A-Fa-f]{6})\]').firstMatch(alias)!.group(1)!;

void main() {
  setUp(WindParser.clearCache);

  group('generated aliases', () {
    test('carries every one of the 17 semantic roles', () {
      // design:sync emits exactly these. A regenerate that drops one shows up
      // as a class silently resolving to nothing, never as an error.
      expect(designAliases.keys, hasLength(17));
      expect(
        designAliases.keys,
        containsAll(<String>[
          'bg-surface',
          'bg-surface-container',
          'bg-surface-container-high',
          'text-fg',
          'text-fg-muted',
          'text-fg-disabled',
          'bg-primary',
          'text-on-primary',
          'bg-primary-container',
          'bg-accent',
          'border-color-border',
          'border-color-border-subtle',
          'bg-destructive',
          'text-on-destructive',
          'bg-destructive-container',
          'bg-success',
          'bg-warning',
        ]),
      );
    });

    test('every alias carries both a light and a dark half', () {
      for (final MapEntry<String, String> entry in designAliases.entries) {
        expect(entry.value, contains('dark:'), reason: '${entry.key} has no dark half, so dark mode falls back');
      }
    });
  });

  group('status supplement', () {
    test('does not collide with any generated alias', () {
      // The merge is `{...designAliases, ...watchoolsStatusAliases}`, so a
      // shared key would silently overwrite a generated role rather than fail.
      final Set<String> overlap = designAliases.keys.toSet().intersection(watchoolsStatusAliases.keys.toSet());

      expect(overlap, isEmpty, reason: 'status tokens would clobber $overlap');
    });

    test('gives every playback state its four tokens', () {
      for (final String state in <String>['live', 'recording', 'catchup', 'epg-now']) {
        expect(watchoolsStatusAliases, contains('bg-$state'));
        expect(watchoolsStatusAliases, contains('text-$state'));
        expect(watchoolsStatusAliases, contains('bg-$state-soft'));
        expect(watchoolsStatusAliases, contains('text-$state-soft-foreground'));
      }
    });

    test('keeps focus off the brand colour', () {
      // On a D-pad surface focus moves on every keypress and selection does
      // not. If these two ever resolve to the same colour, "where am I" and
      // "what is chosen" become the same signal and the TV UI is unusable.
      expect(_darkHex(watchoolsStatusAliases['bg-focus-ring']!), isNot(_darkHex(designAliases['bg-primary']!)));
    });
  });

  group('theme assembly', () {
    test('merges both halves and keeps our scales', () {
      final WindThemeData theme = buildWatchoolsWindTheme();

      expect(theme.aliases, contains('bg-primary'));
      expect(theme.aliases, contains('bg-live-soft'));
      expect(theme.fontFamilies['sans'], 'Schibsted Grotesk');
      // 2px, not Wind's default. The fact chip reads as a texture at 2 and as
      // a row of separate objects at 4, which is the whole point of the
      // state-versus-fact split.
      expect(theme.borderRadius['sm'], 2);
    });
  });

  group('contrast', () {
    // A palette edit that breaks accessibility is invisible until someone
    // squints at a real screen. These assert the floors instead.
    const Map<String, String> darkSurfaces = <String, String>{
      'bg-surface': 'page',
      'bg-surface-container': 'card',
      'bg-surface-container-high': 'elevated',
    };

    test('body and muted text clear AA on every dark surface', () {
      for (final MapEntry<String, String> surface in darkSurfaces.entries) {
        final String bg = _darkHex(designAliases[surface.key]!);
        for (final String role in <String>['text-fg', 'text-fg-muted']) {
          final double ratio = _contrast(_darkHex(designAliases[role]!), bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$role on ${surface.value} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      }
    });

    test('the brand gold clears AA on every dark surface', () {
      final String gold = _darkHex(designAliases['bg-primary']!);
      for (final MapEntry<String, String> surface in darkSurfaces.entries) {
        final double ratio = _contrast(gold, _darkHex(designAliases[surface.key]!));
        expect(ratio, greaterThanOrEqualTo(4.5), reason: 'gold on ${surface.value} is ${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('button labels clear AA on their own fill, both themes', () {
      for (final List<String> pair in <List<String>>[
        <String>['text-on-primary', 'bg-primary'],
        <String>['text-on-destructive', 'bg-destructive'],
      ]) {
        expect(
          _contrast(_darkHex(designAliases[pair[0]]!), _darkHex(designAliases[pair[1]]!)),
          greaterThanOrEqualTo(4.5),
          reason: '${pair[0]} on ${pair[1]}, dark',
        );
        expect(
          _contrast(_lightHex(designAliases[pair[0]]!), _lightHex(designAliases[pair[1]]!)),
          greaterThanOrEqualTo(4.5),
          reason: '${pair[0]} on ${pair[1]}, light',
        );
      }
    });

    test('every soft badge label clears AA on its own background', () {
      for (final String state in <String>['live', 'recording', 'catchup', 'epg-now']) {
        final String bg = watchoolsStatusAliases['bg-$state-soft']!;
        final String fg = watchoolsStatusAliases['text-$state-soft-foreground']!;
        expect(_contrast(_darkHex(fg), _darkHex(bg)), greaterThanOrEqualTo(4.5), reason: '$state soft badge, dark');
        expect(_contrast(_lightHex(fg), _lightHex(bg)), greaterThanOrEqualTo(4.5), reason: '$state soft badge, light');
      }
    });
  });

  group('rendering', () {
    testWidgets('resolves bg-primary to the brand gold in dark mode', (WidgetTester tester) async {
      const ValueKey<String> key = ValueKey<String>('brand');

      await tester.pumpWidget(
        wrapWithTheme(
          const WDiv(key: key, className: 'bg-primary p-4', child: WText('x')),
          themeData: buildWatchoolsWindTheme(),
          brightness: Brightness.dark,
        ),
      );

      final Iterable<int> resolved = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)))
          .map((DecoratedBox box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((BoxDecoration d) => d.color)
          .nonNulls
          .map((Color c) => c.toARGB32());

      final int expected = int.parse(_darkHex(designAliases['bg-primary']!).substring(1), radix: 16) | 0xFF000000;

      expect(resolved, contains(expected));
    });
  });
}
