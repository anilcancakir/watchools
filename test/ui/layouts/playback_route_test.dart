import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/playback_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/playback/fake_playback_engine.dart';
import 'package:watchools/app/support/guide_clock.dart';
import 'package:watchools/ui/layouts/now_layout.dart';

import '../../support/screen.dart';

void main() {
  setUp(WindParser.clearCache);

  group('the route table', () {
    test('declares /izle beside the other three, and declares it once', () async {
      // Read as source rather than by booting the router, because
      // `registerAppRoutes` can only run before `MagicRouter` locks its table
      // and a test that called it twice would throw rather than assert.
      // `magic_router.dart:122-126` is the lock.
      final String source = await File('lib/routes/app.dart').readAsString();

      expect(source.contains("MagicRoute.page('/izle'"), isTrue);
      expect(source.contains('PlaybackView'), isTrue);

      // Registered where `registerAppRoutes()` runs and nowhere else. A route
      // added after the router builds is silently absent rather than an error,
      // which is the failure this asserts against.
      expect("MagicRoute.page('/izle'".allMatches(source).length, 1);
    });
  });

  group('the hero play affordance', () {
    testWidgets('hands the channel to playback and then navigates', (WidgetTester tester) async {
      final GuideController controller = GuideController(clock: FixedGuideClock());
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController playback = PlaybackController(engine: () => engine);
      int navigations = 0;

      // Only the navigation is stubbed. The select and the hand-off run exactly
      // as they run in the app, which is the correction to a first version
      // where the whole sequence sat behind an `onPlay` the test replaced and
      // the real branch was never exercised.
      await pumpScreen(
        tester,
        NowLayout(controller: controller, playbackOverride: playback, onNavigate: () => navigations++),
      );

      final Channel? selectedBefore = controller.channel;

      // The hero's own play control. Its label is the channel or the programme
      // followed by `izle`, which is what makes it findable without reaching
      // for a key.
      final Finder play = find.byWidgetPredicate(
        (Widget widget) => widget is WAnchor && (widget.semanticLabel?.endsWith(' izle') ?? false),
      );

      expect(play, findsWidgets);

      await tester.tap(play.first);
      await tester.pump();

      expect(navigations, 1);

      // And the tile still only selects. A tap that both previewed and left
      // the screen would make the preview unreachable, which is the whole
      // reason the two are separate controls.
      expect(controller.channel, selectedBefore);

      // The hand-off reached the controller, which is what this test can say
      // and the limit of what it should claim. This screen resolves a session
      // with no credential, so `streamUrlFor` returns null and the channel is
      // reported unplayable rather than held.
      //
      // The ordering itself (held before a surface, opened when one arrives)
      // is asserted in `test/app/controllers/playback_controller_test.dart`
      // against a session that has handshaken and can derive a real URL. It
      // has to be: the first version of this test asserted `engine.commands`
      // lacks `load`, which also passes when `play` does nothing at all, and
      // here it does nothing at all. A no-URL screen cannot tell a fixed
      // ordering from an absent one.
      expect(playback.unplayable, isTrue);
      expect(engine.commands, isEmpty);
    });
  });
}
