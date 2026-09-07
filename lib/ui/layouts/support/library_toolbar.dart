import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';
import 'page_gutter.dart';
import 'search_field.dart';

/// Search, scope and the count, shared by every catalogue direction.
///
/// Unlike the line-up, the three catalogue directions do share this bar. The
/// scope switch (everything, films, series) is not a styling decision, it is
/// what the screen is showing, and giving each direction its own version would
/// mean comparing three different products.
///
/// The count and the missing-artwork note are one string. As two children they
/// overlapped at the right edge of a narrow row, and `shrink-0` protects a
/// child from being squeezed but not a row that has run out of width, which
/// Wind then clips silently.
@immutable
class LibraryToolbar extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Whether the search field and the scope switch share a line.
  ///
  /// They do not below `md`: at 414 pixels three tabs and a text field on one
  /// axis leaves the field too narrow to show a word of what was typed.
  final bool wide;

  /// The direction's own controls, right-aligned on a wide bar and dropped on a
  /// narrow one. Plex's card-size slider and sort menu live here.
  final Widget? trailing;

  /// Creates the [LibraryToolbar].
  const LibraryToolbar({super.key, required this.controller, required this.wide, this.trailing});

  @override
  Widget build(BuildContext context) {
    // Fixed above `sm` rather than `flex-1` with a maximum beside it, which
    // does not clamp: `flex-1` is an `Expanded` and its tight minimum beats a
    // `ConstrainedBox` maximum. Written the other way the field either filled
    // the row or, once the direction added three control groups to the same
    // line, was squeezed down to four characters of its own placeholder.
    final Widget search = WDiv(
      className: wide ? 'w-[360px] shrink-0' : 'w-full min-w-0',
      child: SearchField(value: controller.query, onChanged: controller.search, subject: 'Film, dizi veya bölüm ara'),
    );

    // `PageGutter.x` interpolated rather than written out. Interpolating a
    // CONSTANT is safe for Wind's parse cache, which keys on the string's value
    // and gets the same one every build; the rule against interpolation is
    // about a caller's variable, which mints a fresh cache entry per value.
    return WDiv(
      className: 'flex flex-col gap-2 ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        if (wide)
          // `wrap` with no `flex` beside it, because Wind's display family
          // resolves first-wins and would discard the wrap. The direction that
          // adds a sort group, a density group and a view toggle to this line
          // needs it: at 1100 pixels they and the field do not share one row.
          WDiv(
            className: 'wrap items-center gap-3',
            children: <Widget>[
              search,
              _scopes(),
              _count(),
              if (trailing != null) WDiv(className: 'shrink-0', child: trailing),
            ],
          )
        else ...<Widget>[
          search,
          // Three lines rather than two. The count is a sentence rather than a
          // number ("15 başlık · 4 başlıkta afiş yok"), and on one line beside
          // three scope tabs it overflowed the row by 31 pixels.
          WDiv(className: 'flex flex-row items-center', children: <Widget>[_scopes()]),
          // The direction's controls get their own line rather than being
          // dropped. Plex keeps its sort and its card size on a phone, and it
          // is right to: a five thousand title catalogue is harder to arrange
          // on a small screen, not easier, so that is where the controls matter
          // most.
          // Placed directly, not inside a `flex flex-row` wrapper. A Row gives
          // its child unbounded width on the main axis, so the control group's
          // own `wrap` never had a width to wrap against and ran 163 pixels
          // past a 414 pixel screen.
          ?trailing,
          _count(),
        ],
      ],
    );
  }

  Widget _scopes() {
    return WDiv(
      className: 'flex flex-row gap-1 p-1 rounded-full shrink-0 bg-surface-container',
      children: <Widget>[
        _scope(LibraryScope.all, 'Tümü'),
        _scope(LibraryScope.movies, 'Filmler'),
        _scope(LibraryScope.series, 'Diziler'),
      ],
    );
  }

  Widget _scope(LibraryScope scope, String label) {
    return WAnchor(
      onTap: () => controller.showScope(scope),
      semanticLabel: '$label göster',
      child: WDiv(
        className: '''
          px-4 h-8 rounded-full
          flex items-center
          text-xs font-semibold text-fg-disabled
          hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-inverse selected:text-on-inverse
        ''',
        states: controller.scope == scope ? const <String>{'selected'} : const <String>{},
        child: WText(label, className: 'text-xs font-semibold'),
      ),
    );
  }

  Widget _count() {
    final String head = controller.countLabel;
    final String? note = controller.noArtworkNote;

    return WText(note == null ? head : '$head · $note', className: 'shrink-0 text-xs text-fg-muted');
  }
}
