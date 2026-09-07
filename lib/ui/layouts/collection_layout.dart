import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/count_badge/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/rail/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';

/// Direction three: the layout itself says which titles matter.
///
/// Apple TV's composition. A rail treats every card as equal and a grid treats
/// every cell as equal; this one does not. The first title in a collection gets
/// a tile several times the size of the rest, so the ranking is carried by the
/// geometry rather than by a badge, which is also how Apple carries rank (a
/// numeral the size of the card, sitting outside it).
///
/// The provider rail at the top is Apple's `Channels & Apps` row applied
/// honestly. Apple gives Disney+ and ESPN their own brand tiles because a
/// viewer thinks in services; for this product the services are the user's own
/// configured providers, and they are the first thing to fix when something
/// stops playing.
@immutable
class CollectionLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [CollectionLayout].
  const CollectionLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 900;
    final bool hasRail = MediaQuery.sizeOf(context).width >= 640;
    final List<(String, List<TitleItem>)> groups = controller.collections;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (hasRail) const NavRail(),
        WDiv(
          className: 'flex-1 min-w-0 h-full',
          child: controller.matches.isEmpty
              ? _emptyBody(hasRail)
              : CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: LibraryToolbar(controller: controller, wide: hasRail),
                    ),
                    const SliverToBoxAdapter(child: PageGutter.gap),
                    SliverToBoxAdapter(child: LibraryCategories(controller: controller)),
                    SliverToBoxAdapter(child: _providers()),
                    // No empty-collections branch. `collections` falls back to
                    // one unnamed group carrying the matches, so it is empty
                    // only when the catalogue is, and that case is handled
                    // above by `_emptyBody`. The branch that used to be here
                    // explained the direction's own grouping rule to a user who
                    // had asked a question, which is not an answer.
                    SliverList.builder(
                      itemCount: groups.length,
                      itemBuilder: (BuildContext context, int index) {
                        final (String name, List<TitleItem> items) = groups[index];

                        return _collection(name, items, wide);
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _emptyBody(bool wide) {
    return WDiv(
      className: 'flex flex-col w-full h-full',
      children: <Widget>[
        LibraryToolbar(controller: controller, wide: wide),
        PageGutter.gap,
        LibraryCategories(controller: controller),
        PageGutter.gap,
        WDiv(
          className: 'flex-1 w-full',
          child: LibraryEmpty(controller: controller),
        ),
      ],
    );
  }

  /// The provider rail.
  ///
  /// One real entry and one action, which is the honest shape today: this app
  /// has a single configured source and adding another is the interesting verb.
  /// Apple's version of this row is the strongest argument in its whole screen
  /// for brand identity as a first-class citizen rather than a watermark.
  Widget _providers() {
    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.top}',
      children: <Widget>[
        const WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: 'Kaynakların', source: 'Aboneliklerin bu cihazda saklanır'),
        ),
        Rail(
          height: 96,
          itemCount: 2,
          itemBuilder: (BuildContext context, int index) => index == 0 ? _providerTile() : _addProviderTile(),
        ),
      ],
    );
  }

  Widget _providerTile() {
    return SizedBox(
      width: 168,
      child: WAnchor(
        onTap: () {},
        semanticLabel: 'Sağlayıcı ayarları',
        child: const WDiv(
          className: '''
            flex flex-col justify-center gap-1 w-full h-full px-4 rounded-xl
            bg-surface-container-high
            hover:bg-surface-container
            focus:ring-2 focus:ring-focus-ring
          ''',
          children: <Widget>[
            WDiv(
              className: 'flex flex-row items-center gap-1.5 w-full',
              children: <Widget>[
                WDiv(className: 'shrink-0 size-2 rounded-full bg-live'),
                WText('Bağlı', className: 'text-xs font-semibold text-fg-muted'),
              ],
            ),
            WText('Ana sağlayıcı', className: 'text-base font-bold text-fg line-clamp-1'),
            WText('Xtream Codes', className: 'text-xs text-fg-disabled'),
          ],
        ),
      ),
    );
  }

  Widget _addProviderTile() {
    return SizedBox(
      width: 168,
      child: WAnchor(
        onTap: () {},
        semanticLabel: 'Sağlayıcı ekle',
        child: const WDiv(
          className: '''
            flex flex-col items-center justify-center gap-1 w-full h-full rounded-xl
            border border-color-border-subtle
            text-fg-muted
            hover:text-fg
            focus:ring-2 focus:ring-focus-ring
          ''',
          children: <Widget>[
            WIcon(Icons.add_rounded, className: 'text-xl'),
            WText('Sağlayıcı ekle', className: 'text-xs font-semibold'),
          ],
        ),
      ),
    );
  }

  /// One collection: a feature tile plus the supporting ones.
  ///
  /// Above 900 pixels the feature and the supports share a row, which is the
  /// composition that makes the point. Below it there is not enough width for a
  /// feature and a grid side by side, so the feature goes full width and the
  /// rest becomes a rail: the same hierarchy, stacked.
  Widget _collection(String name, List<TitleItem> items, bool wide) {
    final TitleItem feature = items.first;
    final List<TitleItem> rest = items.skip(1).toList();

    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.top}',
      children: <Widget>[
        // No trailing count. Right-aligned on a 1440 pixel screen it sits a
        // thousand pixels from the title it counts and reads as an orphan.
        WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: name),
        ),
        if (wide)
          WDiv(
            className: 'flex flex-row gap-4 w-full ${PageGutter.x}',
            children: <Widget>[
              WDiv(className: 'w-[420px] shrink-0', child: _featureTile(feature)),
              WDiv(className: 'flex-1 min-w-0', child: _supportGrid(rest)),
            ],
          )
        else ...<Widget>[
          WDiv(className: 'w-full ${PageGutter.x}', child: _featureTile(feature)),
          Rail(
            height: 168,
            itemCount: rest.length,
            itemBuilder: (BuildContext context, int index) => SizedBox(width: 240, child: _supportTile(rest[index])),
          ),
        ],
      ],
    );
  }

  /// The large tile. 16:9 rather than 2:3, because at this size a poster's
  /// height forces every supporting tile beside it into a strip.
  Widget _featureTile(TitleItem title) {
    return WDiv(
      className: 'w-full rounded-xl overflow-hidden bg-surface-container-high',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            WAnchor(
              onTap: () => controller.openDetail(title),
              semanticLabel: '${title.name}, ${title.year}, ${title.lengthLabel}',
              child: WDiv(
                className: 'w-full h-full focus:ring-2 focus:ring-focus-ring',
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Artwork(
                      src: title.backdropUrl ?? title.posterUrl,
                      slotWidth: 420,
                      fallback: WDiv(
                        className: 'w-full h-full p-6 items-center justify-center',
                        child: WText(
                          title.name,
                          className: 'text-2xl font-bold text-fg-muted text-center line-clamp-3',
                        ),
                      ),
                    ),
                    Scrim.bottom,
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: WDiv(
                        className: 'flex flex-col gap-1 w-full',
                        children: <Widget>[
                          WText(title.name, className: 'text-2xl font-bold text-fg line-clamp-2'),
                          WText(
                            '${title.year} · ${title.lengthLabel}${title.genres.isEmpty ? '' : ' · ${title.genres.first}'}',
                            className: 'text-xs text-fg-muted line-clamp-1',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: FavouriteButton(
                starred: title.favourite,
                subject: title.name,
                shape: 'badge',
                onToggle: () => controller.toggleFavourite(title),
              ),
            ),
            if (title.unwatchedCount != null)
              Positioned(top: 0, left: 0, child: CountBadge(label: '${title.unwatchedCount}')),
            if (title.progress > 0.03 && title.progress < 0.92)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PlayProgress(value: title.progress, size: 'lg'),
              ),
          ],
        ),
      ),
    );
  }

  /// The supports, two across, wrapping.
  ///
  /// `wrap` with no `flex` beside it, and no `w-full` on it either.
  ///
  /// It sits inside a `flex-1`, which Wind composes as an `Expanded`, so the
  /// width is already tight. Adding `w-full` on top wraps it in a
  /// `FractionallySizedBox` inside a `LayoutBuilder`, and that pair being torn
  /// down mid-layout on a route change produced twenty cascading
  /// `RenderBox was not laid out` assertions every time a title was opened from
  /// this direction.
  Widget _supportGrid(List<TitleItem> items) {
    return WDiv(
      className: 'wrap gap-3',
      children: <Widget>[
        for (final TitleItem title in items.take(6)) WDiv(className: 'w-[240px]', child: _supportTile(title)),
      ],
    );
  }

  Widget _supportTile(TitleItem title) {
    return WDiv(
      className: 'w-full rounded-lg overflow-hidden bg-surface-container-high',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            WAnchor(
              onTap: () => controller.openDetail(title),
              semanticLabel: '${title.name}, ${title.year}',
              child: WDiv(
                className: 'w-full h-full focus:ring-2 focus:ring-focus-ring',
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Artwork(
                      src: title.backdropUrl ?? title.posterUrl,
                      slotWidth: 240,
                      fallback: WDiv(
                        className: 'w-full h-full p-3 items-center justify-center',
                        child: WText(title.name, className: 'text-sm font-bold text-fg-muted text-center line-clamp-3'),
                      ),
                    ),
                    Scrim.flat,
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: WText(title.name, className: 'text-sm font-semibold text-fg line-clamp-1'),
                    ),
                  ],
                ),
              ),
            ),
            // A star on the support tiles as well as the feature. Favourites
            // are the one control that has to be on every surface showing a
            // title, and a composition where only the large tile can be starred
            // is a composition that punishes you for liking the wrong one.
            Positioned(
              top: 4,
              right: 4,
              child: FavouriteButton(
                starred: title.favourite,
                subject: title.name,
                shape: 'badge',
                onToggle: () => controller.toggleFavourite(title),
              ),
            ),
            if (title.unwatchedCount != null)
              Positioned(top: 0, left: 0, child: CountBadge(label: '${title.unwatchedCount}')),
            if (title.progress > 0.03 && title.progress < 0.92)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PlayProgress(value: title.progress, size: 'sm'),
              ),
          ],
        ),
      ),
    );
  }
}
