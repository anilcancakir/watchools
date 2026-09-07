import 'package:flutter/widgets.dart';

/// The one distance between a page's content and its edge.
///
/// Every screen in this app sits inside the same container, and the left edge
/// of a search field, a category pill, a section heading, a grid cell and a
/// list row all line up on it. That sounds obvious and it was not true: the
/// nine directions were written with gutters of 12, 16, 20, 24 and 32 pixels
/// depending on which file the widget happened to live in, so a toolbar and the
/// strip directly beneath it started at different places on the same screen.
///
/// The value is 24. It was chosen by being the one already used by the rails,
/// which are the widest surfaces and the hardest to move.
///
/// Three forms because three APIs need it, and they cannot share a
/// representation. A className cannot carry an interpolated Dart value without
/// turning Wind's parse cache hit into a miss, so [x] is written out and the
/// three have to move together.
abstract final class PageGutter {
  /// The gutter in logical pixels, for a Flutter padding.
  static const double value = 24;

  /// The horizontal gutter as a Wind className fragment.
  ///
  /// `px-6` is `6 * 4 = 24` on Wind's default four pixel scale.
  static const String x = 'px-6';

  /// The vertical distance between two blocks of a page, as a className.
  ///
  /// The same number as the horizontal gutter, and for the same reason: a page
  /// whose vertical rhythm and horizontal rhythm disagree reads as two designs
  /// stacked. The directions were written with 20, 28, 32 and 36 in different
  /// files, and the visible result was a category strip sitting eight pixels
  /// under the hero above it and thirty six above the heading below it.
  static const String top = 'pt-6';

  /// The same distance as a widget, for a sliver list that cannot take padding.
  static const Widget gap = SizedBox(height: value);

  /// The distance WITHIN a block, as a className.
  ///
  /// Deliberately smaller than [top], and the difference is what makes a page
  /// scan: more space between groups than inside them. A title and the line
  /// under it are one group; a title block and the section beneath it are two.
  /// Anything set to this value should be inside one group, and anything set to
  /// [top] should be between two.
  static const String inner = 'pt-4';

  /// Horizontal insets, for a `ListView` or a `GridView`.
  static const EdgeInsets horizontal = EdgeInsets.symmetric(horizontal: value);

  /// Horizontal insets plus room at the bottom for the floating switcher.
  ///
  /// The switcher is scaffolding and goes when a direction is chosen, but a
  /// scrollable whose last row sits under it cannot be reached at all, which
  /// would hide the very thing being compared.
  static const EdgeInsets scrollable = EdgeInsets.fromLTRB(value, value, value, 96);

  /// The height of a horizontal chip strip.
  ///
  /// Exactly the chip's own height, so the strip's box carries no hidden
  /// margin of its own and the page above and below it owns all the spacing.
  /// The chips are `h-9`; a taller box would centre them inside it and put an
  /// invisible half-gap on each side that nothing else in the page shares.
  static const double stripHeight = 36;
}
