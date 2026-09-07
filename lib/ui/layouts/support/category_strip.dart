import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/guide_controller.dart';

/// The horizontal category strip.
///
/// It scrolls rather than wrapping. A provider sends dozens of `group-title`
/// values with no ordering and no consistent naming, so a strip that tries to
/// fit them all pushes the content off the screen.
@immutable
class CategoryStrip extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Underline the selected item (a tab bar) or fill it (a pill row). Both
  /// idioms are in the wild; the pill reads better without a rule under it.
  final bool pills;

  /// Whether the strip sits over artwork rather than over a surface.
  ///
  /// A pill in `bg-surface-container` disappears against a bright still and
  /// muddies a dark one, so over artwork the resting fill becomes a scrim. Only
  /// meaningful together with [pills].
  final bool onScrim;

  /// Creates the [CategoryStrip].
  const CategoryStrip({super.key, required this.controller, this.pills = false, this.onScrim = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: pills ? 52 : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pills ? 24 : 16),
        children: <Widget>[
          for (final String group in controller.groups) _item(group),
        ],
      ),
    );
  }

  Widget _item(String group) {
    return WAnchor(
      onTap: () => controller.selectGroup(group),
      child: WDiv(
        className: pills && onScrim
            ? '''
              flex flex-row items-center gap-1.5
              mr-2 my-2 px-4 rounded-full h-9
              bg-scrim
              text-sm font-semibold text-fg
              hover:bg-scrim-strong
              focus:ring-2 focus:ring-focus-ring
              selected:bg-inverse selected:text-on-inverse
            '''
            : pills
            ? '''
              flex flex-row items-center gap-1.5
              mr-2 my-2 px-4 rounded-full h-9
              bg-surface-container
              text-sm font-semibold text-fg-muted
              hover:bg-surface-container-high hover:text-fg
              focus:ring-2 focus:ring-focus-ring
              selected:bg-inverse selected:text-on-inverse
            '''
            : '''
              flex flex-row items-center gap-1.5
              mr-6 py-3 border-b-2 border-transparent
              text-sm font-semibold text-fg-disabled
              hover:text-fg-muted
              focus:ring-2 focus:ring-focus-ring
              selected:text-fg selected:border-color-epg-now
            ''',
        states: controller.group == group ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (group == 'Favoriler') const WIcon(Icons.star_rounded, className: 'text-sm'),
          WText(group, className: 'text-sm font-semibold'),
        ],
      ),
    );
  }
}
