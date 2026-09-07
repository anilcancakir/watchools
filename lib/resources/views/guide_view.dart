import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../ui/layouts/direction_switcher.dart';
import '../../ui/layouts/now_layout.dart';
import '../../ui/layouts/time_layout.dart';
import '../../ui/layouts/tower_layout.dart';

/// The live television screen.
///
/// It hosts three competing directions rather than one, because the decision
/// underneath is not styling: it is what this screen is for. Each direction
/// descends from a different reference and answers that differently, and they
/// are reachable side by side so the answer can be chosen by looking.
///
/// The switcher is scaffolding. It goes with the directions that lose.
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
  static const List<DirectionOption> _options = <DirectionOption>[
    DirectionOption(name: 'Şimdi', summary: 'Canlı önizleme ve editoryal raylar'),
    DirectionOption(name: 'Kule', summary: 'Kenar çubuğu, yoğun liste ve künye paneli'),
    DirectionOption(name: 'Zaman', summary: 'Gerçek yayın ızgarası ve zaman ekseni'),
  ];

  @override
  Widget build(BuildContext context) {
    // A Flutter `Stack`, not a `WDiv` carrying `relative`. A multi-child WDiv
    // composes a Column whatever its position class says, so the switcher's
    // `Positioned` landed in a Flex and threw ParentDataWidget.
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _body()),
          DirectionSwitcher(
            options: _options,
            selected: controller.direction.index,
            onSelect: (int index) => controller.showDirection(GuideDirection.values[index]),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (controller.direction) {
    GuideDirection.now => NowLayout(controller: controller),
    GuideDirection.tower => TowerLayout(controller: controller),
    GuideDirection.time => TimeLayout(controller: controller),
  };
}
