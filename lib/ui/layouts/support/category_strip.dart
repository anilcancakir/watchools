import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/guide_controller.dart';
import 'page_gutter.dart';

/// The horizontal category strip on the live screen.
///
/// It scrolls rather than wrapping. A provider sends dozens of `group-title`
/// values with no ordering and no consistent naming, so a strip that tries to
/// fit them all pushes the content off the screen.
///
/// Pills, and the same pills the catalogue's [LibraryCategories] draws: same
/// height, same radius, same selected fill. It used to be pills in one live
/// view and underlined tabs in the other, which was defensible while they were
/// competing designs and is not now that one switch flips between them. The
/// same control changing shape mid-screen is the "two designs stacked" failure
/// the page container exists to prevent.
@immutable
class CategoryStrip extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [CategoryStrip].
  const CategoryStrip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Exactly the chip's own height. The box used to be 52 against a 36 pixel
    // chip, so it carried eight pixels of invisible margin above and below that
    // nothing else on the page shared, and the strip sat closer to the hero
    // above it than to the heading below it.
    final List<String> groups = controller.groups;

    // `ListView.builder`, not `ListView(children: [...])`, and the reason is
    // narrower than it first looks. The list form does NOT build every chip:
    // `SliverChildListDelegate.build` is `children[index]`
    // (`scroll_delegate.dart:772`), so only mounted indices are ever built, and
    // the measured `WDiv` build count was identical either way.
    //
    // What it does is ALLOCATE a widget object per group every time this
    // method runs, and this method runs on every controller notify, which means
    // every keystroke. At two hundred groups that is two hundred allocations
    // per character for thirteen chips anyone can see. The builder allocates
    // the thirteen.
    //
    // Below the harness's noise floor at this scale. Kept because it is the
    // shape that does not degrade when a provider sends eight hundred groups.
    return SizedBox(
      height: PageGutter.stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: PageGutter.horizontal,
        itemCount: groups.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (BuildContext context, int index) => _item(groups[index]),
      ),
    );
  }

  Widget _item(String group) {
    return WAnchor(
      onTap: () => controller.selectGroup(group),
      // The only WAnchor in the app that relied on a child WText to supply its
      // label. It worked, and it is what made the end-to-end walk's
      // `button "Spor"` matcher fragile: the label was a side effect rather
      // than a contract.
      semanticLabel: '$group kategorisi',
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
        states: controller.group == group ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (group == 'Favoriler') const WIcon(Icons.star_rounded, className: 'text-sm'),
          WText(group, className: 'text-sm font-semibold'),
        ],
      ),
    );
  }
}
