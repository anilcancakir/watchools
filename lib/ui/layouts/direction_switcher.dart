import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// One option on the switcher.
@immutable
class DirectionOption {
  /// The short name, shown on the pill.
  final String name;

  /// What the direction is for, read aloud and shown on hover.
  final String summary;

  /// Creates a [DirectionOption].
  const DirectionOption({required this.name, required this.summary});
}

/// The floating control that swaps one competing direction for another.
///
/// Scaffolding, and tested anyway for one reason: it is the only way to reach
/// six of the nine directions, so a break here hides two thirds of the work
/// behind a screen that still looks fine. It goes when a direction is chosen,
/// along with the directions that lose.
///
/// `justify-start sm:justify-center` rather than a plain centre: centred on a
/// phone it sat on top of the content it was meant to let you compare.
@immutable
class DirectionSwitcher extends StatelessWidget {
  /// The options, in the order they should be offered.
  final List<DirectionOption> options;

  /// Which one is on show.
  final int selected;

  /// Fired with the index of the option picked.
  final ValueChanged<int> onSelect;

  /// Creates a [DirectionSwitcher].
  const DirectionSwitcher({super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: WDiv(
        className: 'flex flex-row justify-start sm:justify-center w-full px-4',
        child: WDiv(
          className: '''
            flex flex-row items-center gap-1 shrink-0
            p-1 rounded-full
            bg-surface-container
            border border-color-border-subtle
            shadow-lg
          ''',
          children: <Widget>[for (int i = 0; i < options.length; i++) _pill(options[i], i)],
        ),
      ),
    );
  }

  Widget _pill(DirectionOption option, int index) {
    return WAnchor(
      onTap: () => onSelect(index),
      // Name and summary both, because the pill shows only the name and the
      // end-to-end walk reads this label to prove which direction it landed on.
      semanticLabel: '${option.name}: ${option.summary}',
      child: WDiv(
        className: '''
          flex flex-row items-center px-4 h-9 rounded-full
          text-sm font-semibold text-fg-muted
          hover:bg-surface-container-high hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-inverse selected:text-on-inverse
        ''',
        states: selected == index ? const <String>{'selected'} : const <String>{},
        child: WText(option.name, className: 'text-sm font-semibold'),
      ),
    );
  }
}
