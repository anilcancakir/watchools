import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../ui/layouts/layout_switcher.dart';
import '../../ui/layouts/marquee_layout.dart';
import '../../ui/layouts/mosaic_layout.dart';
import '../../ui/layouts/signal_layout.dart';
import '../../ui/layouts/stage_layout.dart';

/// The line-up screen.
///
/// It hosts four competing layouts rather than one, because the product
/// decision underneath is not styling: it is what this screen is for. Each
/// layout answers that differently and they are on screen side by side so the
/// answer can be chosen by looking rather than by describing.
///
/// The switcher is scaffolding. It goes with the layouts that lose.
///
/// The data is a fixture. There is no protocol layer yet, and this screen
/// exists to settle the design language before the Xtream client lands.
class GuideView extends MagicStatefulView<GuideController> {
  /// Creates the [GuideView].
  const GuideView({super.key});

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends MagicStatefulViewState<GuideController, GuideView> {
  @override
  Widget build(BuildContext context) {
    // A Flutter `Stack`, not a `WDiv` carrying `relative`. A multi-child WDiv
    // composes a Column whatever its position class says, so the switcher's
    // `Positioned` landed in a Flex and threw ParentDataWidget.
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _layout()),
          LayoutSwitcher(controller: controller),
        ],
      ),
    );
  }

  Widget _layout() => switch (controller.layout) {
    BrowseLayout.signal => SignalLayout(controller: controller),
    BrowseLayout.marquee => MarqueeLayout(controller: controller),
    BrowseLayout.stage => StageLayout(controller: controller),
    BrowseLayout.mosaic => MosaicLayout(controller: controller),
  };
}
