import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/playback_controller.dart';
import '../../ui/layouts/playback_layout.dart';

/// The playback screen.
///
/// The thin mounting half, the same split the other three screens use: this
/// resolves the controller and `PlaybackLayout` does the work. It lives here
/// rather than in `lib/ui/layouts/` because `lib/resources/views/` is excluded
/// from the CI coverage denominator, and a widget whose only job is to hand a
/// controller to a layout has nothing worth covering.
///
/// The layout reads `PlaybackFacade` rather than this controller's concrete
/// type, so a widget test drives the screen with no container, no provider
/// session and no panel behind it. `PlaybackController` declares
/// `implements PlaybackFacade`; nothing here adapts it.
class PlaybackView extends MagicStatefulView<PlaybackController> {
  /// Creates the [PlaybackView].
  const PlaybackView({super.key});

  @override
  State<PlaybackView> createState() => _PlaybackViewState();
}

class _PlaybackViewState extends MagicStatefulViewState<PlaybackController, PlaybackView> {
  /// Tells the controller the surface is going away.
  ///
  /// The one piece of behaviour in this otherwise thin file, and it has to live
  /// here: this state's subtree owns the platform view, so its teardown is the
  /// moment the view id stops being valid. The native side prunes the view and
  /// stops the core by itself (`WatchoolsPlayerPlugin.swift:186-191`) and says
  /// nothing about either, so without this the controller would keep believing
  /// it holds a live surface. `PlaybackController.detach` records what follows
  /// from that.
  ///
  /// This covers the route pop and **not** every way playback can end. An
  /// earlier version of this line claimed it was the only signal Dart gets,
  /// which is wrong in a direction that matters on the mobile targets:
  /// backgrounding the app does not dispose a `State`, so on Android and iOS
  /// the core, the account's single connection slot and the wakelock all
  /// survive the user pressing Home. There is no `WidgetsBindingObserver`
  /// anywhere in this app yet, and when one arrives it belongs with the engine
  /// rather than with this screen, for the same reason the wakelock does: it
  /// follows the core's lifetime, not a route's.
  ///
  /// Unawaited because `dispose` is synchronous. What it awaits is the engine's
  /// stop, and the local bookkeeping it fixes is set before the first `await`.
  @override
  void dispose() {
    unawaited(controller.detach());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: PlaybackLayout(playback: controller));
  }
}
