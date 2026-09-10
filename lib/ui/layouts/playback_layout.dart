import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:watchools_player/watchools_player.dart';

import '../../app/controllers/playback_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/provider_fault.dart';
import '../../app/playback/playback_engine.dart';
import '../components/provider_notice/provider_notice.dart';
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
/// ### The chrome recedes, and no scrim covers the picture
///
/// `DESIGN.md:441-442` sets the rule this surface answers to: the chrome is
/// transparent over video, because the reason Plex's artwork stays legible is
/// that nothing washes it. So nothing here does. The chrome is content-width
/// panels in two corners and the frame is untouched everywhere else.
///
/// The first version reached for `Scrim.flat` and `Scrim.bottom` full-bleed.
/// Both are built for a still behind a text block rather than for live video:
/// `flat` bottoms out at 85 percent black (`scrim.dart:35`) and `bottom` at
/// the fully opaque surface colour (`scrim.dart:67`), so the two stacked
/// painted the lower third of the picture out completely. Wind exposes no
/// gradient stops, so a lighter ramp is not something this file can build, and
/// `scrim.dart` is a shared component this screen has no business reweighting
/// for its own case.
///
/// The panels carry `bg-scrim-strong`, which is 72 percent
/// (`watchools_status_tokens.dart:109`). That is over the 40 percent the same
/// `DESIGN.md` line names, and the conflict is real rather than an oversight
/// here: the theme ships exactly two scrim weights, 45 and 72, and its own
/// comment records 72 as what a line of text needs to clear AA over a frame
/// whose brightness we do not control. One of the two numbers is wrong and
/// only a design call settles which. Bounded is the part this file can honour,
/// and it is the part that keeps the picture.
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
          // No full-bleed scrim here, deliberately; the doc block above is why.
          //
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
                  onRetry: () => _run(playback.retry),
                  // The same destination the other four layouts send this to,
                  // and it stops first. `expired` is the one fault whose panel
                  // shows this instead of a retry, so the user is leaving to
                  // replace a credential: walking off an open core would hold
                  // the account's single connection slot while they do it.
                  onOpenSettings: () => _run(() async {
                    await playback.stop();
                    MagicRoute.to('/saglayici');
                  }),
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

  /// Runs a playback command from a control, and reports what it throws.
  ///
  /// Every control on this screen calls something that reaches the native
  /// side, and `WAnchor.onTap` is a `VoidCallback`, so the future it returns
  /// belongs to nobody: a `PlatformException` out of the plugin becomes an
  /// unhandled async error, which is a red console dump in debug and silence
  /// in release. Reproduced on the running app by tapping pause with no core.
  ///
  /// Logged rather than turned into a [ProviderFault], because a failed pause
  /// is not the provider failing and that vocabulary has no member for it. The
  /// message is already redacted: every plugin call in `MpvPlaybackEngine`
  /// goes through its `_native` door, which rebuilds the exception with the
  /// message cleaned.
  Future<void> _run(Future<void> Function() command) async {
    try {
      await command();
    } on PlatformException catch (failure) {
      Log.error('playback control failed: ${failure.code} ${failure.message ?? ''}');
    }
  }

  /// The way out, which also releases the connection.
  ///
  /// Stops rather than merely navigating, because the measured account allows
  /// **one** connection and a screen that walks away from an open core is the
  /// reason the next device in the house cannot watch.
  Widget _back() => WAnchor(
    onTap: () => _run(() async {
      await playback.stop();
      (onBack ?? MagicRoute.back)();
    }),
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
      // Content-width and rounded, so it reads as a panel over the picture
      // rather than a band across it. `Align` above keeps it from claiming the
      // row, which is the other half of bounded: a `w-full` here would put a
      // 72 percent strip across the frame and undo the whole correction.
      className: 'flex flex-col gap-3 p-4 rounded-xl bg-scrim-strong',
      children: <Widget>[
        // The channel is named on both paths, and that is the point of the
        // controller keeping it through a refusal: "this channel cannot be
        // played" with no channel on screen leaves the user guessing which
        // one. The programme line goes, because a channel that cannot open has
        // nothing to say about what is on it.
        if (channel != null) WText(channel.name, className: 'text-xl font-semibold text-fg'),
        if (playback.unplayable)
          const WText('Bu kanal oynatılamıyor', className: 'text-base font-semibold text-fg')
        else if (channel != null && channel.schedule.isNotEmpty)
          WText(channel.schedule.first.title, className: 'text-sm text-fg-muted'),
        if (health != null) WText(health, className: 'text-sm text-fg-muted'),
        // No transport controls when there is nothing to control. An
        // unplayable channel opened no core, so pause would reach the native
        // side with no core to pause and come back a `PlatformException` the
        // user cannot act on. A control that cannot work is worse than no
        // control on the one screen where a silent no-op is invisible.
        if (!playback.unplayable) WDiv(className: 'flex flex-row items-center gap-3', children: <Widget>[_pause()]),
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
      onTap: () => _run(playback.togglePause),
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
