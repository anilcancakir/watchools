import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../ui/layouts/curtain_layout.dart';

/// The title screen: one movie or one series.
///
/// A route rather than an overlay, which the previous pass got wrong. All three
/// references treat a title's page as a page, and the reason is mechanical: a
/// browser's back button and a remote's back key both have to land somewhere,
/// and an overlay held in controller state gives them nowhere to land.
///
/// It reads the same [LibraryController] the catalogue does, because it has no
/// state of its own: it shows whatever the catalogue last selected. A second
/// controller would be a second answer to "which title" and one of them would
/// eventually be wrong.
class TitleView extends MagicStatefulView<LibraryController> {
  /// Creates the [TitleView].
  const TitleView({super.key});

  @override
  State<TitleView> createState() => _TitleViewState();
}

class _TitleViewState extends MagicStatefulViewState<LibraryController, TitleView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: CurtainLayout(controller: controller));
  }
}
