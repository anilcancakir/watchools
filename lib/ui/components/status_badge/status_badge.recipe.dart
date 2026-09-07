import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the StatusBadge component.
///
/// State gets colour. This is the half of the badge vocabulary that is allowed
/// to shout, and there are only ever three of them on screen, so each one still
/// reads as a signal rather than as decoration.
///
/// The `soft` tone is the default because a channel grid shows many badges at
/// once; `solid` is for the one card the user is looking at.
WindRecipe statusBadgeRecipe() {
  return const WindRecipe(
    base: '''
      flex flex-row items-center gap-1
      rounded px-2 py-0.5
      text-xs font-semibold
    ''',
    variants: {
      'status': {
        'live': 'bg-live-soft text-live-soft-foreground',
        'recording': 'bg-recording-soft text-recording-soft-foreground',
        'catchup': 'bg-catchup-soft text-catchup-soft-foreground',
      },
      'tone': {'soft': '', 'solid': 'text-on-primary'},
    },
    compoundVariants: [
      // A solid badge drops the soft background for the full-strength tone.
      // Declared per status rather than as one rule, because the recipe matches
      // on exact pairs and there is no wildcard.
      WindCompoundVariant(conditions: {'status': 'live', 'tone': 'solid'}, className: 'bg-live'),
      WindCompoundVariant(conditions: {'status': 'recording', 'tone': 'solid'}, className: 'bg-recording'),
      WindCompoundVariant(conditions: {'status': 'catchup', 'tone': 'solid'}, className: 'bg-catchup'),
    ],
    defaultVariants: {'status': 'live', 'tone': 'soft'},
  );
}
