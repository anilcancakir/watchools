import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/title_item.dart';
import '../favourite_button/index.dart';
import 'title_poster.recipe.dart';

/// One catalogue entry as a 2:3 poster with its name and metadata under it.
///
/// 2:3 is the ratio for a title whose artwork carries its own name, and the
/// convention is that such a card needs no text label. This one is labelled
/// anyway, and that is the concession this product has to make: a provider's
/// artwork is not bespoke key art, a large share of a real catalogue arrives
/// with no poster at all, and a wall of unlabelled boxes is unreadable the
/// moment either is true.
///
/// The missing-poster state is designed rather than blank. It shows the name
/// set in the frame, so the card still says which title it is and the grid
/// keeps its rhythm instead of developing holes.
@immutable
class TitlePoster extends StatelessWidget {
  /// The title to render.
  final TitleItem title;

  /// Recipe size axis: `sm`, `md` or `lg`.
  final String size;

  /// Whether this is the entry the detail surface is showing.
  final bool selected;

  /// Fired when the poster is picked.
  final VoidCallback? onTap;

  /// Fired when the star is picked.
  final VoidCallback? onToggleFavourite;

  /// Creates a [TitlePoster].
  const TitlePoster({
    super.key,
    required this.title,
    this.size = 'md',
    this.selected = false,
    this.onTap,
    this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = titlePosterRecipe()(variants: <String, String?>{'size': size});
    final Set<String> states = selected ? const <String>{'selected'} : const <String>{};

    return WDiv(
      className: slots['box'] ?? '',
      states: states,
      children: <Widget>[
        WDiv(
          className: slots['frame'] ?? '',
          states: states,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // The anchor wraps only the artwork, so the star beside it stays
                // its own semantics node and its own target.
                WAnchor(
                  onTap: onTap,
                  semanticLabel: '${title.name} ${title.year}',
                  child: title.posterUrl == null
                      ? _blank()
                      : Image.network(
                          title.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _blank(),
                        ),
                ),
                if (title.progress > 0.03 && title.progress < 0.92)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: WDiv(
                      className: 'h-1 bg-scrim-strong',
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: title.progress,
                        child: const WDiv(className: 'h-1 bg-primary'),
                      ),
                    ),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: FavouriteButton(
                    starred: title.favourite,
                    subject: title.name,
                    shape: 'badge',
                    onToggle: onToggleFavourite,
                  ),
                ),
                if (title.isSeries)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: WDiv(
                      className: 'px-2 h-6 rounded-full bg-scrim flex items-center',
                      child: WText(title.lengthLabel, className: 'text-[10px] font-bold text-fg'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        WText(title.name, className: slots['name'] ?? ''),
        WText(_meta(), className: slots['meta'] ?? ''),
      ],
    );
  }

  /// The name set in the frame, for a title the provider sent no poster for.
  ///
  /// Centred and clamped to four lines rather than truncated: this IS the
  /// artwork for these entries, and a long Turkish title cut off mid-word tells
  /// the viewer less than the same title wrapped.
  Widget _blank() {
    return WDiv(
      className: '''
        size-full p-3
        flex flex-col items-center justify-center
        bg-surface-container-high
      ''',
      children: <Widget>[
        WText(title.name, className: 'text-sm font-bold text-fg-muted text-center n-4'),
        WIcon(
          title.isSeries ? Icons.subscriptions_outlined : Icons.movie_outlined,
          className: 'text-sm text-fg-disabled mt-2',
        ),
      ],
    );
  }

  /// Year, length, and the rating when there is one.
  String _meta() {
    final String? rating = title.ratingLabel;
    final String head = '${title.year} · ${title.lengthLabel}';

    return rating == null ? head : '$head · ★ $rating';
  }
}
