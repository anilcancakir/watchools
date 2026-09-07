import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the PlayProgress component.
///
/// Two slots, because the bar is two boxes: an unfilled track that has to
/// darken arbitrary artwork, and a fill that has to be the accent colour.
///
/// The height is an axis of three fixed steps rather than a `double`
/// interpolated into the className. Wind parses a className once per unique
/// string and caches it, so a widget that builds `h-[${height}px]` from a
/// caller's variable turns a cache hit into a cache miss for every distinct
/// value that ever reaches it.
WindSlotRecipe playProgressRecipe() {
  return const WindSlotRecipe(
    slots: {'track': 'w-full overflow-hidden bg-scrim-strong', 'fill': ''},
    variants: {
      'size': {
        'sm': {'track': 'h-[2px]', 'fill': 'h-[2px]'},
        'md': {'track': 'h-[3px]', 'fill': 'h-[3px]'},
        'lg': {'track': 'h-[4px]', 'fill': 'h-[4px]'},
      },
      'tone': {
        'primary': {'fill': 'bg-primary'},
        'live': {'fill': 'bg-live'},
      },
    },
    defaultVariants: {'size': 'md', 'tone': 'primary'},
  );
}
