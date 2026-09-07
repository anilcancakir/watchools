import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the TitlePoster component.
///
/// One axis, `size`, and it sets the width only: the box holds a 2:3
/// `AspectRatio`, so a width is the whole geometry and letting the two drift
/// apart is how a poster grid ends up ragged.
///
/// The widths follow Apple's own unfocused grid table, which is the only
/// published set of numbers for this: 320 at five columns, 260 at six, 217 at
/// seven, 184 at eight. `md` sits between six and seven, `sm` below eight.
WindSlotRecipe titlePosterRecipe() {
  return const WindSlotRecipe(
    slots: <String, String>{
      'box': '''
        shrink-0 flex flex-col gap-2
        focus:ring-2 focus:ring-focus-ring
      ''',
      'frame': '''
        w-full rounded-lg overflow-hidden
        bg-surface-container
        selected:bg-surface-container-high
      ''',
      // The caption is a fixed block, and that is what makes
      // `TitlePoster.heightFor` exact. A rail and a grid both have to state a
      // cell height before the cell is laid out, so a caption that sizes to its
      // own content means the caller is guessing: the first version of this
      // guessed eight pixels short and every card in every rail overflowed.
      'caption': 'flex flex-col w-full h-[40px] overflow-hidden',
      'name': 'text-sm font-semibold text-fg truncate',
      'meta': 'text-xs text-fg-disabled truncate',
    },
    variants: <String, Map<String, Map<String, String>>>{
      'size': <String, Map<String, String>>{
        'sm': <String, String>{'box': 'w-[124px]'},
        'md': <String, String>{'box': 'w-[168px]'},
        'lg': <String, String>{'box': 'w-[220px]'},
      },
    },
    defaultVariants: <String, String>{'size': 'md'},
  );
}
