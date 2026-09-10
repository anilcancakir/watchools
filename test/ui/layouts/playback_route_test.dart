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

    test('every path navigated to from a layout is a path that is registered', () async {
      // The failure this exists for, found on the running app: `/saglayici` was
      // reached from five layouts and registered nowhere, so
      // `ProviderNotice`'s action on `expired` fell through to `/` and put the
      // user back on the live screen with the same dead catalogue. Nothing
      // errored, because `MagicRoute.to` on an unknown path is a fall-through
      // rather than a throw, which is exactly how six call sites accumulated
      // against a route that did not exist.
      //
      // Read as source for the same reason the test above is: the table can
      // only be built once per process.
      final String routes = await File('lib/routes/app.dart').readAsString();
      final Iterable<File> layouts = Directory('lib/ui/layouts')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'));

      final Set<String> navigated = <String>{};

      for (final File layout in layouts) {
        final String source = layout.readAsStringSync();

        for (final RegExpMatch match in RegExp(r"MagicRoute\.to\('([^']+)'\)").allMatches(source)) {
          navigated.add(match.group(1)!);
        }
      }

      // The regex has to have found something, or this test passes by reading
      // nothing. That is the shape of vacuous check this project keeps paying
      // for, so the guard is part of the assertion rather than a comment.
      expect(navigated, isNotEmpty, reason: 'no MagicRoute.to call was found, so nothing was checked');

      for (final String path in navigated) {
        expect(
          routes.contains("MagicRoute.page('$path'"),
          isTrue,
          reason: '$path is navigated to from a layout but registered in no route',
        );
      }
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
