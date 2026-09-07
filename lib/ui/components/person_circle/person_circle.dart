import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../artwork/index.dart';

/// A person in a cast rail: circular portrait, name, role.
///
/// The circle is doing work beyond decoration. Every other piece of artwork in
/// this app is a rectangle whose aspect ratio says what it is (2:3 a title,
/// 16:9 a moment, 1:1 a brand), so a circle is unambiguously a person without
/// a label saying so.
///
/// The fallback is the reason this is a component. Plex's cast rails are full
/// of people with no portrait, and it renders a grey circle carrying their
/// initials rather than dropping them from the row: a cast list missing its
/// unphotographed half is worse than one with grey circles in it, because the
/// user cannot tell that anything is missing.
@immutable
class PersonCircle extends StatelessWidget {
  /// The person's name.
  final String name;

  /// What they did: a character name, `Yönetmen`, `Senarist`.
  final String role;

  /// The portrait, or null. Null is the common case.
  final String? imageUrl;

  /// Creates a [PersonCircle].
  const PersonCircle({super.key, required this.name, required this.role, this.imageUrl});

  /// The rendered diameter, so the decode can be sized to the slot.
  static const double _edge = 88;

  /// The rendered height of the whole cell.
  ///
  /// The circle, two `gap-2` rules, a name clamped to two lines and a role on
  /// one. Exposed because a `Rail` states its cell height before the cell is
  /// laid out; the first version of this let the caller guess 148 and every
  /// cast rail overflowed by seven pixels.
  static const double height = _edge + 8 + 34 + 8 + 18;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col items-center gap-2 w-[104px] shrink-0',
      children: <Widget>[
        WDiv(
          className: 'size-[88px] rounded-full overflow-hidden bg-surface-container items-center justify-center',
          child: Artwork(
            src: imageUrl,
            slotWidth: _edge,
            fallback: WText(_initials(name), className: 'text-lg font-semibold text-fg-muted'),
          ),
        ),
        WDiv(
          className: 'w-full h-[34px] overflow-hidden',
          child: WText(name, className: 'text-xs font-medium text-fg text-center line-clamp-2'),
        ),
        WText(role, className: 'text-xs text-fg-muted text-center line-clamp-1'),
      ],
    );
  }

  static String _initials(String name) {
    final List<String> words = name.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return _upper(words.first.substring(0, 1));

    return _upper(words[0][0] + words[1][0]);
  }

  static String _upper(String value) => value.replaceAll('i', 'İ').toUpperCase();
}
