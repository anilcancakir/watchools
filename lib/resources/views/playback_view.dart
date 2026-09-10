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
/// session and no panel behind it. `PlaybackController` satisfies that
/// interface structurally; nothing here adapts it.
class PlaybackView extends MagicStatefulView<PlaybackController> {
  /// Creates the [PlaybackView].
  const PlaybackView({super.key});

  @override
  State<PlaybackView> createState() => _PlaybackViewState();
}

class _PlaybackViewState extends MagicStatefulViewState<PlaybackController, PlaybackView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: PlaybackLayout(playback: controller));
  }
}
