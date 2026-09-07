import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/ui/layouts/ledger_layout.dart';
import 'package:watchools/ui/layouts/showcase_layout.dart';
import 'package:watchools/ui/layouts/wall_layout.dart';

import '../../support/screen.dart';

/// The three competing catalogue layouts, at both widths.
///
/// See `lineup_layouts_test.dart` for why these exist alongside the dusk walk,
/// and `../../support/screen.dart` for what a widget test here can and cannot
/// tell you about a layout.
void main() {
  late LibraryController controller;

  Widget layout(LibraryLayout which) => switch (which) {
    LibraryLayout.wall => WallLayout(controller: controller),
    LibraryLayout.ledger => LedgerLayout(controller: controller),
    LibraryLayout.showcase => ShowcaseLayout(controller: controller),
  };

  TitleItem series() => controller.titles.firstWhere((TitleItem t) => t.name == 'Bozkır Hattı');

  setUp(() {
    WindParser.clearCache();
    controller = LibraryController();
  });

  for (final (String name, Size size) in <(String, Size)>[('desktop', desktop), ('mobile', mobile)]) {
    group('at $name', () {
      for (final LibraryLayout which in LibraryLayout.values) {
        group(which.name, () {
          testWidgets('renders the catalogue', (WidgetTester tester) async {
            await pumpScreen(tester, layout(which), size: size);

            expect(find.byType(WDiv), findsWidgets);
            expect(find.byType(WInput), findsAtLeast(1));
          });

          testWidgets('states how many titles arrived with no poster', (WidgetTester tester) async {
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.noArtworkNote, isNotNull);
            expect(find.textContaining('afiş yok', findRichText: true), findsWidgets);
          });

          testWidgets('renders films only and series only', (WidgetTester tester) async {
            for (final LibraryScope scope in <LibraryScope>[LibraryScope.movies, LibraryScope.series]) {
              controller.showScope(scope);
              await pumpScreen(tester, layout(which), size: size);
              expect(controller.matches, isNotEmpty);
            }
          });

          testWidgets('survives an empty result set', (WidgetTester tester) async {
            controller.search('zzzzzz');
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.matches, isEmpty);
            expect(find.text('Sonuç yok'), findsOneWidget);
          });

          testWidgets('survives an empty favourites list', (WidgetTester tester) async {
            // The fixture ships two starred titles, so they have to come off
            // before this state exists at all.
            for (final TitleItem starred in controller.titles.where((TitleItem t) => t.favourite).toList()) {
              controller.toggleFavourite(starred);
            }
            controller.selectCategory('Favoriler');
            await pumpScreen(tester, layout(which), size: size);

            expect(find.text('Henüz favori yok'), findsOneWidget);
          });

          testWidgets('survives an empty continue-watching list', (WidgetTester tester) async {
            // Reachable in the real app the moment a viewer finishes what they
            // started, and the state a shelf layout is most likely to render
            // as a blank band.
            controller.search('Mahalle');
            controller.selectCategory('İzlemeye devam et');
            await pumpScreen(tester, layout(which), size: size);

            expect(controller.matches, isEmpty);
          });

          testWidgets('renders the detail surface for a series', (WidgetTester tester) async {
            controller.openDetail(series());
            await pumpScreen(tester, layout(which), size: size);

            // The play button names the episode it will resume, which is the
            // whole point of a series page.
            expect(find.textContaining('S02B02', findRichText: true), findsWidgets);
          });

          testWidgets('renders the detail surface for a film', (WidgetTester tester) async {
            controller.openDetail(controller.titles.firstWhere((TitleItem t) => !t.isSeries && t.inProgress));
            await pumpScreen(tester, layout(which), size: size);

            expect(find.text('Devam et'), findsWidgets);
          });

          testWidgets('renders a title with no poster, no rating and no synopsis', (WidgetTester tester) async {
            // A large share of a real catalogue looks like this, and it is the
            // entry every poster-led layout has to answer for.
            final TitleItem bare = controller.titles.firstWhere(
              (TitleItem t) => t.posterUrl == null && t.rating == null && t.synopsis == null,
            );
            controller.openDetail(bare);
            await pumpScreen(tester, layout(which), size: size);

            expect(find.textContaining(bare.name, findRichText: true), findsWidgets);
          });
        });
      }
    });
  }

  group('the wall layout specifically', () {
    testWidgets('keeps the detail beside the grid above xl and as a screen below', (WidgetTester tester) async {
      controller.openDetail(series());

      // A pane plus a grid below `xl` leaves the grid two columns wide, which
      // is a list with pictures rather than a wall, so there the detail takes
      // the screen and gains a way back out.
      await pumpScreen(tester, layout(LibraryLayout.wall), size: const Size(1600, 900));
      expect(find.bySemanticsLabel('Kütüphaneye dön'), findsNothing);

      await pumpScreen(tester, layout(LibraryLayout.wall), size: mobile);
      expect(find.bySemanticsLabel('Kütüphaneye dön'), findsOneWidget);
    });
  });

  group('the ledger layout specifically', () {
    testWidgets('shows the column header only where the columns are', (WidgetTester tester) async {
      await pumpScreen(tester, layout(LibraryLayout.ledger));
      expect(find.text('BAŞLIK'), findsOneWidget);

      await pumpScreen(tester, layout(LibraryLayout.ledger), size: mobile);
      expect(find.text('BAŞLIK'), findsNothing);
    });
  });

  group('the showcase layout specifically', () {
    testWidgets('shows the detail as a screen at every width', (WidgetTester tester) async {
      // A hero sells one title and the shelves sell the rest; neither can hold
      // an episode list, so the detail is never a pane here.
      controller.openDetail(series());

      for (final Size size in <Size>[const Size(1600, 900), desktop, mobile]) {
        await pumpScreen(tester, layout(LibraryLayout.showcase), size: size);
        expect(find.bySemanticsLabel('Kütüphaneye dön'), findsOneWidget);
      }
    });

    testWidgets('leads with continue-watching when there is anything in it', (WidgetTester tester) async {
      await pumpScreen(tester, layout(LibraryLayout.showcase));

      expect(controller.continueWatching, isNotEmpty);
      expect(find.textContaining('İzlemeye devam et', findRichText: true), findsWidgets);
    });
  });
}
