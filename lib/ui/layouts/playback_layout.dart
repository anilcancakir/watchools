import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:watchools_player/watchools_player.dart';

import '../../app/controllers/playback_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/provider_fault.dart';
import '../../app/playback/playback_engine.dart';
import '../components/provider_notice/provider_notice.dart';
import '../components/scrim/scrim.dart';
import 'support/page_gutter.dart';

/// The playback surface: video underneath, Flutter chrome on top.
///
/// ### Every control is a Flutter widget above the view
///
/// Flutter's gesture arena does not hand gestures to a macOS platform view at
/// all, so a control drawn inside or behind the video is invisible to a tap and
/// silent in a widget test. The stack's order is therefore load-bearing rather
/// than cosmetic, and the test asserts the view sits at index 0.
///
/// ### The chrome recedes
///
/// `DESIGN.md:441-442` sets the one rule this surface already had: the chrome
/// is transparent over video and never uses a scrim heavier than 40 percent,
/// which is the ceiling Plex holds and the reason their artwork stays legible
/// underneath. `Scrim.bottom` and `Scrim.flat` are the two the component
/// offers that fit; there is no `Scrim.top`, and adding one would mean editing
/// a component this screen has no business editing.
///
/// ### Remote activation is prepared, not live
///
/// Every control is a `WAnchor` carrying `focus:ring-2 focus:ring-focus-ring`,
/// which is universal across this app's other eleven layouts, and `WAnchor`
/// answers `ActivateIntent`, so `Enter`, `Space` and the D-pad centre reach an
/// `onTap`. That binding exists only in an **unreleased** Wind commit: the app
/// constrains `fluttersdk_wind: ^1.5.0` and every published version through
/// 1.5.2 has none of it, so what CI builds has the ring and not the
/// activation. Developing against `pubspec_overrides.yaml` would show it
/// working and ship it absent.
class PlaybackLayout extends StatelessWidget {
  /// What this screen reads and drives.
  final PlaybackFacade playback;

  /// Where the back affordance goes, defaulting to popping the route.
  ///
  /// A seam rather than a hardcoded `MagicRoute.back()`, because `MagicRouter`
  /// throws `Router not initialized` without a `MaterialApp.router` above it
  /// and a widget test has none. On the one screen where a control that
  /// silently does nothing is invisible to the user (gestures never reach the
  /// platform view, so there is no fallback path), an untestable control is
  /// the wrong trade.
  final VoidCallback? onBack;

  /// Creates the playback surface over [playback].
  const PlaybackLayout({super.key, required this.playback, this.onBack});

  @override
  Widget build(BuildContext context) {
    final Channel? channel = playback.channel;
    final ProviderFault? fault = playback.fault;

    return WDiv(
      className: 'w-full h-full bg-surface',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Index 0 deliberately: everything else must sit above it to be
          // tappable at all.
          WatchoolsPlayerView(onReady: (int viewId) => playback.attach(PlaybackSurface(platformViewId: viewId))),
          Scrim.flat,
          Scrim.bottom,
          // Above the fault branch rather than inside it. Both browse screens
          // once rendered a focusable widget in one parent when a list had
          // results and another when it did not, and every keystroke after the
          // first went nowhere. The way out never moves.
          Positioned(top: PageGutter.value, left: PageGutter.value, child: _back()),
          if (fault != null)
            Positioned(
              left: PageGutter.value,
              right: PageGutter.value,
              bottom: PageGutter.value,
              child: Align(
                alignment: Alignment.centerLeft,
                // `onRetry` means "make the request again", which here is the
                // load rather than the pause: for `unreachable` and `evicted`
                // there is no core to toggle, and toggling one that never
                // opened is not a retry.
                child: ProviderNotice(
                  fault: fault,
                  onRetry: () => playback.retry(),
                  onOpenSettings: () => MagicRoute.to('/'),
                ),
              ),
            )
          else
            Positioned(
              left: PageGutter.value,
              right: PageGutter.value,
              bottom: PageGutter.value,
              child: Align(alignment: Alignment.centerLeft, child: _chrome(channel)),
            ),
        ],
      ),
    );
  }

  /// The way out, which also releases the connection.
  ///
  /// Stops rather than merely navigating, because the measured account allows
  /// **one** connection and a screen that walks away from an open core is the
  /// reason the next device in the house cannot watch.
  Widget _back() => WAnchor(
    onTap: () async {
      await playback.stop();
      (onBack ?? MagicRoute.back)();
    },
    semanticLabel: 'Geri',
    child: const WDiv(
      className: '''
        size-10 rounded-full items-center justify-center
        bg-scrim-strong text-fg
        hover:bg-scrim
        focus:ring-2 focus:ring-focus-ring
      ''',
      child: WIcon(Icons.arrow_back, className: 'text-base'),
    ),
  );

  /// The channel, its programme, the health line and the pause control.
  Widget _chrome(Channel? channel) {
    final String? health = _healthLine();

    return WDiv(
      className: 'flex flex-col gap-3',
      children: <Widget>[
        if (playback.unplayable)
          const WText('Bu kanal oynatılamıyor', className: 'text-base font-semibold text-fg')
        else if (channel != null) ...<Widget>[
          WText(channel.name, className: 'text-xl font-semibold text-fg'),
          if (channel.schedule.isNotEmpty) WText(channel.schedule.first.title, className: 'text-sm text-fg-muted'),
        ],
        if (health != null) WText(health, className: 'text-sm text-fg-muted'),
        WDiv(className: 'flex flex-row items-center gap-3', children: <Widget>[_pause()]),
      ],
    );
  }

  /// Pause, or resume when the engine says the stream is paused.
  ///
  /// The label follows the engine's verdict rather than a flag of this
  /// widget's, so a pause the user triggered on a remote and a pause the app
  /// triggered read the same.
  Widget _pause() {
    final bool paused = playback.health == PlaybackHealth.paused;

    return WAnchor(
      onTap: () => playback.togglePause(),
      semanticLabel: paused ? 'Devam et' : 'Duraklat',
      child: WDiv(
        className: '''
          size-12 rounded-full items-center justify-center
          bg-scrim-strong text-fg
          hover:bg-scrim
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(paused ? Icons.play_arrow : Icons.pause, className: 'text-lg'),
      ),
    );
  }

  /// One line about the health, or null when there is nothing to say.
  ///
  /// The three that are not `playing` are told apart rather than folded into
  /// one, because they are three different things to a viewer.
  /// `notPresenting` is an asleep display and recovers the moment the screen
  /// wakes, which is why it says so rather than reporting a fault; this
  /// project once filed that state as a code regression and had to retract it.
  /// `starving` is a live window's ordinary wait, measured at about eight
  /// seconds in every twenty four. `stalled` is a freeze that outlasted the
  /// twelve second grace and may never recover, and it is the only one of the
  /// three that is a problem.
  String? _healthLine() => switch (playback.health) {
    PlaybackHealth.notPresenting => 'Ekran uyandığında geri gelir',
    PlaybackHealth.starving => 'Arabelleğe alınıyor',
    PlaybackHealth.stalled => 'Yayın durdu',
    PlaybackHealth.idle || PlaybackHealth.playing || PlaybackHealth.paused => null,
  };
}
