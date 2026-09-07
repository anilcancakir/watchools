import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../ui/layouts/ledger_layout.dart';
import '../../ui/layouts/library_switcher.dart';
import '../../ui/layouts/showcase_layout.dart';
import '../../ui/layouts/wall_layout.dart';

/// The catalogue screen: films and series.
///
/// One screen for both, with a scope switch, rather than a Films page and a
/// Series page. A provider sends them through separate endpoints, but the
/// viewer does not think in endpoints, and a search that covers only half the
/// library is a search nobody trusts. Where the two genuinely differ is below
/// the fold on the detail surface, which is where a series grows its seasons.
///
/// It hosts three competing layouts for the same reason the line-up hosts four:
/// the decision underneath is what a catalogue entry is, and that is settled by
/// looking rather than by describing.
///
/// The data is a fixture. There is no protocol layer yet.
class LibraryView extends MagicStatefulView<LibraryController> {
  /// Creates the [LibraryView].
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends MagicStatefulViewState<LibraryController, LibraryView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _layout()),
          LibrarySwitcher(controller: controller),
        ],
      ),
    );
  }

  Widget _layout() => switch (controller.layout) {
    LibraryLayout.wall => WallLayout(controller: controller),
    LibraryLayout.ledger => LedgerLayout(controller: controller),
    LibraryLayout.showcase => ShowcaseLayout(controller: controller),
  };
}
