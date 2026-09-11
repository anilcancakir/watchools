import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';
import 'page_gutter.dart';
import 'search_field.dart';

/// Search, scope and the count: the catalogue's toolbar.
///
/// The scope switch (everything, films, series) is not a styling decision, it
/// is what the screen is showing. It is shaped like the line-up's view switch
/// on purpose, and sits in the same place, because both answer "same catalogue,
/// which cut" and two idioms for one idea is one too many.
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
    // Fixed above `sm` rather than `flex-1` with a maximum beside it, which
    // does not clamp: `flex-1` is an `Expanded` and its tight minimum beats a
    // `ConstrainedBox` maximum. Written the other way the field filled the row.
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
          // `wrap` with no `flex` beside it. They are the same parser family and
          // the last one written wins, so `wrap` alone cannot be broken by
          // someone adding a class in front of it. Kept rather than reduced to
          // a plain row: a provider's own category names run long, and the bar
          // has to survive one arriving here later.
          WDiv(className: 'wrap items-center gap-3', children: <Widget>[search, _scopes(), _count()])
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

  /// The scope switch, scoped to the one field it reads.
  ///
  /// It is the catalogue's counterpart to `GuideViewSwitch` and the same free
  /// saving: the rest of this toolbar has to rebuild on a keystroke because it
  /// reads the query, and without this the switch went along with it, redrawing
  /// three anchors and three labels to show the same three words.
  Widget _scopes() {
    return MagicSelector<LibraryController, LibraryScope>(
      controller: controller,
      selector: (LibraryController c) => c.scope,
      builder: (LibraryScope current) => WDiv(
        className: 'flex flex-row gap-1 p-1 rounded-full shrink-0 bg-surface-container',
        children: <Widget>[
          _scope(LibraryScope.all, 'Tümü', current: current),
          _scope(LibraryScope.movies, 'Filmler', current: current),
          _scope(LibraryScope.series, 'Diziler', current: current),
        ],
      ),
    );
  }

  Widget _scope(LibraryScope scope, String label, {required LibraryScope current}) {
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
        states: current == scope ? const <String>{'selected'} : const <String>{},
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
