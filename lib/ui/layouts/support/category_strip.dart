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
    // The strip reads two things and neither of them is the query, so a
    // keystroke has nothing to say to it. Without the selector it rebuilt on
    // every character along with the rest of the view, because `refreshUI`
    // notifies every listener and the view answers with one `setState`.
    //
    // The list is in the selected value as well as the selection, and it is
    // there for the day the fixture is replaced: a provider's groups arrive
    // with the playlist, and a strip keyed only on the selection would still be
    // drawing the empty pre-load list when they landed. It is a cached
    // `late final` rather than a fresh list per call, so identity holds and so
    // does the cache.
    return MagicSelector<GuideController, (List<String>, String)>(
      controller: controller,
      selector: (GuideController c) => (c.groups, c.group),
      builder: ((List<String>, String) state) => _strip(state.$1, selected: state.$2),
    );
  }

  /// The scrolling row of pills.
  ///
  /// Takes both inputs as arguments rather than reading them back off the
  /// controller. A cached subtree cannot see anything its builder captured, so
  /// passing them is what keeps the purity [MagicSelector] documents visible at
  /// a glance instead of true by coincidence.
  Widget _strip(List<String> groups, {required String selected}) {
    // Exactly the chip's own height. The box used to be 52 against a 36 pixel
    // chip, so it carried eight pixels of invisible margin above and below that
    // nothing else on the page shared, and the strip sat closer to the hero
    // above it than to the heading below it.
    //
    // `ListView.builder`, not `ListView(children: [...])`, and the reason is
    // narrower than it first looks. The list form does NOT build every chip:
    // `SliverChildListDelegate.build` is `children[index]`
    // (`scroll_delegate.dart:772`), so only mounted indices are ever built, and
    // the measured `WDiv` build count was identical either way.
    //
    // What it does is ALLOCATE a widget object per group every time this
    // method runs. That used to be every controller notify; with the selector
    // above it is every category change. Measured below the harness's noise
    // floor at this scale either way, and kept because it is the shape that
    // does not degrade when a provider sends eight hundred groups.
    return SizedBox(
      height: PageGutter.stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: PageGutter.horizontal,
        itemCount: groups.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (BuildContext context, int index) => _item(groups[index], selected: selected),
      ),
    );
  }

  Widget _item(String group, {required String selected}) {
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
        states: selected == group ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (group == 'Favoriler') const WIcon(Icons.star_rounded, className: 'text-sm'),
          WText(group, className: 'text-sm font-semibold'),
        ],
      ),
    );
  }
}
