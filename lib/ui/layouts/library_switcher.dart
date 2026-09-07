import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';

/// The floating control that swaps one competing catalogue layout for another.
///
/// The same scaffolding as the line-up's, and it goes the same way once a
/// direction is chosen. Left-aligned below `sm`, because centred on a phone it
/// sits on top of whatever the layout put at the bottom of the screen.
@immutable
class LibrarySwitcher extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [LibrarySwitcher].
  const LibrarySwitcher({super.key, required this.controller});

  /// The label and the one-line claim each layout is making.
  static const Map<LibraryLayout, (String, String)> _options = <LibraryLayout, (String, String)>{
    LibraryLayout.wall: ('Duvar', 'Afiş ızgarası, yanında detay'),
    LibraryLayout.ledger: ('Defter', 'Yoğun tablo, sütunlarla'),
    LibraryLayout.showcase: ('Sergi', 'Tam ekran afiş, yatay raflar'),
  };

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
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
            for (final MapEntry<LibraryLayout, (String, String)> option in _options.entries)
              _button(option.key, option.value.$1, option.value.$2),
          ],
        ),
      ),
    );
  }

  Widget _button(LibraryLayout layout, String label, String claim) {
    return WAnchor(
      onTap: () => controller.showLayout(layout),
      semanticLabel: '$label: $claim',
      child: WDiv(
        className: '''
          px-4 h-9 rounded-full
          flex items-center
          text-xs font-bold text-fg-muted
          hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-primary selected:text-on-primary
        ''',
        states: controller.layout == layout ? const <String>{'selected'} : const <String>{},
        child: WText(label, className: 'text-xs font-bold'),
      ),
    );
  }
}
