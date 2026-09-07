import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the FavouriteButton component.
///
/// Two slots, because the box and the glyph scale independently: a bare star in
/// a dense row wants no background at all, while the same action beside a play
/// button wants the weight of a pill.
///
/// `starred:` is the state, not a second variant. The starred styling has to
/// survive alongside `hover:` and `focus:`, and only the state system composes
/// prefixes; a variant axis would have to re-declare every combination.
WindSlotRecipe favouriteButtonRecipe() {
  return const WindSlotRecipe(
    slots: <String, String>{
      'box': '''
        flex flex-row items-center justify-center shrink-0
        text-fg-disabled
        hover:text-fg
        focus:ring-2 focus:ring-focus-ring
        starred:text-primary
      ''',
      'icon': '',
      'label': 'font-semibold',
    },
    variants: <String, Map<String, Map<String, String>>>{
      'shape': <String, Map<String, String>>{
        // A star and nothing else. For a list row, where a background per row
        // is a second grid the eye has to read past.
        'bare': <String, String>{
          'box': 'size-11 rounded-lg gap-0 hover:bg-surface-container',
          'icon': 'text-lg',
        },
        // A filled circle. For a bar or a strip, where the action sits among
        // other round controls.
        'circle': <String, String>{
          'box': 'size-11 rounded-full bg-surface-container-high',
          'icon': 'text-lg',
        },
        // A labelled pill. For a hero or a detail pane, where the action is
        // one of two or three and the word carries the state.
        'pill': <String, String>{
          'box': 'h-11 px-5 rounded-full gap-2 bg-surface-container-high',
          'icon': 'text-lg',
          'label': 'text-sm font-semibold',
        },
        // A small badge over artwork. For a tile or a card, where the star is
        // an indicator first and a target second.
        'badge': <String, String>{
          'box': 'size-7 rounded-full bg-scrim',
          'icon': 'text-sm',
        },
      },
    },
    defaultVariants: <String, String>{'shape': 'bare'},
  );
}
