import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// The line above a rail or a grid.
///
/// Two parts, and the second one is the part every in-house design forgets.
/// Netflix titles its rows with sentences that have a point of view (`Because
/// you watched Narcos`), and Plex puts a small grey line under each one saying
/// where the row came from (`Discover`). Together they answer the two questions
/// a row raises: what is this, and why am I being shown it.
///
/// For this product the source line carries something the references do not
/// have to: which provider a row came from, once more than one is configured.
@immutable
class SectionHeader extends StatelessWidget {
  /// The editorial title. A sentence, not a taxonomy label.
  final String title;

  /// Where the row came from. Null when the answer is uninteresting, which is
  /// most of the time on a single-provider setup.
  final String? source;

  /// A control that belongs to this section: a count, a sort, a pair of arrows.
  final Widget? trailing;

  /// Appended to the outer row, for spacing at the call site.
  final String? className;

  /// Creates a [SectionHeader].
  const SectionHeader({super.key, required this.title, this.source, this.trailing, this.className});

  @override
  Widget build(BuildContext context) {
    const String base = 'flex flex-row items-end justify-between gap-4 w-full';

    return WDiv(
      className: className == null ? base : '$base $className',
      children: <Widget>[
        WDiv(
          className: 'flex flex-col gap-0.5 flex-1',
          children: <Widget>[
            WText(title, className: 'text-xl font-semibold text-fg line-clamp-1'),
            if (source != null) WText(source!, className: 'text-xs text-fg-muted line-clamp-1'),
          ],
        ),
        // `shrink-0` on the trailing cell, because a clipping row hands every
        // sibling without it a `Flexible(flex: 1)` and the control would then
        // compete with the title for the same width. Recorded as defect 1 in
        // `.ac/research/ecosystem-defects.md`.
        if (trailing != null) WDiv(className: 'shrink-0', child: trailing),
      ],
    );
  }
}
