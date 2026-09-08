import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// The persistent search field.
///
/// Persistent, and never behind an icon on anything wider than a phone. Plex
/// keeps a 470 pixel field in its top bar at all times and Netflix hides its
/// own behind a glyph; for a line-up that runs to five figures, Plex is
/// obviously right. Scrolling a provider's channel list is not browsing, it is
/// futile, and search plus grouping are the only navigation that scales.
///
/// The clear button is a sibling of the input rather than a suffix inside it.
/// Wind's `WInput` takes no trailing slot, and a control nested inside a text
/// field's own semantics node is one a screen reader cannot reach separately
/// anyway.
@immutable
class SearchField extends StatelessWidget {
  /// The current term.
  final String value;

  /// Fired on every keystroke and by the clear button.
  final ValueChanged<String> onChanged;

  /// What the field is searching, for the placeholder and the label.
  final String subject;

  /// Creates a [SearchField].
  const SearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.subject = 'Kanal, numara veya program',
  });

  /// The width Plex gives its own field, and the width to give this one on any
  /// surface with the room.
  ///
  /// A number the caller applies as `w-[470px] shrink-0`, rather than a
  /// `flex-1 max-w-[470px]` on the wrapper. The second shape does not work and
  /// looks like it should: `flex-1` wraps the child in an `Expanded`, which
  /// passes a TIGHT width constraint down, and a tight minimum beats a
  /// `ConstrainedBox` maximum. Every field written that way rendered at the
  /// full row width, 1250 pixels of it on a desktop.
  static const double preferred = 470;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: '''
        flex flex-row items-center gap-2 w-full h-11
        px-3 rounded-full
        bg-surface-container
        border border-color-border-subtle
        focus:ring-2 focus:ring-focus-ring
      ''',
      children: <Widget>[
        const WDiv(
          className: 'shrink-0',
          child: WIcon(Icons.search, className: 'text-base text-fg-muted'),
        ),
        WDiv(
          className: 'flex-1 min-w-0',
          // `border-0`, not `border-transparent`. `WInput` paints a hardcoded
          // `#D1D5DB` hairline whenever the className resolves no border, and
          // `border-transparent` resolves to a near-white `#E5E7EB` rather than
          // to nothing: it matches the border colour regex with the shade
          // defaulting to 500, `transparent` in the palette is a plain Color
          // rather than a shade map, `isValidColor` fails, and the fallback is
          // used. Only a zero WIDTH reaches the `b.top.width == 0` branch that
          // drops the border. Both halves are defect 3 in
          // `.ac/research/ecosystem-defects.md`.
          child: WInput(
            value: value,
            onChanged: onChanged,
            placeholder: subject,
            semanticLabel: 'Arama',
            className: 'w-full bg-transparent border-0 text-sm text-fg',
          ),
        ),
        if (value.isNotEmpty)
          WDiv(
            // `shrink-0` is ignored on a WAnchor (defect 2 in
            // `.ac/research/ecosystem-defects.md`), so the wrapper is what
            // keeps the button from being squeezed to nothing by the field.
            className: 'shrink-0',
            child: WAnchor(
              onTap: () => onChanged(''),
              semanticLabel: 'Aramayı temizle',
              child: const WDiv(
                className: '''
                  size-7 rounded-full items-center justify-center
                  text-fg-muted
                  hover:bg-surface-container-high hover:text-fg
                  focus:ring-2 focus:ring-focus-ring
                ''',
                child: WIcon(Icons.close, className: 'text-sm'),
              ),
            ),
          ),
      ],
    );
  }
}
