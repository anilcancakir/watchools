import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the EpisodeRow component.
///
/// One axis, `density`. A series page in a two pane layout has room for a still
/// and a synopsis; the same list inside a shelf or on a phone has room for a
/// code, a title and a runtime. Both are the same row rather than two
/// components, because the difference is what is shown and not what it means.
WindSlotRecipe episodeRowRecipe() {
  return const WindSlotRecipe(
    slots: <String, String>{
      'box': '''
        flex flex-row items-center gap-3
        rounded-lg
        hover:bg-surface-container
        selected:bg-surface-container-high
      ''',
      'still': 'shrink-0 rounded-md overflow-hidden bg-surface-container-high',
      'code': 'shrink-0 text-xs font-semibold text-fg-disabled',
      'title': 'text-sm font-semibold text-fg truncate',
      'synopsis': 'text-xs text-fg-muted line-clamp-2',
      'runtime': 'shrink-0 text-xs text-fg-disabled',
    },
    variants: <String, Map<String, Map<String, String>>>{
      'density': <String, Map<String, String>>{
        // Code, title, runtime. No still, no synopsis.
        'compact': <String, String>{'box': 'h-12 px-3'},
        // A 16:9 still at 128 wide, plus two lines of synopsis.
        'full': <String, String>{'box': 'p-3'},
      },
    },
    defaultVariants: <String, String>{'density': 'compact'},
  );
}
