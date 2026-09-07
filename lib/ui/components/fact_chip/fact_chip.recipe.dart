import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the FactChip component.
///
/// The neutral half of the badge vocabulary: resolution, codec, audio layout.
/// Deliberately colourless and deliberately tighter than a status badge, 2px
/// against 4px, so six of them in a row read as one texture rather than six
/// objects competing with the one badge that actually matters.
WindRecipe factChipRecipe() {
  return const WindRecipe(
    base: '''
      rounded-sm px-1.5 py-0.5
      bg-fact text-fact
      text-xs font-medium
    ''',
  );
}
