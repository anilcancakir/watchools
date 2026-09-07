import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'favourite_button.recipe.dart';

/// The star that adds a channel or a title to favourites.
///
/// Favourites are the only thing that makes a ten thousand channel line-up
/// usable, so the action appears on every surface that shows a channel. Four
/// shapes, one behaviour: the shape follows what surrounds it, and the state,
/// the glyph and the label never diverge between them.
///
/// The label says `Favoride` when it is on, not `Favori`. A toggle whose label
/// never changes leaves the user reading the glyph to find out what happened.
@immutable
class FavouriteButton extends StatelessWidget {
  /// Whether the subject is currently starred.
  final bool starred;

  /// Recipe shape axis: `bare`, `circle`, `pill` or `badge`.
  final String shape;

  /// What the semantic label calls the subject, e.g. `TRT 1`.
  final String subject;

  /// Fired when the star is picked.
  final VoidCallback? onToggle;

  /// Appended to the box slot, for spacing at the call site.
  final String? className;

  /// Creates a [FavouriteButton].
  const FavouriteButton({
    super.key,
    required this.starred,
    required this.subject,
    this.shape = 'bare',
    this.onToggle,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = favouriteButtonRecipe()(variants: <String, String?>{'shape': shape});
    final String box = slots['box'] ?? '';
    final Set<String> states = starred ? const <String>{'starred'} : const <String>{};

    return WAnchor(
      onTap: onToggle,
      semanticLabel: starred ? '$subject favorilerden çıkar' : '$subject favorilere ekle',
      child: WDiv(
        className: className == null ? box : '$box $className',
        states: states,
        children: <Widget>[
          WIcon(
            starred ? Icons.star_rounded : Icons.star_outline_rounded,
            className: slots['icon'] ?? '',
            states: states,
          ),
          if (shape == 'pill')
            WText(
              starred ? 'Favoride' : 'Favori',
              className: slots['label'] ?? '',
              states: states,
            ),
        ],
      ),
    );
  }
}
