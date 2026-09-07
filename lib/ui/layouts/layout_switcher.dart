import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';

/// The floating control that swaps one competing layout for another.
///
/// Deliberately unlike the product: pinned to the bottom, floating over the
/// design rather than built into it, so that nothing about it reads as part of
/// what is being judged. It goes with the layouts that lose.
@immutable
class LayoutSwitcher extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [LayoutSwitcher].
  const LayoutSwitcher({super.key, required this.controller});

  /// The label and the one-line claim each layout is making.
  static const Map<BrowseLayout, (String, String)> _options = <BrowseLayout, (String, String)>{
    BrowseLayout.signal: ('Sinyal', 'Yoğun liste ve zaman ekseni'),
    BrowseLayout.marquee: ('Vitrin', 'Tam ekran afiş, yatay raylar'),
    BrowseLayout.stage: ('Sahne', 'Sessiz liste, tek büyük önizleme'),
    BrowseLayout.mosaic: ('Mozaik', 'Kanal amblemi ızgarası'),
  };

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      // Left-aligned below `sm`, centred above it. Centred on a 414 pixel
      // screen the pill covers most of the width and sat directly on top of
      // the mosaic layout's action strip, so a tap aimed at the favourite star
      // hit the switcher instead. Scaffolding must not occlude the thing it
      // exists to let you judge.
      child: WDiv(
        className: 'flex flex-row justify-start sm:justify-center px-2 sm:px-4',
        child: WDiv(
          className: '''
            flex flex-row items-center gap-1 p-1.5 rounded-full
            bg-surface-container-high
            border border-color-border
            shadow-lg
          ''',
          children: <Widget>[
            for (final MapEntry<BrowseLayout, (String, String)> option in _options.entries)
              _button(option.key, option.value.$1, option.value.$2),
          ],
        ),
      ),
    );
  }

  Widget _button(BrowseLayout layout, String label, String claim) {
    return WAnchor(
      onTap: () => controller.showLayout(layout),
      semanticLabel: '$label: $claim',
      child: WDiv(
        className: '''
          px-4 h-9 rounded-full
          flex items-center
          text-xs font-bold text-fact
          hover:bg-fact
          focus:ring-2 focus:ring-focus-ring
          selected:bg-primary selected:text-on-primary
        ''',
        states: controller.layout == layout ? const <String>{'selected'} : const <String>{},
        child: WText(label, className: 'text-xs font-bold'),
      ),
    );
  }
}
