import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/provider_fault.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/provider_notice/index.dart';
import '../components/rail/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import '../components/title_poster/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';

/// `Vitrin`: the catalogue as a shop window.
///
/// Netflix's browse screen. One title is promoted at hero scale and everything
/// else is a rail, because the screen's job here is to end the decision rather
/// than to help you search: a viewer who opens a catalogue without a title in
/// mind wants to be told, and a grid tells them nothing.
///
/// The hero is a resume rather than a recommendation. Netflix promotes what it
/// wants you to start; with no recommendation engine and a catalogue the user
/// already owns, the honest equivalent is what they left unfinished, which is
/// also the thing a returning viewer opened the app for.
@immutable
class ShowcaseLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [ShowcaseLayout].
  const ShowcaseLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 640;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex flex-col flex-1 min-w-0 h-full',
          children: <Widget>[
            // Above the branch, and that position is the fix rather than a
            // preference. The toolbar used to be a sliver inside the scroll
            // view on one branch and a plain child on the other, so the
            // keystroke that emptied the catalogue rebuilt it from scratch and
            // took the search field's `FocusNode` with it: every key after the
            // one that found nothing went nowhere. `NowLayout` documents the
            // measurement; this is the same trap in the same shape.
            LibraryToolbar(controller: controller, wide: wide),
            PageGutter.gap,
            // Out of the branch for the same reason as the toolbar. It is a
            // horizontal `ListView.builder` and owns a scroll position, which
            // inside the branch was reset to zero by the keystroke that emptied
            // the catalogue.
            LibraryCategories(controller: controller),
            PageGutter.gap,
            WDiv(className: 'flex-1 w-full', child: _body(wide)),
          ],
        ),
      ],
    );
  }

  /// A provider fault, an empty result, or the hero plus the rails.
  ///
  /// A fault takes precedence over an empty result, because they are
  /// different statements: an empty [LibraryController.matches] can mean a
  /// search found nothing while the catalogue is healthy, while a fault means
  /// the provider itself is the problem, and the fault is the more specific
  /// of the two.
  Widget _body(bool wide) {
    final ProviderFault? fault = controller.fault;
    if (fault != null) {
      return ProviderNotice(
        fault: fault,
        onRetry: controller.reload,
        onOpenSettings: () => MagicRoute.to('/saglayici'),
      );
    }

    if (controller.matches.isEmpty) return _emptyBody();

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _hero(wide)),
        const SliverToBoxAdapter(child: PageGutter.gap),
        if (controller.continueWatching.isNotEmpty) SliverToBoxAdapter(child: _resumeRail(wide)),
        SliverList.builder(
          itemCount: controller.sections.length,
          itemBuilder: (BuildContext context, int index) {
            final (String name, List<TitleItem> items) = controller.sections[index];

            return _posterRail(name, items, wide);
          },
        ),
        const SliverToBoxAdapter(child: PageGutter.gap),
      ],
    );
  }

  /// What replaces the hero and the rails when nothing matched.
  ///
  /// Only the body: the toolbar above this is shared with the populated branch,
  /// which is what keeps the search field in one place.
  Widget _emptyBody() {
    return LibraryEmpty(controller: controller);
  }

  /// The promoted title: what the viewer left unfinished, or the first entry.
  TitleItem get _featured =>
      controller.continueWatching.isEmpty ? controller.matches.first : controller.continueWatching.first;

  Widget _hero(bool wide) {
    final TitleItem title = _featured;
    final Episode? next = title.upNext;
    final double progress = title.isSeries ? (next?.progress ?? 0) : title.progress;

    // 440 at desktop, not 540.
    //
    // The hero, the toolbar, the category strip and the first rail come to 949
    // pixels at 540, so on a 900 pixel window the resume rail's caption row was
    // below the fold, and with it the star. The end-to-end walk found it by
    // tapping a control that was in the semantics tree and outside the
    // viewport: nothing moved, and the same case passed on a phone where the
    // hero is shorter. A hero that pushes the first row's labels off the screen
    // is a hero that is too tall, whatever it looks like on its own.
    return WDiv(
      className: 'w-full h-[420px] sm:h-[440px]',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: title.backdropUrl ?? title.posterUrl,
            fallback: const WDiv(className: 'w-full h-full bg-surface-container'),
          ),
          Scrim.left,
          Scrim.bottom,
          // `Align` loosens the tight width a `Positioned` with both `left` and
          // `right` hands down, which is what lets the content block's
          // `max-w-*` apply at all. See the note in `now_layout.dart`.
          Positioned(
            left: PageGutter.value,
            right: PageGutter.value,
            bottom: 32,
            child: Align(alignment: Alignment.centerLeft, child: _heroContent(title, next, wide)),
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

  Widget _heroContent(TitleItem title, Episode? next, bool wide) {
    final String? rating = title.ratingLabel;

    return WDiv(
      className: 'flex flex-col gap-3 w-full max-w-[620px]',
      children: <Widget>[
        WText(title.isSeries ? 'DİZİ' : 'FİLM', className: 'text-xs font-bold tracking-widest text-primary'),
        WText(title.name, className: 'text-3xl sm:text-5xl font-bold text-fg line-clamp-2'),
        // Composed from the parts, not interpolated: a provider entry carries
        // no year and no runtime, and `0 · 0 dk` states two facts it never
        // sent. See `TitleItem.metaLabel`.
        WText(
          <String>[if (title.metaLabel.isNotEmpty) title.metaLabel, if (rating != null) '★ $rating'].join(' · '),
          className: 'text-sm font-medium text-fg-muted',
        ),
        if (title.synopsis != null && wide)
          WText(title.synopsis!, className: 'text-sm text-fg-muted line-clamp-2 max-w-prose'),
        // `wrap` with no `flex` beside it. They are the same parser family and
        // the last one written wins, so `wrap` alone is the form that cannot be
        // got wrong by someone adding a class in front of it. Without the wrap
        // this row ran 110 pixels past a 414 pixel screen.
        WDiv(
          className: 'wrap items-center gap-2',
          children: <Widget>[
            WDiv(className: 'shrink-0', child: _play(title, next)),
            WDiv(
              className: 'shrink-0',
              child: WAnchor(
                onTap: () => controller.openDetail(title),
                semanticLabel: '${title.name} detayı',
                child: const WDiv(
                  className: '''
                    flex flex-row items-center gap-2
                    h-11 px-5 rounded-full
                    bg-scrim-strong text-fg
                    hover:bg-scrim
                    focus:ring-2 focus:ring-focus-ring
                  ''',
                  children: <Widget>[
                    WIcon(Icons.info_outline, className: 'text-base'),
                    WText('Detay', className: 'text-sm font-semibold'),
                  ],
                ),
              ),
            ),
            WDiv(
              className: 'shrink-0',
              child: FavouriteButton(
                starred: title.favourite,
                subject: title.name,
                shape: 'circle',
                onToggle: () => controller.toggleFavourite(title),
              ),
            ),
            for (final String fact in title.facts)
              WDiv(
                className: 'shrink-0',
                child: FactChip(label: fact),
              ),
          ],
        ),
      ],
    );
  }

  /// The one filled button on the screen.
  Widget _play(TitleItem title, Episode? next) {
    final bool resuming = title.isSeries ? (next?.progress ?? 0) > 0.03 : title.progress > 0.03;
    final String label = title.isSeries && next != null
        ? '${resuming ? 'Devam et' : 'Başla'} · ${next.code}'
        : resuming
        ? 'Devam et'
        : 'Oynat';

    return WAnchor(
      onTap: () {},
      semanticLabel: '${title.name} $label',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-2
          h-11 px-6 rounded-full
          bg-primary text-on-primary
          hover:bg-primary-hover
          focus:ring-2 focus:ring-focus-ring
        ''',
        children: <Widget>[
          const WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
          WText(label, className: 'text-sm font-bold'),
        ],
      ),
    );
  }

  /// Continue-watching, as 16:9 stills rather than posters.
  ///
  /// The aspect ratio is doing the work: 2:3 means a title and 16:9 means a
  /// moment inside one, so a rail of stills says "you are partway through
  /// these" before a single word is read. Plex and Netflix both make the same
  /// switch for the same row.
  Widget _resumeRail(bool wide) {
    final List<TitleItem> items = controller.continueWatching;
    final double width = wide ? 280 : 220;

    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.top}',
      children: <Widget>[
        const WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: 'İzlemeye devam et', source: 'Bu cihazda kaldığın yer'),
        ),
        Rail(
          // 16:9 frame, the `gap-2` under it, and the caption's own fixed
          // height, which is what makes this exact rather than a guess.
          height: width * 9 / 16 + 8 + 44,
          itemWidth: width,
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) => _resumeCard(items[index], width),
        ),
      ],
    );
  }

  Widget _resumeCard(TitleItem title, double width) {
    final Episode? next = title.upNext;
    final double progress = title.isSeries ? (next?.progress ?? 0) : title.progress;
    final String caption = title.isSeries && next != null ? '${next.code} · ${next.title}' : title.lengthLabel ?? '';

    return SizedBox(
      width: width,
      child: WDiv(
        className: 'flex flex-col gap-2',
        children: <Widget>[
          WAnchor(
            onTap: () => controller.openDetail(title),
            semanticLabel: '${title.name}, $caption',
            child: WDiv(
              className: 'rounded-lg overflow-hidden focus:ring-2 focus:ring-focus-ring',
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Artwork(
                      src: next?.imageUrl ?? title.backdropUrl ?? title.posterUrl,
                      slotWidth: width,
                      fallback: WDiv(
                        className: 'w-full h-full p-3 items-center justify-center bg-surface-container-high',
                        child: WText(title.name, className: 'text-sm font-bold text-fg-muted text-center line-clamp-3'),
                      ),
                    ),
                    Scrim.flat,
                    Positioned(left: 0, right: 0, bottom: 0, child: PlayProgress(value: progress)),
                  ],
                ),
              ),
            ),
          ),
          // The star is a sibling of the anchor, not a child of it. A WAnchor's
          // `semanticLabel` replaces its descendants' text, so a star nested
          // inside would be unreachable to a screen reader and invisible to the
          // walk that drives this app through the same tree, which is how this
          // rail came to be the one surface in the app showing a title with no
          // way to star it.
          // 44 rather than 40, which is the star's own `size-11`. At 40 the
          // clip took four pixels off the bottom of the control and enough of
          // its hit area with them that the end-to-end walk could tap it
          // without toggling anything.
          WDiv(
            className: 'flex flex-row items-start gap-2 w-full h-[44px] overflow-hidden',
            children: <Widget>[
              WDiv(
                className: 'flex flex-col flex-1 min-w-0',
                children: <Widget>[
                  WText(title.name, className: 'text-sm font-semibold text-fg line-clamp-1'),
                  WText(caption, className: 'text-xs text-fg-muted line-clamp-1'),
                ],
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
          ),
        ],
      ),
    );
  }

  Widget _posterRail(String name, List<TitleItem> items, bool wide) {
    final String size = wide ? 'md' : 'sm';
    final double width = wide ? 168 : 124;

    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.top}',
      children: <Widget>[
        WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(
            title: name,
            source: 'Sağlayıcı kategorisi',
            trailing: WText('${items.length}', className: 'text-sm font-semibold text-fg-muted'),
          ),
        ),
        Rail(
          height: TitlePoster.heightFor(width),
          itemWidth: width,
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) {
            final TitleItem title = items[index];

            return SizedBox(
              width: width,
              child: TitlePoster(
                title: title,
                size: size,
                onTap: () => controller.openDetail(title),
                onToggleFavourite: () => controller.toggleFavourite(title),
              ),
            );
          },
        ),
      ],
    );
  }
}
