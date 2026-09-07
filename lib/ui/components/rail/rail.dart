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
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 12,
    this.gutter = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: gutter),
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: itemBuilder,
      ),
    );
  }
}
