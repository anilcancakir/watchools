import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../ui/layouts/curtain_layout.dart';
import '../../ui/layouts/direction_switcher.dart';
import '../../ui/layouts/record_layout.dart';
import '../../ui/layouts/sheet_layout.dart';

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
  static const List<DirectionOption> _options = <DirectionOption>[
    DirectionOption(name: 'Künye', summary: 'Afiş solda, etiketli olgular sağda'),
    DirectionOption(name: 'Perde', summary: 'Sinematik, sezon ve bölüm iki sütun'),
    DirectionOption(name: 'Sayfa', summary: 'Mobil düzen, teknik künye ön planda'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _body()),
          DirectionSwitcher(
            options: _options,
            selected: controller.detail.index,
            onSelect: (int index) => controller.showDetail(DetailDirection.values[index]),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (controller.detail) {
    DetailDirection.record => RecordLayout(controller: controller),
    DetailDirection.curtain => CurtainLayout(controller: controller),
    DetailDirection.sheet => SheetLayout(controller: controller),
  };
}
