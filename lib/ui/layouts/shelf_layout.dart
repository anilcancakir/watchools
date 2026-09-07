import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/count_badge/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/title_poster/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';

/// Direction two: the catalogue as a shelf the owner arranges.
///
/// Plex's library, and the reason it belongs beside a shop window: a provider
/// ships thousands of titles in an order nobody curated, and the only thing
/// that makes that usable is handing the arrangement to the person who owns it.
/// Plex's zoom slider looks like a toy until you meet a five thousand title
/// dump, at which point it is the whole feature.
///
/// Three controls, each answering a question the other directions cannot. Card
/// size decides how many titles a screen holds. Sort decides what "first"
/// means. The table decides whether artwork is worth its space at all, which
/// for a catalogue where a third of the posters never arrived is a real
/// question rather than a preference.
@immutable
class ShelfLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [ShelfLayout].
  const ShelfLayout({super.key, required this.controller});

  /// Poster width per density step. Mirrors the recipe sizes `TitlePoster`
  /// carries, so the decode and the cell agree.
  static const Map<ShelfDensity, (double, String)> _cells = <ShelfDensity, (double, String)>{
    ShelfDensity.compact: (124, 'sm'),
    ShelfDensity.regular: (168, 'md'),
    ShelfDensity.roomy: (220, 'lg'),
  };

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 640;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(expanded: true),
        WDiv(
          className: 'flex-1 min-w-0 h-full',
          child: WDiv(
            className: 'flex flex-col w-full h-full',
            children: <Widget>[
              LibraryToolbar(controller: controller, wide: wide, trailing: _controls()),
              PageGutter.gap,
              LibraryCategories(controller: controller),
              WDiv(
                className: 'flex-1 w-full',
                child: controller.matches.isEmpty
                    ? LibraryEmpty(controller: controller)
                    : controller.asTable
                    ? _table()
                    : _grid(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `wrap`, not `flex flex-row`. On a phone the three groups get the toolbar's
  /// own line and still do not fit it on one axis. `flex` and `wrap` are the
  /// same parser family and the last one written wins, so writing `wrap` alone
  /// is the form that cannot be got wrong by adding a class in front of it.
  Widget _controls() {
    return WDiv(className: 'wrap items-center gap-2', children: <Widget>[_sort(), _density(), _viewToggle()]);
  }

  Widget _sort() {
    const Map<ShelfSort, String> labels = <ShelfSort, String>{
      ShelfSort.provider: 'Sağlayıcı sırası',
      ShelfSort.name: 'Ada göre',
      ShelfSort.year: 'Yıla göre',
      ShelfSort.rating: 'Puana göre',
    };

    // `wrap` here as well as around the group. Four Turkish sort labels come to
    // about 377 pixels, which is eleven past a 414 pixel screen's content
    // width, so the group wrapping is not enough on its own.
    return WDiv(
      className: 'wrap items-center gap-1 p-1 rounded-full bg-surface-container',
      children: <Widget>[
        for (final MapEntry<ShelfSort, String> entry in labels.entries)
          WAnchor(
            onTap: () => controller.showSort(entry.key),
            semanticLabel: entry.value,
            child: WDiv(
              className: '''
                flex flex-row items-center px-3 h-7 rounded-full
                text-xs font-semibold text-fg-disabled
                hover:text-fg
                focus:ring-2 focus:ring-focus-ring
                selected:bg-inverse selected:text-on-inverse
              ''',
              states: controller.sort == entry.key ? const <String>{'selected'} : const <String>{},
              child: WText(entry.value, className: 'text-xs font-semibold'),
            ),
          ),
      ],
    );
  }

  /// Three steps rather than a continuous slider.
  ///
  /// Plex ships a slider, and a slider is the wrong control on a remote: it has
  /// no discrete stops for a D-pad to land on. Three named steps are the same
  /// decision with a focusable target for each answer.
  Widget _density() {
    const Map<ShelfDensity, (IconData, String)> steps = <ShelfDensity, (IconData, String)>{
      ShelfDensity.compact: (Icons.grid_on, 'Küçük kartlar'),
      ShelfDensity.regular: (Icons.grid_view, 'Orta kartlar'),
      ShelfDensity.roomy: (Icons.view_agenda_outlined, 'Büyük kartlar'),
    };

    return WDiv(
      className: 'flex flex-row items-center gap-1 p-1 rounded-full bg-surface-container',
      children: <Widget>[
        for (final MapEntry<ShelfDensity, (IconData, String)> entry in steps.entries)
          WAnchor(
            onTap: () => controller.showDensity(entry.key),
            semanticLabel: entry.value.$2,
            child: WDiv(
              className: '''
                size-7 rounded-full items-center justify-center
                text-fg-disabled
                hover:text-fg
                focus:ring-2 focus:ring-focus-ring
                selected:bg-inverse selected:text-on-inverse
              ''',
              states: controller.density == entry.key ? const <String>{'selected'} : const <String>{},
              child: WIcon(entry.value.$1, className: 'text-sm'),
            ),
          ),
      ],
    );
  }

  Widget _viewToggle() {
    return WAnchor(
      onTap: () => controller.showTable(asTable: !controller.asTable),
      semanticLabel: controller.asTable ? 'Izgara görünümü' : 'Liste görünümü',
      child: WDiv(
        className: '''
          size-9 rounded-full items-center justify-center
          bg-surface-container text-fg-muted
          hover:bg-surface-container-high hover:text-fg
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(controller.asTable ? Icons.grid_view : Icons.view_list_outlined, className: 'text-base'),
      ),
    );
  }

  /// The poster grid.
  ///
  /// The column count and the cell width are worked out here rather than left
  /// to `SliverGridDelegateWithMaxCrossAxisExtent`, and that is not a
  /// preference. That delegate treats the extent as a MAXIMUM and then divides
  /// the row evenly, so the cell it hands you is wider than the number you
  /// passed. A `mainAxisExtent` computed from the number you passed is
  /// therefore always short, and every cell in the grid overflowed its bottom
  /// by thirty pixels while the arithmetic looked right.
  Widget _grid() {
    final (double target, String size) = _cells[controller.density]!;
    final List<TitleItem> items = controller.sorted;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 16;
        const double padding = PageGutter.value * 2;
        final double available = constraints.maxWidth - padding;
        final int columns = ((available + gap) / (target + gap)).floor().clamp(1, 12);
        final double cell = (available - gap * (columns - 1)) / columns;

        return GridView.builder(
          padding: PageGutter.scrollable,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: TitlePoster.heightFor(cell),
            crossAxisSpacing: gap,
            mainAxisSpacing: 20,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) {
            final TitleItem title = items[index];

            return TitlePoster(
              title: title,
              size: size,
              // The cell owns the width, so the recipe's own `w-[168px]` would
              // fight it. Overridden to fill, which is what makes the frame's
              // 2:3 aspect agree with the height stated above.
              className: 'w-full',
              onTap: () => controller.openDetail(title),
              onToggleFavourite: () => controller.toggleFavourite(title),
            );
          },
        );
      },
    );
  }

  /// The table. Artwork shrinks to a thumbnail and the facts take the width.
  Widget _table() {
    final List<TitleItem> items = controller.sorted;

    return ListView.separated(
      padding: PageGutter.scrollable,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (BuildContext context, int index) => _row(items[index]),
    );
  }

  Widget _row(TitleItem title) {
    final String? rating = title.ratingLabel;

    return WDiv(
      className: '''
        flex flex-row items-center gap-3
        h-[76px] rounded-lg overflow-hidden pr-2
        bg-surface-container
        hover:bg-surface-container-high
      ''',
      children: <Widget>[
        WDiv(
          className: 'flex-1 min-w-0',
          child: WAnchor(
            onTap: () => controller.openDetail(title),
            // The row's own label carries what the columns say, because they
            // drop out one at a time as the width narrows and a label built
            // from whatever survived would describe a different row on a phone.
            semanticLabel: _label(title, rating),
            child: WDiv(
              className: 'flex flex-row items-center gap-3 h-[76px] focus:ring-2 focus:ring-focus-ring',
              children: <Widget>[
                _thumb(title),
                WDiv(
                  className: 'flex-1 min-w-0',
                  child: WDiv(
                    className: 'flex flex-col',
                    children: <Widget>[
                      WText(title.name, className: 'text-sm font-semibold text-fg line-clamp-1'),
                      WText(
                        '${title.isSeries ? 'Dizi' : 'Film'} · ${title.category}',
                        className: 'text-xs text-fg-muted line-clamp-1',
                      ),
                    ],
                  ),
                ),
                WDiv(
                  className: 'hidden md:block shrink-0 w-16',
                  child: WText(
                    '${title.year}',
                    className: 'text-xs text-fg-muted',
                    textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                  ),
                ),
                WDiv(
                  className: 'hidden md:block shrink-0 w-20',
                  child: WText(title.lengthLabel, className: 'text-xs text-fg-muted'),
                ),
                WDiv(
                  className: 'hidden lg:block shrink-0 w-16',
                  child: WText(
                    rating == null ? 'yok' : '★ $rating',
                    className: rating == null ? 'text-xs text-fg-disabled' : 'text-xs font-semibold text-fg',
                  ),
                ),
                WDiv(
                  className: 'hidden xl:flex flex-row gap-1 shrink-0 w-[180px]',
                  children: <Widget>[for (final String fact in title.facts) FactChip(label: fact)],
                ),
              ],
            ),
          ),
        ),
        WDiv(
          className: 'shrink-0',
          child: FavouriteButton(
            starred: title.favourite,
            subject: title.name,
            onToggle: () => controller.toggleFavourite(title),
          ),
        ),
      ],
    );
  }

  Widget _thumb(TitleItem title) {
    return WDiv(
      className: 'shrink-0 w-[52px] h-[76px] overflow-hidden bg-surface-container-high',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: title.posterUrl,
            slotWidth: 52,
            fallback: WDiv(
              className: 'w-full h-full items-center justify-center p-1',
              child: WIcon(
                title.isSeries ? Icons.subscriptions_outlined : Icons.movie_outlined,
                className: 'text-sm text-fg-disabled',
              ),
            ),
          ),
          if (title.unwatchedCount != null)
            Positioned(top: 0, right: 0, child: CountBadge(label: '${title.unwatchedCount}')),
          if (title.progress > 0.03 && title.progress < 0.92)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlayProgress(value: title.progress, size: 'sm'),
            ),
        ],
      ),
    );
  }

  String _label(TitleItem title, String? rating) {
    final StringBuffer out = StringBuffer()
      ..write(title.name)
      ..write(', ${title.isSeries ? 'dizi' : 'film'}')
      ..write(', ${title.year}')
      ..write(', ${title.lengthLabel}');

    if (rating != null) out.write(', puan $rating');
    if (title.inProgress) out.write(', yarım kaldı');

    return out.toString();
  }
}
