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
  int detaches = 0;
  int retries = 0;
  final List<Channel> played = <Channel>[];

  @override
  Future<void> togglePause() async => toggles++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> attach(PlaybackSurface surface) async => attaches++;

  @override
  Future<void> detach() async => detaches++;

  @override
  Future<void> play(Channel channel) async => played.add(channel);

  @override
  Future<void> retry() async => retries++;
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

    testWidgets('the notice retries the load rather than toggling a pause', (WidgetTester tester) async {
      // `ProviderNotice.onRetry` means "make the request again". For
      // `unreachable` and `evicted` there is no core to toggle, so an earlier
      // version wired this to `togglePause` and the only action a fault offered
      // was pausing a stream that had never opened.
      final _FakePlayback playback = _FakePlayback(fault: ProviderFault.evicted);
      await pumpLayout(tester, playback);

      // `evicted`'s own action label, which is the notice's copy rather than
      // this layout's.
      await tester.tap(find.bySemanticsLabel('Bağlantıyı devral'));
      await tester.pump();

      expect(playback.retries, 1);
      expect(playback.toggles, 0);
    });

    testWidgets('an unplayable channel says so rather than showing a fault', (WidgetTester tester) async {
      await pumpLayout(tester, _FakePlayback(unplayable: true));

      expect(find.byType(ProviderNotice), findsNothing);
      expect(find.text('Bu kanal oynatılamıyor'), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsOneWidget);

      // Named, which is what the controller keeping the channel through a
      // refusal is for: the message alone leaves the user guessing which
      // channel it is about. Found on the running app, where the controller
      // fix had bought nothing visible because this branch replaced the name
      // instead of adding to it.
      expect(find.text(_channel.name), findsOneWidget);

      // And it offers no transport control. An unplayable channel opened no
      // core, so pause would reach the native side with nothing to pause and
      // come back an error the user cannot act on. The way out stays.
      expect(find.bySemanticsLabel('Duraklat'), findsNothing);
      expect(find.bySemanticsLabel('Devam et'), findsNothing);
    });
  });

  group('nothing washes the picture', () {
    testWidgets('no scrim covers the frame, whatever the state', (WidgetTester tester) async {
      // `DESIGN.md:440-443`: no scrim spans the frame. The first
      // version stacked `Scrim.flat` (85 percent black at its bottom stop) and
      // `Scrim.bottom` (the opaque surface colour) full-bleed over the view,
      // which painted the lower third of the picture out. Asserted on the
      // stack's own children rather than on a rendered colour, because the
      // widget test's square font makes nothing about the paint measurable.
      for (final _FakePlayback playback in <_FakePlayback>[
        _FakePlayback(),
        _FakePlayback(unplayable: true),
        _FakePlayback(fault: ProviderFault.unreachable),
      ]) {
        await pumpLayout(tester, playback);

        final Stack stack = tester.widget<Stack>(find.byType(Stack).first);
        final Iterable<Widget> unpositioned = stack.children.where(
          (Widget each) => each is! Positioned && each is! WatchoolsPlayerView,
        );

        expect(
          unpositioned,
          isEmpty,
          reason: 'every child above the view is bounded by a Positioned, so none of them covers the frame',
        );
      }
    });
  });
}
