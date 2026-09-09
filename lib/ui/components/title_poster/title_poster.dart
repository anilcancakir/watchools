import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/title_item.dart';
import '../artwork/index.dart';
import '../count_badge/index.dart';
import '../favourite_button/index.dart';
import '../play_progress/index.dart';
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

  /// The rendered width of each size, so the decode can be sized to the slot.
  /// Mirrors the recipe; the two have to move together.
  static const Map<String, double> _edges = <String, double>{'sm': 124, 'md': 168, 'lg': 220};

  /// Whether this is the entry the detail surface is showing.
  final bool selected;

  /// Fired when the poster is picked.
  final VoidCallback? onTap;

  /// Fired when the star is picked.
  final VoidCallback? onToggleFavourite;

  /// Appended to the box slot, for a caller that owns the width.
  ///
  /// A grid cell decides its own width, so the recipe's `w-[168px]` has to be
  /// overridable. The recipe only appends, and Wind's per-family last-class
  /// wins, so `w-full` here beats the recipe's fixed width at parse time.
  final String? className;

  /// Creates a [TitlePoster].
  const TitlePoster({
    super.key,
    required this.title,
    this.size = 'md',
    this.selected = false,
    this.onTap,
    this.onToggleFavourite,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = titlePosterRecipe()(variants: <String, String?>{'size': size});
    final Set<String> states = selected ? const <String>{'selected'} : const <String>{};
    final String box = slots['box'] ?? '';

    return WDiv(
      className: className == null ? box : '$box $className',
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
                  // The year only when there is one: a provider entry has
                  // none, and `Kanal D 0` reads worse than `Kanal D`.
                  semanticLabel: title.year > 0 ? '${title.name} ${title.year}' : title.name,
                  child: Artwork(src: title.posterUrl, fallback: _blank(), slotWidth: _edges[size]),
                ),
                if (title.progress > 0.03 && title.progress < 0.92)
                  Positioned(left: 0, right: 0, bottom: 0, child: PlayProgress(value: title.progress)),
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
                // The unwatched count, not the season count. A square badge
                // holding a bare number is the one shape in this system that is
                // not rounded, so it reads as a different class of object
                // without needing a word beside it, and the number it holds is
                // the one that decides whether the card is worth opening.
                if (title.unwatchedCount != null)
                  Positioned(left: 0, top: 0, child: CountBadge(label: '${title.unwatchedCount}')),
              ],
            ),
          ),
        ),
        WDiv(
          className: slots['caption'] ?? '',
          children: <Widget>[
            WText(title.name, className: slots['name'] ?? ''),
            WText(_meta(), className: slots['meta'] ?? ''),
          ],
        ),
      ],
    );
  }

  /// The rendered height of a card [width] pixels wide.
  ///
  /// A 2:3 frame, the `gap-2` between the frame and the caption, and the
  /// caption's own fixed height. Exposed because a `Rail` and a
  /// `SliverGridDelegate` both have to state the cell height up front, and the
  /// only place that can know it is here.
  static double heightFor(double width) => width * 3 / 2 + 8 + 40;

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
        WText(title.name, className: 'text-sm font-bold text-fg-muted text-center line-clamp-4'),
        WIcon(
          title.isSeries ? Icons.subscriptions_outlined : Icons.movie_outlined,
          className: 'text-sm text-fg-disabled mt-2',
        ),
      ],
    );
  }

  /// Year, length, and the rating, each only when the provider sent it.
  ///
  /// Composed from the parts rather than interpolated, because a provider's
  /// `get_vod_streams` entry carries no year and no runtime and
  /// [TitleItem.metaLabel] is therefore empty far more often than a fixture
  /// suggested. A caption of `0 · 0 dk · ★ 7,5` claims two things the provider
  /// never said.
  String _meta() {
    final String? rating = title.ratingLabel;

    return <String>[if (title.metaLabel.isNotEmpty) title.metaLabel, if (rating != null) '★ $rating'].join(' · ');
  }
}
