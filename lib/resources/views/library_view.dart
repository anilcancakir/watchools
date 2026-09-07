import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../ui/layouts/showcase_layout.dart';

/// The catalogue screen.
///
/// One layout, unlike the live screen, and the asymmetry is the point rather
/// than an oversight. A catalogue has no second question to answer: every title
/// in it is available at every moment, so a "what is on at nine" cut has
/// nothing to cut. The scope tabs and the category strip already carry the only
/// two axes a viewer actually browses along.
class LibraryView extends MagicStatefulView<LibraryController> {
  /// Creates the [LibraryView].
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends MagicStatefulViewState<LibraryController, LibraryView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: ShowcaseLayout(controller: controller));
  }
}
