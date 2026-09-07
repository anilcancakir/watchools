import 'package:flutter/widgets.dart';

/// A horizontal row of cards that bleeds off the right edge.
///
/// The bleed is the point. Netflix and Apple both let the last card be cut by
/// the viewport rather than fitting a whole number of cards, because a row that
/// ends flush looks finished and a row that ends mid-card does not. Plex
/// achieves the same thing with explicit arrows; the clip is cheaper and works
/// on a remote, where there is no cursor to reveal an arrow to.
///
/// A `ListView.builder` rather than a Wind `overflow-x-auto`, and this is not a
/// preference either: Wind's overflow utilities compose a
/// `SingleChildScrollView`, which builds every child. A provider line-up runs
/// to five figures and one un-virtualised rail is enough to drop frames on a
/// television. The gap is recorded in `CLAUDE.md`.
@immutable
class Rail extends StatelessWidget {
  /// How tall the row is. The cards size themselves to it.
  final double height;

  /// How wide one card is, so the list can compute its scroll extent without
  /// laying a card out.
  ///
  /// Every caller already knows this number: it is the same `width` it hands
  /// the tile it builds. Passing it here turns the list from a `SliverList`,
  /// which must lay out each child to learn its extent, into a
  /// `SliverFixedExtentList`, which does not. `prototypeItem` would also work
  /// and is strictly worse here: it mounts and lays out one hidden extra card
  /// to learn a number the caller already has.
  ///
  /// It has to be the CELL's width rather than any inner dimension, and the
  /// caller has to mean it. `sliver_fixed_extent_list.dart:270` hands the child
  /// `constraints.asBoxConstraints(minExtent: extent, maxExtent: extent)`, a
  /// TIGHT main-axis constraint: a cell handed less than it renders is squeezed
  /// silently, and `shrink-0` cannot argue with a tight constraint. The cast
  /// rail shipped exactly that bug for one review cycle, passing a circle's 88
  /// pixel diameter for a cell that renders at 104.
  final double itemWidth;

  /// How many cards.
  final int itemCount;

  /// Builds card [index].
  final IndexedWidgetBuilder itemBuilder;

  /// Gap between cards, in logical pixels.
  final double gap;

  /// The page gutter. Applied on the leading edge only: a trailing gutter would
  /// give the last card somewhere to stop, which is the thing the bleed exists
  /// to prevent.
  ///
  /// It has to equal the app's page gutter or a rail's first card sits at a
  /// different left edge from the heading above it. The value lives in
  /// `PageGutter`; the default here mirrors it rather than importing it,
  /// because a component in `ui/components` reaching into `ui/layouts/support`
  /// would invert the dependency. The two move together.
  final double gutter;

  /// Creates a [Rail].
  const Rail({
    super.key,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 12,
    this.gutter = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: gutter),
        itemCount: itemCount,
        // The gap rides on the item rather than on a separator widget.
        //
        // A `ListView.separated` gives every separator its own delegate child
        // slot, so the sliver mounts, keeps alive and repaint-bounds each one as
        // if it were a card. Measured on the catalogue's vertical session at
        // scale 5000: `KeyedSubtree` 234 to 150 and `RepaintBoundary` 234 to
        // 150, over a run that drew MORE frames than the one before it.
        itemExtent: itemWidth + gap,
        // No card in this app keeps itself alive, so the `AutomaticKeepAlive`
        // the delegate adds by default (`scroll_delegate.dart:368`) is a widget
        // per card that can never do anything. Measured on the same session:
        // `AutomaticKeepAlive` and `_SelectionKeepAlive` both 234 to zero.
        //
        // It is also the one mechanism that could pin a whole rail, and its
        // scroll position, alive after it scrolled out of the vertical list.
        addAutomaticKeepAlives: false,
        itemBuilder: (BuildContext context, int index) => Padding(
          padding: EdgeInsets.only(right: gap),
          child: itemBuilder(context, index),
        ),
      ),
    );
  }
}
