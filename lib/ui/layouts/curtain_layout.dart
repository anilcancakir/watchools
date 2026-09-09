import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/provider_fault.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/episode_row/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/provider_notice/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import 'support/library_empty.dart';
import 'support/page_gutter.dart';
import 'support/title_sections.dart';

/// `Perde`: the title screen, cinematic and designed for a remote first.
///
/// Netflix's television detail screen. Full-bleed artwork, the title at display
/// scale, one white-weight verb, and then the part worth copying above all: the
/// season list is a SIBLING COLUMN of the episode list rather than a dropdown.
///
/// That is a D-pad decision, not a styling one. A dropdown on a remote costs
/// open, travel, select, close, and hides the two facts that decide which
/// season you want (how many there are, and how far into them you got). Two
/// columns cost one horizontal press, and both facts are on screen the whole
/// time.
///
/// The other thing this screen takes from Netflix is what it leaves out. No
/// poster appears anywhere: the artwork already said what this is, and a poster
/// beside a backdrop of the same title is the same information twice.
@immutable
class CurtainLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [CurtainLayout].
  const CurtainLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // A fault takes precedence over the no-selection arm below, because they
    // are different statements: no selection can mean a healthy but empty
    // catalogue, while a fault means the provider itself is the problem, and
    // the fault is the more specific of the two. It is a new arm rather than
    // a third one, unlike the other three layouts: this screen had no empty
    // branch at all before the previous step added the one below.
    final ProviderFault? fault = controller.fault;
    if (fault != null) {
      return WDiv(
        className: 'w-full h-full bg-surface',
        child: ProviderNotice(
          fault: fault,
          onRetry: controller.reload,
          onOpenSettings: () => MagicRoute.to('/saglayici'),
        ),
      );
    }

    final TitleItem? title = controller.selected;

    // No selection is the normal state during a provider's first refresh
    // (`LibraryController.selected` falls back to `titles.first`, which is
    // null on an empty catalogue) rather than an edge case: this screen had
    // no branch at all before, so a `late TitleItem` read here threw the
    // moment a fixture-free catalogue reached it.
    if (title == null) {
      return WDiv(
        className: 'w-full h-full bg-surface',
        child: LibraryEmpty(controller: controller),
      );
    }

    final bool wide = MediaQuery.sizeOf(context).width >= 900;

    return WDiv(
      className: 'w-full h-full bg-surface',
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _curtain(title, wide)),
          // A film has no season split, so its first section lands directly
          // against the hero's lower edge and the heading collides with the
          // progress bar running along it.
          if (title.isSeries)
            SliverToBoxAdapter(child: _seasonSplit(title, wide))
          else
            const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          // The technical stack, on a series as well as a film. It used to be
          // in the film branch only, so the screen dropped the doctrine's
          // seventh rule exactly where the pages are longest and a viewer is
          // most likely to be checking whether a stream is what the provider
          // called it.
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.specs(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.cast(title)),
          const SliverToBoxAdapter(child: SizedBox(height: PageGutter.value)),
          SliverToBoxAdapter(child: TitleSections.related(controller, title)),
          const SliverToBoxAdapter(child: PageGutter.gap),
        ],
      ),
    );
  }

  Widget _curtain(TitleItem title, bool wide) {
    final Episode? next = title.upNext;
    final double progress = title.isSeries ? (next?.progress ?? 0) : title.progress;

    return WDiv(
      className: 'w-full h-[460px] sm:h-[600px]',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: title.backdropUrl ?? title.posterUrl,
            fallback: const WDiv(className: 'w-full h-full bg-surface-container'),
          ),
          Scrim.left,
          Scrim.bottom,
          Positioned(
            top: PageGutter.value,
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
          // `Align` loosens the tight width a `Positioned` with both `left` and
          // `right` hands down, which is what lets the content block's
          // `max-w-*` apply at all. See the note in `now_layout.dart`.
          Positioned(
            left: PageGutter.value,
            right: PageGutter.value,
            bottom: 36,
            child: Align(alignment: Alignment.centerLeft, child: _content(title, next, wide)),
          ),
          if (progress > 0.03 && progress < 0.92)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlayProgress(value: progress, size: 'lg'),
            ),
        ],
      ),
    );
  }

  Widget _content(TitleItem title, Episode? next, bool wide) {
    final String? rating = title.ratingLabel;

    return WDiv(
      className: 'flex flex-col gap-4 w-full max-w-[640px]',
      children: <Widget>[
        WText(title.isSeries ? 'DİZİ' : 'FİLM', className: 'text-xs font-bold tracking-widest text-primary'),
        WText(title.name, className: 'text-4xl sm:text-6xl font-bold text-fg line-clamp-2'),
        // Netflix's meta line, with its match percentage replaced by the rating
        // the provider actually sends. Inventing a match score with no
        // recommendation engine behind it would be a number that means nothing.
        WDiv(
          className: 'flex flex-row items-center gap-3',
          children: <Widget>[
            if (rating != null) WText('★ $rating', className: 'shrink-0 text-sm font-bold text-primary'),
            WText('${title.year} · ${title.lengthLabel}', className: 'shrink-0 text-sm font-medium text-fg-muted'),
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(
                title.genres.isEmpty ? '' : title.genres.join(' · '),
                className: 'text-sm text-fg-disabled line-clamp-1',
              ),
            ),
          ],
        ),
        // The empty case says so rather than leaving a gap. This screen had no
        // such state at all: a provider that sends no synopsis is the common
        // case, and a hero that simply omits the paragraph reads as a page that
        // failed to load rather than as a provider that sent nothing.
        if (title.synopsis == null)
          const WText('Sağlayıcı bu başlık için özet göndermedi.', className: 'text-base text-fg-disabled')
        else if (wide)
          WText(title.synopsis!, className: 'text-base text-fg-muted line-clamp-3 max-w-prose'),
        if (next != null && title.isSeries)
          WText('Sırada ${next.code} · ${next.title}', className: 'text-sm font-semibold text-fg line-clamp-1'),
        WDiv(
          className: 'wrap items-center gap-3',
          children: <Widget>[
            WDiv(className: 'shrink-0', child: TitleSections.playVerb(title)),
            WDiv(
              className: 'shrink-0',
              child: FavouriteButton(
                starred: title.favourite,
                subject: title.name,
                shape: 'pill',
                onToggle: () => controller.toggleFavourite(title),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The two columns. Seasons on the left, episodes on the right.
  ///
  /// Below 900 pixels there is no room for both, so the seasons become the
  /// shared horizontal chip rail. That is a real concession rather than a
  /// responsive trick: the two-column arrangement is this screen's whole
  /// argument, and it only holds at television and desktop widths.
  Widget _seasonSplit(TitleItem title, bool wide) {
    if (!wide) {
      return WDiv(
        className: 'flex flex-col gap-6 w-full ${PageGutter.top}',
        children: <Widget>[TitleSections.seasons(controller, title), TitleSections.episodes(controller, title)],
      );
    }

    final List<int> numbers = title.seasons;
    final List<Episode> list = title.episodesOf(controller.season);
    final Episode? next = title.upNext;

    return WDiv(
      className: 'flex flex-row items-start gap-8 w-full ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        WDiv(
          className: 'w-[240px] shrink-0',
          child: WDiv(
            className: 'flex flex-col gap-1 w-full',
            children: <Widget>[
              const WDiv(
                className: 'pb-2',
                child: SectionHeader(title: 'Sezonlar'),
              ),
              for (final int season in numbers) _seasonRow(title, season),
            ],
          ),
        ),
        WDiv(
          className: 'flex-1 min-w-0',
          child: WDiv(
            className: 'flex flex-col gap-2 w-full',
            children: <Widget>[
              SectionHeader(
                title: '${controller.season}. sezon',
                source: title.category,
                trailing: WText('${list.length} bölüm', className: 'text-sm font-semibold text-fg-muted'),
              ),
              if (list.isEmpty)
                const WDiv(
                  className: 'w-full p-4 rounded-lg border border-color-border-subtle',
                  child: WText('Bu sezon için bölüm bilgisi gelmedi.', className: 'text-sm text-fg-muted'),
                )
              else
                for (final Episode episode in list)
                  EpisodeRow(episode: episode, density: 'full', selected: identical(episode, next), onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }

  /// One season in the left column.
  ///
  /// Netflix reveals the episode count on the focused row only, which keeps a
  /// nine season list from reading as a table. The ring rather than a fill is
  /// the same rule the rest of this app follows: on a remote, focus moves on
  /// every keypress and selection does not.
  Widget _seasonRow(TitleItem title, int season) {
    final int count = title.episodesOf(season).length;
    final bool selected = controller.season == season;

    return WAnchor(
      onTap: () => controller.selectSeason(season),
      semanticLabel: '$season. sezon, $count bölüm',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-2 w-full h-11 px-3 rounded-lg
          text-fg-muted
          hover:text-fg hover:bg-surface-container
          focus:ring-2 focus:ring-focus-ring
          selected:bg-surface-container-high selected:text-fg
        ''',
        states: selected ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          WDiv(
            className: 'flex-1 min-w-0',
            child: WText('$season. Sezon', className: 'text-sm font-semibold line-clamp-1'),
          ),
          if (selected)
            WDiv(
              className: 'shrink-0',
              child: WText('$count bölüm', className: 'text-xs text-fg-muted'),
            ),
        ],
      ),
    );
  }
}
