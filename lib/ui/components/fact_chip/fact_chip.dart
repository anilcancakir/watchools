import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'fact_chip.recipe.dart';

/// A technical fact about a stream: `1080p`, `H.265`, `5.1`.
///
/// Never coloured. Colour is reserved for what a channel is *doing*, and a row
/// that colours its facts as well spends the signal it needs for the one badge
/// that matters.
@immutable
class FactChip extends StatelessWidget {
  /// The fact itself, already formatted.
  final String label;

  /// Optional className that overrides the recipe output entirely.
  final String? className;

  /// Creates a [FactChip].
  const FactChip({super.key, required this.label, this.className});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: className ?? factChipRecipe()(),
      child: WText(label, className: 'text-xs font-medium'),
    );
  }
}
