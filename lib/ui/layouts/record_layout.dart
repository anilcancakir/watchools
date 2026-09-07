import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/ambient_wash/index.dart';
import '../components/artwork/index.dart';
import '../components/count_badge/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import 'support/page_gutter.dart';
import 'support/title_sections.dart';

/// Detail direction one: the record card.
///
/// Plex's title page, close to line for line, because it is the one in the
/// references built for a library the user owns rather than a catalogue
/// somebody is selling them. Poster on the left with the resume target spelled
/// out beneath it, a stack of labelled facts on the right, one amber verb, and
/// everything else demoted to a ghost icon.
///
/// The ambient wash is the cheapest thing in the references and the most
/// effective: a page tinted with its own artwork feels bespoke without a single
/// bespoke asset, and it degrades to a plain dark page when the provider sent
/// no backdrop, which is a third of the time.
@immutable
class RecordLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [RecordLayout].
  const RecordLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final TitleItem title = controller.selected;
    final bool wide = MediaQuery.sizeOf(context).width >= 900;

    return AmbientWash(
      src: title.backdropUrl ?? title.posterUrl,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _header(title)),
          // The header is a block like any other and gets the page's own
          // distance below it. Without this the poster's top edge touched the
          // back button, which reads as the artwork having escaped its frame.
          const SliverToBoxAdapter(child: PageGutter.gap),
          SliverToBoxAdapter(child: _card(title, wide)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          if (title.isSeries) ...<Widget>[
            SliverToBoxAdapter(child: TitleSections.seasons(controller, title)),
            const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
            SliverToBoxAdapter(child: TitleSections.episodes(controller, title)),
            const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          ],
          SliverToBoxAdapter(child: TitleSections.specs(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.cast(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.related(controller, title)),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  /// Back, the library it came from, and the arrows that walk to the next title
  /// without going back first. Plex's header carries all three, and the arrows
  /// are the part everyone else leaves out: browsing a library means comparing,
  /// and comparing through a back button is four taps per comparison.
  Widget _header(TitleItem title) {
    // `sorted`, not `matches`. The arrows walk the catalogue you came FROM, and
    // the shelf renders `sorted`: reading `matches` here meant "next" followed
    // the provider's order while the grid behind it was alphabetical, so the
    // arrow moved to a title that was nowhere near the one you had just left.
    final List<TitleItem> siblings = controller.sorted;
    final int index = siblings.indexOf(title);

    return WDiv(
      className: 'flex flex-row items-center gap-3 w-full ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        WDiv(className: 'shrink-0', child: _icon(Icons.arrow_back, 'Geri', () => MagicRoute.back())),
        WDiv(
          className: 'flex-1 min-w-0',
          child: WDiv(
            className: 'flex flex-col',
            children: <Widget>[
              WText(title.isSeries ? 'Diziler' : 'Filmler', className: 'text-sm font-semibold text-fg line-clamp-1'),
              WText(title.category, className: 'text-xs text-fg-muted line-clamp-1'),
            ],
          ),
        ),
        WDiv(
          className: 'shrink-0',
          child: _icon(
            Icons.chevron_left,
            'Önceki başlık',
            index > 0 ? () => controller.select(siblings[index - 1]) : null,
          ),
        ),
        WDiv(
          className: 'shrink-0',
          child: _icon(
            Icons.chevron_right,
            'Sonraki başlık',
            index >= 0 && index < siblings.length - 1 ? () => controller.select(siblings[index + 1]) : null,
          ),
        ),
      ],
    );
  }

  Widget _icon(IconData icon, String label, VoidCallback? onTap) {
    return WAnchor(
      onTap: onTap,
      semanticLabel: label,
      child: WDiv(
        className: '''
          size-10 rounded-full items-center justify-center
          bg-scrim text-fg
          hover:bg-scrim-strong
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(icon, className: 'text-base'),
      ),
    );
  }

  Widget _card(TitleItem title, bool wide) {
    final Widget poster = _poster(title);
    final Widget facts = _facts(title, wide);

    if (!wide) {
      return WDiv(
        className: 'flex flex-col gap-5 w-full ${PageGutter.x}',
        children: <Widget>[
          WDiv(className: 'w-[180px]', child: poster),
          facts,
        ],
      );
    }

    return WDiv(
      className: 'flex flex-row items-start gap-8 w-full ${PageGutter.x}',
      children: <Widget>[
        WDiv(className: 'w-[260px] shrink-0', child: poster),
        WDiv(className: 'flex-1 min-w-0', child: facts),
      ],
    );
  }

  Widget _poster(TitleItem title) {
    final Episode? next = title.upNext;

    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: <Widget>[
        WDiv(
          className: 'w-full rounded-xl overflow-hidden bg-surface-container-high',
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Artwork(
                  src: title.posterUrl,
                  slotWidth: 260,
                  fallback: WDiv(
                    className: 'w-full h-full p-4 items-center justify-center',
                    child: WText(title.name, className: 'text-lg font-bold text-fg-muted text-center line-clamp-4'),
                  ),
                ),
                if (title.unwatchedCount != null)
                  Positioned(top: 0, right: 0, child: CountBadge(label: '${title.unwatchedCount}')),
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
        ),
        // The resume target under the poster, spelled out. Plex puts it here
        // and it is the single line that saves a returning viewer from opening
        // the episode list to find their place.
        WText(
          title.isSeries && next != null ? 'Hazır: ${next.code} · ${next.title}' : title.lengthLabel,
          className: 'text-xs text-fg-muted text-center line-clamp-2',
        ),
      ],
    );
  }

  Widget _facts(TitleItem title, bool wide) {
    final String? rating = title.ratingLabel;

    return WDiv(
      className: 'flex flex-col gap-4 w-full',
      children: <Widget>[
        WText(title.name, className: 'text-3xl sm:text-4xl font-bold text-fg line-clamp-2'),
        WText('${title.year}', className: 'text-sm text-fg-muted'),
        WText(
          title.genres.isEmpty ? 'Tür belirtilmemiş' : title.genres.join(', '),
          className: 'text-sm text-fg-muted line-clamp-1',
        ),
        WDiv(
          className: 'wrap items-center gap-2',
          children: <Widget>[
            // Plex puts a content-rating pill here. A provider sends no content
            // rating at all, so the slot carries what it does send and what the
            // page's whole shape depends on: whether this is one stream or a
            // container of them.
            WDiv(
              className: 'shrink-0 flex flex-row items-center px-2 h-6 rounded bg-fact',
              child: WText(title.isSeries ? 'DİZİ' : 'FİLM', className: 'text-xs font-bold tracking-wide text-fact'),
            ),
            if (rating != null)
              WDiv(
                className: 'shrink-0 flex flex-row items-center gap-1 px-2 h-6 rounded bg-fact',
                children: <Widget>[
                  const WIcon(Icons.star_rounded, className: 'text-xs text-primary'),
                  WText(rating, className: 'text-xs font-bold text-fact'),
                ],
              ),
            for (final String fact in title.facts)
              WDiv(
                className: 'shrink-0',
                child: FactChip(label: fact),
              ),
          ],
        ),
        WDiv(
          className: 'wrap items-center gap-2',
          children: <Widget>[
            WDiv(className: 'shrink-0', child: TitleSections.playVerb(title)),
            WDiv(
              className: 'shrink-0',
              child: FavouriteButton(
                starred: title.favourite,
                subject: title.name,
                shape: 'circle',
                onToggle: () => controller.toggleFavourite(title),
              ),
            ),
            if (wide) WDiv(className: 'shrink-0', child: TitleSections.ghostActions()),
          ],
        ),
        if (!wide) TitleSections.ghostActions(),
        if (title.synopsis == null)
          const WText('Sağlayıcı bu başlık için özet göndermedi.', className: 'text-sm text-fg-disabled')
        else
          WText(title.synopsis!, className: 'text-sm text-fg-muted line-clamp-4 max-w-prose'),
      ],
    );
  }
}
