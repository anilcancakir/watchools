import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// The permanent left rail.
///
/// It stays on the left in every layout that has one. Netflix moved its TV
/// navigation to a top strip in May 2025 and was still being called unusable a
/// year later; Plex made the same move and reverted it in August 2026.
@immutable
class NavRail extends StatelessWidget {
  /// Whether the rail shows its labels beside the icons.
  ///
  /// Icons alone are ambiguous, which is why Netflix expands its rail on
  /// focus. A layout that has the width can afford the words outright.
  final bool expanded;

  /// Creates the [NavRail].
  const NavRail({super.key, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: expanded
          ? '''
            flex flex-col gap-1 shrink-0
            w-[200px] h-full py-5 px-3
            bg-surface-container
          '''
          : '''
            flex flex-col items-center gap-1 shrink-0
            w-16 h-full py-5
            bg-surface-container
            border-r border-color-border-subtle
          ''',
      children: <Widget>[
        _wordmark(),
        _item(Icons.search_outlined, 'Ara'),
        _item(Icons.live_tv_outlined, 'Canlı', route: '/'),
        _item(Icons.video_library_outlined, 'Kütüphane', route: '/kutuphane'),
        _item(Icons.grid_view_outlined, 'Kategoriler'),
        _item(Icons.star_outline_rounded, 'Favoriler'),
        const WDiv(className: 'flex-1'),
        _item(Icons.settings_outlined, 'Ayarlar'),
      ],
    );
  }

  Widget _wordmark() {
    const Widget glyph = WDiv(
      className: '''
        size-9 shrink-0 rounded-lg
        bg-primary
        flex items-center justify-center
      ''',
      child: WIcon(Icons.play_arrow_rounded, className: 'text-on-primary'),
    );

    if (!expanded) return const WDiv(className: 'mb-4', child: glyph);

    // The label takes the remainder and truncates rather than pushing the row
    // past the rail. Defensive rather than a fix: the four overflows that
    // prompted it turned out to be `flutter_test`'s square-glyph font inflating
    // every string by half again (see `test/support/screen.dart`), and in
    // Schibsted Grotesk none of them happens. Kept because a rail label is one
    // string away from being long enough for real, and truncating costs
    // nothing.
    return const WDiv(
      className: 'flex flex-row items-center gap-2 mb-6 px-1',
      children: <Widget>[
        glyph,
        WDiv(
          className: 'flex-1 min-w-0',
          child: WText('Watchools', className: 'text-sm font-bold text-fg truncate'),
        ),
      ],
    );
  }

  /// One rail item.
  ///
  /// [route] is what makes the rail navigation rather than decoration. An item
  /// without one is a destination that does not exist yet and says so by doing
  /// nothing, which is honest; an item that routes is `selected` when the
  /// current location is its own, read from the router rather than passed in,
  /// so the rail cannot disagree with the screen behind it.
  Widget _item(IconData icon, String label, {String? route}) {
    final bool selected = route != null && route == MagicRouter.instance.currentLocation;

    return WAnchor(
      onTap: route == null ? null : () => MagicRoute.to(route),
      semanticLabel: label,
      child: WDiv(
        className: expanded
            ? '''
              flex flex-row items-center gap-3
              h-11 px-3 rounded-lg
              text-fg-disabled
              hover:bg-surface-container-high hover:text-fg
              focus:ring-2 focus:ring-focus-ring
              selected:bg-surface-container-high selected:text-primary
            '''
            : '''
              size-11 rounded-lg
              flex items-center justify-center
              text-fg-disabled
              hover:bg-surface-container-high hover:text-fg
              focus:ring-2 focus:ring-focus-ring
              selected:bg-surface-container-high selected:text-primary
            ''',
        states: selected ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          WIcon(icon, className: 'text-lg'),
          if (expanded)
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(label, className: 'text-sm font-semibold truncate'),
            ),
        ],
      ),
    );
  }
}
