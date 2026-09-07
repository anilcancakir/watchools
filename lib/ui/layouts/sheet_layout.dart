import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/count_badge/index.dart';
import '../components/fact_chip/index.dart';
import '../components/fact_list/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import 'support/page_gutter.dart';
import 'support/title_sections.dart';

/// Detail direction three: the phone-native one.
///
/// Plex on Android, scaled up rather than down. Its three moves are the ones
/// worth arguing for on a touch surface: the primary action becomes a large
/// circular button straddling the seam between the artwork and the content, the
/// poster shrinks and OVERLAPS that seam instead of sitting in a column of its
/// own, and everything else collapses into one centred row of icons.
///
/// The overlap is what makes it work at 414 pixels. A poster in its own column
/// costs a third of the width on a phone; a poster crossing the seam costs
/// nothing, because the space it occupies was artwork that had already faded to
/// black.
///
/// The technical stack is a first-class section here rather than a footnote,
/// which is this direction's own departure. A phone is where a stream fails,
/// and `Video / Ses / Altyazılar` is what the viewer opens the page to change.
@immutable
class SheetLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [SheetLayout].
  const SheetLayout({super.key, required this.controller});

  /// How far the poster and the play button hang below the artwork.
  static const double _overlap = 56;

  @override
  Widget build(BuildContext context) {
    final TitleItem title = controller.selected;

    // Held to a phone's width and centred, on every screen.
    //
    // This direction is an argument about a touch surface: the poster crossing
    // the seam, the thumb-sized circle on the right of it, the icon row centred
    // under the name. Every one of those depends on the two ends of the row
    // being a thumb apart. Let the column run to 1440 and the poster and the
    // button are at opposite ends of a monitor, the label-value rows are a
    // metre of dead space, and the direction stops being the thing it was meant
    // to be judged as.
    // A `LayoutBuilder` and a `SizedBox`, not a Wind row with a centred child.
    // Written that way (`flex flex-row justify-center` around a
    // `w-full sm:w-[520px] h-full`) the column reached the `CustomScrollView`
    // with a constraint Flutter could not resolve, and the screen came back as
    // `RenderBox was not laid out` plus a semantics assertion and three nodes.
    // The two axes are stated outright here instead.
    return WDiv(
      className: 'w-full h-full bg-surface',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const double column = 520;
          final double width = constraints.maxWidth < column ? constraints.maxWidth : column;

          return Center(
            child: SizedBox(width: width, height: constraints.maxHeight, child: _body(title)),
          );
        },
      ),
    );
  }

  Widget _body(TitleItem title) {
    return WDiv(
      className: 'w-full h-full',
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _head(title)),
          SliverToBoxAdapter(child: _identity(title)),
          SliverToBoxAdapter(child: _actions(title)),
          SliverToBoxAdapter(child: _measures(title)),
          SliverToBoxAdapter(child: _synopsis(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: _specs(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          if (title.isSeries) ...<Widget>[
            SliverToBoxAdapter(child: TitleSections.seasons(controller, title)),
            const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
            SliverToBoxAdapter(child: TitleSections.episodes(controller, title, density: 'compact')),
            const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          ],
          SliverToBoxAdapter(child: TitleSections.cast(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.related(controller, title)),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  /// The artwork, plus the two things that hang off its lower edge.
  Widget _head(TitleItem title) {
    final Episode? next = title.upNext;
    final double progress = title.isSeries ? (next?.progress ?? 0) : title.progress;

    return SizedBox(
      height: 240 + _overlap,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Artwork(
                  src: title.backdropUrl ?? title.posterUrl,
                  fallback: const WDiv(className: 'w-full h-full bg-surface-container'),
                ),
                Scrim.bottom,
                if (progress > 0.03 && progress < 0.92)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PlayProgress(value: progress, size: 'lg'),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: PageGutter.value,
            child: WAnchor(
              onTap: () => MagicRoute.back(),
              semanticLabel: 'Geri',
              child: const WDiv(
                className: '''
                  size-10 rounded-full items-center justify-center
                  bg-scrim-strong text-fg
                  hover:bg-scrim
                  focus:ring-2 focus:ring-focus-ring
                ''',
                child: WIcon(Icons.arrow_back, className: 'text-base'),
              ),
            ),
          ),
          Positioned(left: PageGutter.value, bottom: 0, width: 110, child: _poster(title)),
          Positioned(right: PageGutter.value, bottom: 12, child: _playCircle(title)),
        ],
      ),
    );
  }

  Widget _poster(TitleItem title) {
    return WDiv(
      className: 'w-full rounded-lg overflow-hidden bg-surface-container-high shadow-lg',
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Artwork(
              src: title.posterUrl,
              slotWidth: 110,
              fallback: WDiv(
                className: 'w-full h-full p-2 items-center justify-center',
                child: WText(title.name, className: 'text-xs font-bold text-fg-muted text-center line-clamp-4'),
              ),
            ),
            if (title.unwatchedCount != null)
              Positioned(top: 0, right: 0, child: CountBadge(label: '${title.unwatchedCount}')),
          ],
        ),
      ),
    );
  }

  /// The circular primary action, sized past the 48dp touch floor with room to
  /// spare because it is the one control a thumb reaches for without looking.
  Widget _playCircle(TitleItem title) {
    return WAnchor(
      onTap: () {},
      semanticLabel: '${title.name} ${TitleSections.playLabel(title)}',
      child: const WDiv(
        className: '''
          size-16 rounded-full items-center justify-center
          bg-primary text-on-primary
          shadow-lg
          hover:bg-primary-hover
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(Icons.play_arrow_rounded, className: 'text-3xl'),
      ),
    );
  }

  Widget _identity(TitleItem title) {
    final Episode? next = title.upNext;

    return WDiv(
      className: 'flex flex-col gap-1 w-full ${PageGutter.x} ${PageGutter.inner}',
      children: <Widget>[
        WText(title.name, className: 'text-2xl sm:text-3xl font-bold text-fg line-clamp-2'),
        WText(
          title.isSeries && next != null ? '${next.code} · ${next.title}' : '${title.year} · ${title.lengthLabel}',
          className: 'text-sm text-fg-muted line-clamp-1',
        ),
      ],
    );
  }

  /// The centred icon row. Plex's phone layout, where the star joins the row
  /// rather than sitting apart from it: on a touch surface a lone control in a
  /// corner is a control nobody finds.
  Widget _actions(TitleItem title) {
    return WDiv(
      className: 'flex flex-row items-center justify-center gap-2 w-full ${PageGutter.inner}',
      children: <Widget>[
        WDiv(
          className: 'shrink-0',
          child: FavouriteButton(
            starred: title.favourite,
            subject: title.name,
            shape: 'circle',
            onToggle: () => controller.toggleFavourite(title),
          ),
        ),
        WDiv(className: 'shrink-0', child: TitleSections.ghostActions(controller, title)),
      ],
    );
  }

  /// The split fact row: time on the left, score on the right.
  ///
  /// Plex puts exactly these two at opposite ends of one line on a phone, and
  /// the reason it reads well is that they answer different questions. How long
  /// will this take, and is it any good.
  Widget _measures(TitleItem title) {
    final String? rating = title.ratingLabel;

    return WDiv(
      className: 'flex flex-row items-center justify-between gap-4 w-full ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        WDiv(
          className: 'flex flex-row items-center gap-1.5 shrink-0',
          children: <Widget>[
            const WIcon(Icons.schedule, className: 'text-sm text-fg-muted'),
            WText(title.lengthLabel, className: 'text-sm font-medium text-fg'),
          ],
        ),
        WDiv(
          className: 'flex flex-row items-center gap-1.5 shrink-0',
          children: <Widget>[
            if (rating == null)
              const WText('Puan yok', className: 'text-sm text-fg-disabled')
            else ...<Widget>[
              const WIcon(Icons.star_rounded, className: 'text-sm text-primary'),
              WText(rating, className: 'text-sm font-bold text-fg'),
            ],
          ],
        ),
      ],
    );
  }

  Widget _synopsis(TitleItem title) {
    if (title.synopsis == null) {
      return const WDiv(
        className: 'w-full ${PageGutter.x} ${PageGutter.inner}',
        child: WText('Sağlayıcı bu başlık için özet göndermedi.', className: 'text-sm text-fg-disabled'),
      );
    }

    return WDiv(
      className: 'flex flex-col gap-1 w-full ${PageGutter.x} ${PageGutter.inner}',
      children: <Widget>[
        WText(title.synopsis!, className: 'text-sm text-fg-muted line-clamp-3'),
        WAnchor(
          onTap: () {},
          semanticLabel: 'Özetin tamamını göster',
          child: const WDiv(
            className: 'py-1 focus:ring-2 focus:ring-focus-ring',
            child: WText('Daha fazla', className: 'text-sm font-semibold text-primary'),
          ),
        ),
      ],
    );
  }

  /// The technical stack, with the fact chips above it.
  ///
  /// The chips and the rows are deliberately not redundant: a chip is a claim
  /// the provider made in its playlist (`4K`, `H.265`) and a row is what the
  /// stream is going to hand the decoder. On a real provider those two disagree
  /// often enough that showing only one of them is the wrong choice.
  Widget _specs(TitleItem title) {
    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.x}',
      children: <Widget>[
        const SectionHeader(title: 'Künye', source: 'Sağlayıcının bildirdiği değerler'),
        if (title.facts.isNotEmpty)
          WDiv(
            className: 'wrap gap-1 w-full',
            children: <Widget>[for (final String fact in title.facts) FactChip(label: fact)],
          ),
        FactList(entries: TitleSections.entries(title)),
      ],
    );
  }
}
