import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the ChannelMark component.
///
/// One axis, `size`, because the mark is the same object everywhere and only
/// its scale changes: 32 in a dense row, 40 in a tile, 56 in a card, 72 in a
/// hero. Both the box and the initials move together, which is why they share a
/// variant rather than being passed separately.
WindRecipe channelMarkRecipe() {
  return const WindRecipe(
    base: '''
      shrink-0 overflow-hidden
      flex items-center justify-center
      bg-surface-container-high
    ''',
    variants: <String, Map<String, String>>{
      'size': <String, String>{
        'sm': 'size-8 rounded text-[10px]',
        'md': 'size-10 rounded-md text-xs',
        'lg': 'size-14 rounded-lg text-sm',
        'xl': 'size-[72px] rounded-xl text-lg',
      },
    },
    defaultVariants: <String, String>{'size': 'md'},
  );
}
