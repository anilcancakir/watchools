import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/playback_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/playback/playback_engine.dart';
import 'package:watchools/ui/components/provider_notice/provider_notice.dart';
import 'package:watchools/ui/layouts/playback_layout.dart';
import 'package:watchools_player/watchools_player.dart';

import '../../support/screen.dart';

const Channel _channel = Channel(
  number: 2,
  name: '02 H.264 AAC | RAW TS',
  group: 'Ulusal',
  status: ChannelStatus.live,
  streamId: 10002,
);

/// A stand-in for `PlaybackController`, so the layout is tested against the
/// contract it reads rather than against a container, a session and a panel.
///
/// Records what a control reached, because the assertion that matters most on
/// this surface is that a tap crossed the boundary at all: gestures do not
/// reach a macOS platform view, so a control placed wrong is invisible to the
/// user and silent in a widget test.
class _FakePlayback implements PlaybackFacade {
  _FakePlayback({this.health = PlaybackHealth.playing, this.fault, this.unplayable = false});

  @override
  final Channel? channel = _channel;

  @override
  PlaybackHealth health;

  @override
  final ProviderFault? fault;

  @override
  final bool unplayable;

  int toggles = 0;
  int stops = 0;
  int attaches = 0;

  @override
  Future<void> togglePause() async => toggles++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> attach(PlaybackSurface surface) async => attaches++;
}

void main() {
  setUp(WindParser.clearCache);

  int backs = 0;

  setUp(() => backs = 0);

  Future<void> pumpLayout(WidgetTester tester, _FakePlayback playback, {Size size = desktop}) => pumpScreen(
    tester,
    PlaybackLayout(playback: playback, onBack: () => backs++),
    size: size,
  );

  group('the stack', () {
    testWidgets('puts the platform view at the base and the controls above it', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback());

      expect(find.byType(WatchoolsPlayerView), findsOneWidget);

      // Above, not merely present. A control behind the view is invisible to a
      // tap on macOS and no widget test would say so, which is why the order
      // is asserted rather than the membership.
      final Stack stack = tester.widget<Stack>(find.byType(Stack).first);
      final int viewIndex = stack.children.indexWhere((Widget each) => each is WatchoolsPlayerView);

      expect(viewIndex, 0);
    });

    testWidgets('names the channel it is playing', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback());

      expect(find.text('02 H.264 AAC | RAW TS'), findsOneWidget);
    });

    testWidgets('renders at a mobile size as well as a desktop one', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(), size: const Size(414, 896));

      expect(find.byType(WatchoolsPlayerView), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('the pause control reaches the controller', (WidgetTester tester) async {
      final _FakePlayback playback = _FakePlayback();
      await pumpLayout(tester, playback);

      expect(playback.toggles, 0);

      await tester.tap(find.bySemanticsLabel('Duraklat'));
      await tester.pump();

      expect(playback.toggles, 1);
    });

    testWidgets('the control says resume once the engine reports paused', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(health: PlaybackHealth.paused));

      expect(find.bySemanticsLabel('Devam et'), findsOneWidget);
      expect(find.bySemanticsLabel('Duraklat'), findsNothing);
    });

    testWidgets('the back affordance stops playback rather than leaving the core open', (WidgetTester tester) async {
      final _FakePlayback playback = _FakePlayback();
      await pumpLayout(tester, playback);

      await tester.tap(find.bySemanticsLabel('Geri'));
      await tester.pump();

      // The measured account allows one connection, so a screen that navigates
      // away without stopping is the reason the next device cannot watch.
      // Both halves asserted: the stop AND the navigation, because a back
      // button that releases the core and strands the user is as wrong as one
      // that leaves it open.
      expect(playback.stops, 1);
      expect(backs, 1);
    });

    testWidgets('attaches the surface when the platform view reports its identifier', (WidgetTester tester) async {
      final _FakePlayback playback = _FakePlayback();
      await pumpLayout(tester, playback);

      final WatchoolsPlayerView view = tester.widget<WatchoolsPlayerView>(find.byType(WatchoolsPlayerView));

      expect(view.onReady, isNotNull);

      view.onReady!(7);
      await tester.pump();

      expect(playback.attaches, 1);
    });
  });

  group('health, told apart rather than folded together', () {
    testWidgets('an asleep display reads differently from a stall', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(health: PlaybackHealth.notPresenting));
      final Finder asleep = find.text('Ekran uyandığında geri gelir');

      expect(asleep, findsOneWidget);

      await pumpLayout(tester, _FakePlayback(health: PlaybackHealth.stalled));

      expect(asleep, findsNothing);
      expect(find.text('Yayın durdu'), findsOneWidget);
    });

    testWidgets('a healthy stream shows no health message at all', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback());

      expect(find.text('Yayın durdu'), findsNothing);
      expect(find.text('Ekran uyandığında geri gelir'), findsNothing);
    });

    testWidgets('starving says the window is waiting, not that it broke', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(health: PlaybackHealth.starving));

      expect(find.text('Yayın durdu'), findsNothing);
      expect(find.text('Arabelleğe alınıyor'), findsOneWidget);
    });
  });

  group('faults', () {
    for (final ProviderFault fault in ProviderFault.values) {
      testWidgets('renders the notice for $fault without hiding the way back', (WidgetTester tester) async {
        await pumpLayout(tester, _FakePlayback(fault: fault));

        expect(find.byType(ProviderNotice), findsOneWidget);

        // The back affordance sits above the branch rather than inside it. A
        // fault that swallowed the only way out would strand the user, and
        // this project has already paid for a widget that moved between two
        // parents across a branch.
        expect(find.bySemanticsLabel('Geri'), findsOneWidget);
      });
    }

    testWidgets('an unplayable channel says so rather than showing a fault', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(unplayable: true));

      expect(find.byType(ProviderNotice), findsNothing);
      expect(find.text('Bu kanal oynatılamıyor'), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsOneWidget);
    });
  });
}
