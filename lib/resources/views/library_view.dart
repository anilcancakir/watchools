import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../ui/layouts/collection_layout.dart';
import '../../ui/layouts/direction_switcher.dart';
import '../../ui/layouts/shelf_layout.dart';
import '../../ui/layouts/showcase_layout.dart';

/// The catalogue screen.
///
/// Three competing directions, for the same reason the live screen has three:
/// the decision underneath is what a catalogue is for. A shop window ends the
/// decision, a shelf helps the owner arrange what they have, and a collection
/// screen argues about which titles matter. They cannot all be right and only
/// one of them ships.
///
/// The switcher is scaffolding. It goes with the directions that lose.
class LibraryView extends MagicStatefulView<LibraryController> {
  /// Creates the [LibraryView].
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends MagicStatefulViewState<LibraryController, LibraryView> {
  static const List<DirectionOption> _options = <DirectionOption>[
    DirectionOption(name: 'Vitrin', summary: 'Tam ekran afiş ve editoryal raylar'),
    DirectionOption(name: 'Raf', summary: 'Kenar çubuğu, kart boyutu ve sıralama kontrolü'),
    DirectionOption(name: 'Koleksiyon', summary: 'Karışık boyutlu karolar ve kaynak rayı'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _body()),
          DirectionSwitcher(
            options: _options,
            selected: controller.direction.index,
            onSelect: (int index) => controller.showDirection(LibraryDirection.values[index]),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (controller.direction) {
    LibraryDirection.showcase => ShowcaseLayout(controller: controller),
    LibraryDirection.shelf => ShelfLayout(controller: controller),
    LibraryDirection.collection => CollectionLayout(controller: controller),
  };
}
