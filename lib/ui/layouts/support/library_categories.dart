import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';

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
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[for (final String category in controller.categories) _item(category)],
      ),
    );
  }

  Widget _item(String category) {
    final IconData? icon = _icons[category];

    return WAnchor(
      onTap: () => controller.selectCategory(category),
      semanticLabel: '$category kategorisi',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-1.5
          mr-2 my-2 px-4 rounded-full h-9
          bg-surface-container
          text-sm font-semibold text-fg-muted
          hover:bg-surface-container-high hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-inverse selected:text-on-inverse
        ''',
        states: controller.category == category ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (icon != null) WIcon(icon, className: 'text-sm'),
          WText(category, className: 'text-sm font-semibold'),
        ],
      ),
    );
  }
}
