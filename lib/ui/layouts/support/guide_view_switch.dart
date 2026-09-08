import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/guide_controller.dart';

/// The control that swaps the line-up between its two views.
///
/// A product control rather than the scaffolding it replaced. The floating pill
/// that used to carry the competing directions sat over the content it let you
/// compare and covered a favourite button by half a pixel; a control that ships
/// belongs in the page's own chrome, at the end of the toolbar line, where the
/// catalogue already puts its scope tabs.
///
/// Deliberately the same shape as `LibraryToolbar`'s scope switch: a pill group
/// on `surface-container`, one filled segment, `h-8 px-3`. Both are "same data,
/// different cut", so the two screens should not teach the user two idioms for
/// one idea.
@immutable
class GuideViewSwitch extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [GuideViewSwitch].
  const GuideViewSwitch({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-row gap-1 p-1 rounded-full shrink-0 bg-surface-container',
      children: <Widget>[_segment(GuideMode.now, 'Şimdi'), _segment(GuideMode.grid, 'Zaman')],
    );
  }

  Widget _segment(GuideMode mode, String label) {
    return WAnchor(
      onTap: () => controller.showMode(mode),
      semanticLabel: '$label görünümü',
      child: WDiv(
        className: '''
          px-3 h-8 rounded-full
          flex items-center
          text-xs font-semibold text-fg-disabled
          hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-inverse selected:text-on-inverse
        ''',
        states: controller.mode == mode ? const <String>{'selected'} : const <String>{},
        child: WText(label, className: 'text-xs font-semibold'),
      ),
    );
  }
}
