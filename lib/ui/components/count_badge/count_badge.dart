import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// A number in the corner of a piece of artwork: unwatched episodes, channels
/// in a group, items in a collection.
///
/// It is a corner badge and not a line of metadata because Plex made that
/// choice deliberately and it survives a wall of forty posters: the count sits
/// where the eye already is (on the image) instead of where it is not (in the
/// caption two lines down). Apple does the same thing with rank, at a size the
/// caption could never carry.
///
/// Square-cornered on purpose. Everything else in this system that holds a word
/// is rounded, so the one thing holding a bare number reads as a different
/// class of object at a glance.
@immutable
class CountBadge extends StatelessWidget {
  /// The number, already formatted. A string rather than an int so a caller can
  /// pass `99+` without this component owning a truncation rule.
  final String label;

  /// Appended to the recipe output, for placement at the call site.
  final String? className;

  /// Creates a [CountBadge].
  const CountBadge({super.key, required this.label, this.className});

  /// The badge, with the scrim it needs to sit on arbitrary artwork.
  static const String _base = 'bg-scrim-strong px-1.5 py-0.5 min-w-[24px] items-center justify-center';

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: className == null ? _base : '$_base $className',
      // `text-on-inverse` is wrong here: this sits on a black scrim in both
      // modes, so the label is white in both modes and does not flip.
      child: WText(label, className: 'text-xs font-bold text-[#FFFFFF] dark:text-[#FFFFFF]'),
    );
  }
}
