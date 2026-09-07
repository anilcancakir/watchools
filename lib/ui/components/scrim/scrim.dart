import 'package:flutter/widgets.dart';

/// The gradient ramps that make text legible over artwork.
///
/// Every one of these is a raw `LinearGradient` and none of them is a
/// className, because Wind has no custom gradient stops: `bg-gradient-to-t`
/// ramps between two theme colours and a scrim needs three, with the middle
/// stop placed by eye. That gap is recorded in
/// `.ac/research/ecosystem-defects.md`; this is the one place the workaround
/// lives, so the fix is a single edit when the sibling ships stops.
///
/// The dark half of `bg-surface` (`#0E0F11`) is hand-copied into the ramps for
/// the same reason. A scrim has to end in the page colour or the artwork stops
/// at a visible seam, and there is no way to read a theme colour into a
/// gradient from a className. The value is duplicated from
/// `lib/config/wind_theme.g.dart` and moves with it.
///
/// A scrim is always translucent black rather than a tinted surface, in both
/// light and dark. A light scrim over a light photograph reads as a smudge;
/// black reads as shade over anything.
abstract final class Scrim {
  /// The page colour the vertical ramps resolve into.
  static const Color _surface = Color(0xFF0E0F11);

  /// Bottom-up ramp, for a hero whose content sits along the lower edge and
  /// whose artwork has to meet the page with no seam.
  ///
  /// Three stops. Two produces a visible band across the middle of any
  /// photograph with a horizon in it, which most backdrops have.
  static const Widget bottom = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[_surface, Color(0xCC0E0F11), Color(0x000E0F11)],
        stops: <double>[0.0, 0.45, 0.9],
      ),
    ),
    child: SizedBox.expand(),
  );

  /// Left-to-right ramp, for a hero whose content sits in the left third.
  ///
  /// Netflix's television layout, and the reason it works: the artwork stays
  /// fully visible on the side the subject is usually on, and the text side is
  /// dark enough for a display face without a box behind it.
  static const Widget left = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[Color(0xF20E0F11), Color(0xB30E0F11), Color(0x000E0F11)],
        stops: <double>[0.0, 0.38, 0.78],
      ),
    ),
    child: SizedBox.expand(),
  );

  /// A flat wash, for a card whose whole surface carries a label.
  ///
  /// Weaker than [bottom] on purpose: it darkens a thumbnail enough for a
  /// two-word overlay and no more, because a card that is uniformly dimmed
  /// stops selling the thing it is showing.
  static const Widget flat = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[Color(0xD9000000), Color(0x66000000), Color(0x00000000)],
        stops: <double>[0.0, 0.5, 1.0],
      ),
    ),
    child: SizedBox.expand(),
  );

  /// The ramp that sits over an ambient wash on a detail page.
  ///
  /// Plex tints its detail background with a colour pulled out of the poster,
  /// darkening downward. This is the second half of that effect: the first half
  /// is the smeared artwork underneath, and this is what stops it competing
  /// with the text on top of it.
  static const Widget ambient = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // The top stop is what decides whether the wash is visible at all.
        // At 70% black over a 24 pixel decode there was a tint on paper and
        // nothing on screen; 60% is where the artwork's colour actually reaches
        // the page, and the title still clears AA over it because the smear has
        // no local contrast left to compete with type.
        colors: <Color>[Color(0x990E0F11), Color(0xDB0E0F11), _surface],
        stops: <double>[0.0, 0.45, 0.9],
      ),
    ),
    child: SizedBox.expand(),
  );
}
