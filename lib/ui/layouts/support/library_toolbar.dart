import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';

/// Search, scope and the count, shared by every catalogue layout.
///
/// Unlike the line-up, the three catalogue layouts do share this bar. The
/// scope switch (everything, films, series) is not a styling decision, it is
/// what the screen is showing, and giving each layout its own version would
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

  /// Creates the [LibraryToolbar].
  const LibraryToolbar({super.key, required this.controller, required this.wide});

  @override
  Widget build(BuildContext context) {
    final Widget search = WDiv(
      className: wide ? 'flex-1 max-w-[360px] min-w-0' : 'w-full min-w-0',
      child: WInput(
        value: controller.query,
        onChanged: controller.search,
        placeholder: 'Film, dizi veya bölüm ara',
        semanticLabel: 'Film, dizi veya bölüm ara',
        className: '''
          border-0
          rounded-full px-4 py-2.5
          bg-surface-container
          text-sm text-fg
          hover:bg-surface-container-high
          focus:ring-2 focus:ring-focus-ring
        ''',
      ),
    );

    return WDiv(
      className: 'flex flex-col gap-2 px-4 md:px-8 pt-5',
      children: <Widget>[
        if (wide)
          WDiv(
            className: 'flex flex-row items-center gap-3',
            children: <Widget>[
              search,
              _scopes(),
              const WDiv(className: 'flex-1'),
              _count(),
            ],
          )
        else ...<Widget>[
          search,
          // Three lines rather than two. The count is a sentence rather than a
          // number ("15 başlık · 4 başlıkta afiş yok"), and on one line beside
          // three scope tabs it overflowed the row by 31 pixels.
          WDiv(className: 'flex flex-row items-center', children: <Widget>[_scopes()]),
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
