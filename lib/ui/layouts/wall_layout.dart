import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/title_poster/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/title_detail.dart';

/// Catalogue direction one: the poster wall.
///
/// Plex's Modern layout and the tvOS TV app. A uniform 2:3 grid, and on a wide
/// screen the detail surface sits beside it so picking a poster never leaves
/// the grid. It is the layout artwork was invented for.
///
/// What it optimises: recognition. When a viewer half-remembers a film, a
/// poster gets them there faster than any amount of text, and the measured
/// finding behind that is the one about nuanced options rather than broad
/// ones: artwork earns its space when the label is ambiguous and the image
/// disambiguates it.
///
/// What it sacrifices: it needs the artwork to exist. A provider sends what it
/// sends, several titles in the fixture have no poster at all on purpose, and
/// the grid's answer for those is the name set in the frame. Judge this layout
/// on those cards rather than on the ones with key art.
@immutable
class WallLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [WallLayout].
  const WallLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Below `xl` the detail is a screen rather than a pane: a pane plus a grid
    // leaves the grid two columns wide, which is a list with pictures rather
    // than a wall.
    final bool split = wScreenIs(context, 'xl');
    final bool wide = wScreenIs(context, 'md');

    if (!split && controller.detailOpen) {
      return TitleDetail(controller: controller, wide: wide, dismissible: true);
    }

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 flex flex-col min-w-0',
          children: <Widget>[
            LibraryToolbar(controller: controller, wide: wide),
            LibraryCategories(controller: controller),
            WDiv(className: 'flex-1 min-w-0', child: _grid(split)),
          ],
        ),
        if (split)
          WDiv(
            className: 'w-[520px] shrink-0 border-l border-color-border-subtle',
            child: TitleDetail(controller: controller, wide: false),
          ),
      ],
    );
  }

  Widget _grid(bool split) {
    if (controller.matches.isEmpty) return LibraryEmpty(controller: controller);

    return GridView.builder(
      primary: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // 200 rather than a fixed column count, so the wall reflows instead of
        // deciding how wide the window should be. Apple's own unfocused grid
        // widths bracket this: 217 at seven columns, 184 at eight.
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        // 2:3 poster plus two label lines. Getting this wrong is what makes a
        // poster grid clip its own captions.
        childAspectRatio: 0.52,
      ),
      itemCount: controller.matches.length,
      itemBuilder: (BuildContext context, int index) {
        final TitleItem title = controller.matches[index];

        return TitlePoster(
          title: title,
          selected: identical(title, controller.selected),
          onTap: () => split ? controller.select(title) : controller.openDetail(title),
          onToggleFavourite: () => controller.toggleFavourite(title),
        );
      },
    );
  }
}
