import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/app/provider/provider_session.dart';
import 'package:watchools/ui/components/provider_notice/index.dart';
import 'package:watchools/ui/layouts/curtain_layout.dart';
import 'package:watchools/ui/layouts/now_layout.dart';
import 'package:watchools/ui/layouts/showcase_layout.dart';
import 'package:watchools/ui/layouts/support/category_strip.dart';
import 'package:watchools/ui/layouts/support/guide_empty.dart';
import 'package:watchools/ui/layouts/support/library_empty.dart';
import 'package:watchools/ui/layouts/support/library_toolbar.dart';
import 'package:watchools/ui/layouts/support/search_field.dart';
import 'package:watchools/ui/layouts/time_layout.dart';

import '../../support/screen.dart';

/// Whether a provider fault reaches the four browse surfaces, in the same
/// slot `GuideEmpty` / `LibraryEmpty` already render, without stranding the
/// viewer behind a swapped-out toolbar.
///
/// The precedence test is the one the step is graded on: a fault and an
/// empty result are different statements, and a session carrying both has to
/// render the fault alone. A worker that checked `matches.isEmpty` before
/// `fault` would pass every other test here and fail only that one.
void main() {
  setUp(WindParser.clearCache);

  const Channel channel = Channel(
    number: 1,
    name: 'Anadolu Spor',
    group: 'Spor',
    status: ChannelStatus.idle,
    streamId: 10,
  );
  const TitleItem title = TitleItem(kind: TitleKind.movie, name: 'Ada', category: 'Aksiyon', year: 2020, providerId: 1);

  group('the live views (Şimdi, Zaman)', () {
    final Map<String, Widget Function(GuideController)> views = <String, Widget Function(GuideController)>{
      'Şimdi': (GuideController c) => NowLayout(controller: c),
      'Zaman': (GuideController c) => TimeLayout(controller: c),
    };

    for (final MapEntry<String, Widget Function(GuideController)> entry in views.entries) {
      testWidgets('${entry.key} renders the notice and keeps the toolbar when the session carries a fault', (
        WidgetTester tester,
      ) async {
        final GuideController controller = GuideController(
          session: _FaultGuideSession(channels: const <Channel>[channel], fault: ProviderFault.unreachable),
        );

        await pumpScreen(tester, entry.value(controller));

        expect(find.byType(ProviderNotice), findsOneWidget);
        expect(find.byType(GuideEmpty), findsNothing);
        expect(find.byType(SearchField), findsOneWidget, reason: 'a fault must not strand the viewer off search');
        expect(find.byType(CategoryStrip), findsOneWidget, reason: 'nor off the category strip');
      });

      testWidgets('${entry.key} renders the notice alone when the fault AND the result are both empty', (
        WidgetTester tester,
      ) async {
        final GuideController controller = GuideController(
          session: _FaultGuideSession(channels: const <Channel>[], fault: ProviderFault.expired),
        );

        await pumpScreen(tester, entry.value(controller));

        expect(find.byType(ProviderNotice), findsOneWidget);
        expect(find.byType(GuideEmpty), findsNothing, reason: 'a fault is the more specific statement');
      });

      testWidgets('${entry.key} still renders the empty state when there is no fault', (WidgetTester tester) async {
        final GuideController controller = GuideController(
          session: _FaultGuideSession(channels: const <Channel>[], fault: null),
        );

        await pumpScreen(tester, entry.value(controller));

        expect(find.byType(GuideEmpty), findsOneWidget);
        expect(find.byType(ProviderNotice), findsNothing);
      });

      testWidgets('${entry.key} routes the notice action through GuideController.reload', (WidgetTester tester) async {
        final _FaultGuideSession session = _FaultGuideSession(
          channels: const <Channel>[channel],
          fault: ProviderFault.unreachable,
        );
        final GuideController controller = GuideController(session: session);

        await pumpScreen(tester, entry.value(controller));
        await tester.tap(
          find.descendant(
            of: find.byType(ProviderNotice),
            matching: find.byWidgetPredicate((Widget w) => w is WAnchor && w.onTap != null),
          ),
        );
        await tester.pump();

        expect(session.refreshCalls, 1);
      });
    }
  });

  group('Vitrin', () {
    Widget showcase(LibraryController c) => ShowcaseLayout(controller: c);

    testWidgets('renders the notice and keeps the toolbar when the session carries a fault', (
      WidgetTester tester,
    ) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[title], fault: ProviderFault.throttled),
      );

      await pumpScreen(tester, showcase(controller));

      expect(find.byType(ProviderNotice), findsOneWidget);
      expect(find.byType(LibraryEmpty), findsNothing);
      expect(find.byType(LibraryToolbar), findsOneWidget);
    });

    testWidgets('renders the notice alone when the fault AND the result are both empty', (WidgetTester tester) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[], fault: ProviderFault.evicted),
      );

      await pumpScreen(tester, showcase(controller));

      expect(find.byType(ProviderNotice), findsOneWidget);
      expect(find.byType(LibraryEmpty), findsNothing, reason: 'a fault is the more specific statement');
    });

    testWidgets('still renders the empty state when there is no fault', (WidgetTester tester) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[], fault: null),
      );

      await pumpScreen(tester, showcase(controller));

      expect(find.byType(LibraryEmpty), findsOneWidget);
      expect(find.byType(ProviderNotice), findsNothing);
    });

    testWidgets('routes the notice action through LibraryController.reload', (WidgetTester tester) async {
      final _FaultLibrarySession session = _FaultLibrarySession(
        titles: const <TitleItem>[title],
        fault: ProviderFault.throttled,
      );
      final LibraryController controller = LibraryController(session: session);

      await pumpScreen(tester, showcase(controller));
      await tester.tap(
        find.descendant(
          of: find.byType(ProviderNotice),
          matching: find.byWidgetPredicate((Widget w) => w is WAnchor && w.onTap != null),
        ),
      );
      await tester.pump();

      expect(session.refreshCalls, 1);
    });
  });

  group('Perde', () {
    Widget curtain(LibraryController c) => CurtainLayout(controller: c);

    testWidgets('renders the notice when the session carries a fault, even with a title selected', (
      WidgetTester tester,
    ) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[title], fault: ProviderFault.unreachable),
      );

      await pumpScreen(tester, curtain(controller));

      expect(find.byType(ProviderNotice), findsOneWidget);
      expect(find.byType(LibraryEmpty), findsNothing);
    });

    testWidgets('renders the notice alone when the fault AND the catalogue are both empty', (
      WidgetTester tester,
    ) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[], fault: ProviderFault.expired),
      );

      await pumpScreen(tester, curtain(controller));

      expect(find.byType(ProviderNotice), findsOneWidget);
      expect(find.byType(LibraryEmpty), findsNothing, reason: 'a fault is the more specific statement');
    });

    testWidgets('still renders the no-selection arm when there is no fault', (WidgetTester tester) async {
      final LibraryController controller = LibraryController(
        session: _FaultLibrarySession(titles: const <TitleItem>[], fault: null),
      );

      await pumpScreen(tester, curtain(controller));

      expect(find.byType(LibraryEmpty), findsOneWidget);
      expect(find.byType(ProviderNotice), findsNothing);
    });

    testWidgets('routes the notice action through LibraryController.reload', (WidgetTester tester) async {
      final _FaultLibrarySession session = _FaultLibrarySession(
        titles: const <TitleItem>[title],
        fault: ProviderFault.unreachable,
      );
      final LibraryController controller = LibraryController(session: session);

      await pumpScreen(tester, curtain(controller));
      await tester.tap(
        find.descendant(
          of: find.byType(ProviderNotice),
          matching: find.byWidgetPredicate((Widget w) => w is WAnchor && w.onTap != null),
        ),
      );
      await tester.pump();

      expect(session.refreshCalls, 1);
    });
  });
}

/// A session double reporting a fixed fault and channel list, so the
/// line-up's fault arm can be exercised without a network, a `Vault` entry or
/// SQLite. Counts [refresh] calls, which is what [GuideController.reload]
/// invokes, so a test can prove the notice's action reaches the session.
class _FaultGuideSession extends ProviderSession {
  _FaultGuideSession({required this.channels, required this.fault});

  @override
  final List<Channel> channels;

  @override
  bool get hasCredentials => true;

  @override
  final ProviderFault? fault;

  /// How many times [refresh] was called.
  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

/// The catalogue's equivalent of [_FaultGuideSession].
class _FaultLibrarySession extends ProviderSession {
  _FaultLibrarySession({required this.titles, required this.fault});

  @override
  final List<TitleItem> titles;

  @override
  bool get hasCredentials => true;

  @override
  final ProviderFault? fault;

  /// How many times [refresh] was called.
  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}
