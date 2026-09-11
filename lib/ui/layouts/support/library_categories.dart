import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';
import 'page_gutter.dart';

/// The catalogue category strip.
///
/// Two of the tabs are ours rather than the provider's and they carry an icon
/// so they read as a different kind of thing: `İzlemeye devam et` is device
/// state and `Favoriler` is user state, while everything after them is the
/// provider's own unordered, inconsistently spelled `category_name`.
@immutable
class LibraryCategories extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [LibraryCategories].
  const LibraryCategories({super.key, required this.controller});

  static const Map<String, IconData> _icons = <String, IconData>{
    'İzlemeye devam et': Icons.history_rounded,
    'Favoriler': Icons.star_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // Scoped to the two fields it reads, neither of which is the query. See
    // `CategoryStrip`, which records the same reasoning in full and includes
    // the list in the selected value for the same future.
    return MagicSelector<LibraryController, (List<String>, String)>(
      controller: controller,
      selector: (LibraryController c) => (c.categories, c.category),
      builder: ((List<String>, String) state) => _strip(state.$1, selected: state.$2),
    );
  }

  /// The scrolling row of pills, built from its arguments and nothing else.
  Widget _strip(List<String> categories, {required String selected}) {
    // Exactly the chip's own height, so the page above and below owns all the
    // spacing. See `PageGutter.stripHeight`.
    return SizedBox(
      height: PageGutter.stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: PageGutter.horizontal,
        itemCount: categories.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (BuildContext context, int index) => _item(categories[index], selected: selected),
      ),
    );
  }

  Widget _item(String category, {required String selected}) {
    final IconData? icon = _icons[category];

    return WAnchor(
      onTap: () => controller.selectCategory(category),
      semanticLabel: '$category kategorisi',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-1.5
          mr-2 px-4 rounded-full h-9
          bg-surface-container
          text-sm font-semibold text-fg-muted
          hover:bg-surface-container-high hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-inverse selected:text-on-inverse
        ''',
        states: selected == category ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (icon != null) WIcon(icon, className: 'text-sm'),
          WText(category, className: 'text-sm font-semibold'),
        ],
      ),
    );
  }
}
