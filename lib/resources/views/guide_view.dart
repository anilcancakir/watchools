import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../ui/layouts/now_layout.dart';
import '../../ui/layouts/time_layout.dart';

/// The live television screen.
///
/// It hosts two layouts rather than one, and that is a product decision rather
/// than an unfinished bake-off. `Şimdi` answers "what is on", `Zaman` answers
/// "what is on at nine", and a live line-up is the one surface where those are
/// different questions: a catalogue has no equivalent of the second, because
/// everything in it is available at every moment.
///
/// Both read one [GuideController], so the query, the category and the
/// selection survive the switch. The control that does the switching is part of
/// each layout's toolbar rather than an overlay here, so it sits inside the
/// page container and cannot cover the content behind it.
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
    return Scaffold(
      body: switch (controller.mode) {
        GuideMode.now => NowLayout(controller: controller),
        GuideMode.grid => TimeLayout(controller: controller),
      },
    );
  }
}
