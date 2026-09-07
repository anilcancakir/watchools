import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/ui/layouts/curtain_layout.dart';
import 'package:watchools/ui/layouts/now_layout.dart';
import 'package:watchools/ui/layouts/showcase_layout.dart';
import 'package:watchools/ui/layouts/time_layout.dart';

import '../../support/screen.dart';

/// Every shipping layout pumped at both widths, through the states that have
/// actually broken something here.
///
/// What this gate is and is not. It fails on an EXCEPTION during build or paint
/// and says nothing about overflow, because `flutter_test` substitutes a font
/// whose every glyph is a square of the font size and almost every text-bearing
/// row overflows under those metrics. Real-font overflow belongs to
/// `tool/dusk/*_e2e.sh`, which drives the actual engine; the reasoning is
/// recorded in full in `test/support/screen.dart`.
///
/// That half still earns its place. It is what caught `LayoutBuilder does not
/// support returning intrinsic dimensions` on an empty result set, and what
/// would have caught the `RenderBox was not laid out` a layout took when its
/// centring wrapper was written in Wind rather than in Flutter.
void main() {
  setUp(WindParser.clearCache);

  group('the live views', () {
    late GuideController controller;

    setUp(() => controller = GuideController());

    Map<String, Widget Function()> views() => <String, Widget Function()>{
      'Şimdi': () => NowLayout(controller: controller),
      'Zaman': () => TimeLayout(controller: controller),
    };

    for (final Size size in <Size>[desktop, mobile]) {
      final String width = '${size.width.round()}';

      for (final MapEntry<String, Widget Function()> entry in views().entries) {
        testWidgets('${entry.key} renders the whole line-up at $width', (WidgetTester tester) async {
          await pumpScreen(tester, entry.value(), size: size);
        });

        testWidgets('${entry.key} renders an empty result set at $width', (WidgetTester tester) async {
          // A search that matches nothing. The empty state is its own layout in
          // both views and it is the one nobody looks at.
          controller.search('zzzzzzzz');
          await pumpScreen(tester, entry.value(), size: size);
        });

        testWidgets('${entry.key} renders an empty favourites filter at $width', (WidgetTester tester) async {
          controller.selectGroup('Favoriler');
          await pumpScreen(tester, entry.value(), size: size);
        });

        testWidgets('${entry.key} renders a starred line-up at $width', (WidgetTester tester) async {
          controller.toggleFavourite(controller.channels.first);
          await pumpScreen(tester, entry.value(), size: size);
        });

        testWidgets('${entry.key} renders a channel with no guide selected at $width', (WidgetTester tester) async {
          // The hero and the grid row both have a no-EPG state, and it is the
          // common case rather than the exception.
          controller.selectChannel(controller.channels.firstWhere((Channel c) => !c.hasSchedule));
          await pumpScreen(tester, entry.value(), size: size);
        });

        testWidgets('${entry.key} renders with the other view selected at $width', (WidgetTester tester) async {
          // The switch is on both toolbars and its unselected segment is a
          // different className branch from its selected one, so a layout
          // pumped only in its own mode never builds half the control.
          controller.showMode(entry.key == 'Şimdi' ? GuideMode.grid : GuideMode.now);
          await pumpScreen(tester, entry.value(), size: size);
        });
      }
    }
  });

  group('the catalogue', () {
    late LibraryController controller;

    setUp(() => controller = LibraryController());

    Widget showcase() => ShowcaseLayout(controller: controller);

    for (final Size size in <Size>[desktop, mobile]) {
      final String width = '${size.width.round()}';

      testWidgets('Vitrin renders the whole catalogue at $width', (WidgetTester tester) async {
        await pumpScreen(tester, showcase(), size: size);
      });

      testWidgets('Vitrin renders an empty result set at $width', (WidgetTester tester) async {
        controller.search('zzzzzzzz');
        await pumpScreen(tester, showcase(), size: size);
      });

      testWidgets('Vitrin renders series only at $width', (WidgetTester tester) async {
        controller.showScope(LibraryScope.series);
        await pumpScreen(tester, showcase(), size: size);
      });

      testWidgets('Vitrin renders an empty continue-watching at $width', (WidgetTester tester) async {
        // The hero falls back to the first entry when nothing is part-watched,
        // and the resume rail disappears. Both paths are otherwise unexercised.
        controller.selectCategory('Belgesel');
        await pumpScreen(tester, showcase(), size: size);
      });
    }
  });

  group('the title screen', () {
    late LibraryController controller;

    setUp(() => controller = LibraryController());

    Widget curtain() => CurtainLayout(controller: controller);

    TitleItem series() => controller.titles.firstWhere((TitleItem t) => t.isSeries);
    TitleItem film() => controller.titles.firstWhere((TitleItem t) => !t.isSeries);

    /// No poster, no rating, no synopsis, no cast. A large share of a real
    /// catalogue looks exactly like this, and it is the case the artwork-led
    /// half of the screen cannot render.
    TitleItem bare() =>
        controller.titles.firstWhere((TitleItem t) => t.posterUrl == null && t.rating == null && t.synopsis == null);

    for (final Size size in <Size>[desktop, mobile]) {
      final String width = '${size.width.round()}';

      testWidgets('Perde renders a series at $width', (WidgetTester tester) async {
        controller.select(series());
        await pumpScreen(tester, curtain(), size: size);
      });

      testWidgets('Perde renders a film at $width', (WidgetTester tester) async {
        controller.select(film());
        await pumpScreen(tester, curtain(), size: size);
      });

      testWidgets('Perde renders a title with nothing filled in at $width', (WidgetTester tester) async {
        controller.select(bare());
        await pumpScreen(tester, curtain(), size: size);
      });
    }

    testWidgets('every season of a series renders', (WidgetTester tester) async {
      final TitleItem show = series();
      controller.select(show);

      for (final int season in show.seasons) {
        controller.selectSeason(season);
        await pumpScreen(tester, curtain());
      }
    });
  });
}
