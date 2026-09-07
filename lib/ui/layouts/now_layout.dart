import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../components/artwork/index.dart';
import '../components/channel_mark/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/live_tile/index.dart';
import '../components/play_progress/index.dart';
import '../components/rail/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';
import 'support/search_field.dart';

/// Direction one: the screen is about the current minute.
///
/// Netflix's television layout is the starting point (full-bleed key art, one
/// content block in the left third, two buttons, rails underneath) and the
/// departure is the subject. Netflix's hero is a title, which is the same
/// object all day. This one is a broadcast: it has a start, an end, a bar
/// showing how much of it is gone, and a named successor. That is the one piece
/// of information a static channel grid cannot carry, and it is the whole
/// argument for this direction.
///
/// The rails are editorial rather than taxonomic, which the references all do
/// and none of them can do as usefully as a live product: `Daha yeni başladı`
/// and `Yarım saat içinde` are questions only a schedule can answer.
@immutable
class NowLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [NowLayout].
  const NowLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 640;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 min-w-0 h-full',
          child: controller.matches.isEmpty
              ? _emptyBody(wide)
              : CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(child: _hero(wide)),
                    // The gap above the strip and the `PageGutter.top` on the
                    // first rail below it are the same number, which is the
                    // whole point: the strip used to sit eight pixels under the
                    // hero and thirty one above the heading, and the page read
                    // as two designs stacked.
                    const SliverToBoxAdapter(child: PageGutter.gap),
                    SliverToBoxAdapter(child: CategoryStrip(controller: controller, pills: true)),
                    SliverList.builder(
                      itemCount: controller.rails.length,
                      itemBuilder: (BuildContext context, int index) => _rail(controller.rails[index], wide),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
        ),
      ],
    );
  }

  /// The empty state keeps the search and the categories on screen.
  ///
  /// A no-results screen that hides the controls that caused it forces the user
  /// to guess how to get back, and on a remote there is no obvious way to.
  Widget _emptyBody(bool wide) {
    return WDiv(
      className: 'flex flex-col w-full h-full',
      children: <Widget>[
        WDiv(className: '${PageGutter.x} ${PageGutter.top} w-full sm:w-[518px]', child: _search()),
        PageGutter.gap,
        CategoryStrip(controller: controller, pills: true),
        PageGutter.gap,
        WDiv(
          className: 'flex-1 w-full',
          child: GuideEmpty(controller: controller),
        ),
      ],
    );
  }

  Widget _search() {
    return SearchField(value: controller.query, onChanged: controller.search, onScrim: true);
  }

  /// The hero: what is on the selected channel right now.
  Widget _hero(bool wide) {
    final Channel channel = controller.channel;
    final Programme? live = controller.programme;
    final Programme? next = channel.nextAfter(GuideController.now);
    final String? note = controller.noGuideNote;

    return WDiv(
      className: 'w-full h-[420px] sm:h-[520px] relative',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: live?.imageUrl,
            fallback: const WDiv(className: 'w-full h-full bg-surface-container'),
          ),
          Scrim.left,
          Scrim.bottom,
          Positioned(
            top: 16,
            left: PageGutter.value,
            right: PageGutter.value,
            child: WDiv(
              className: 'flex flex-row items-center gap-3 w-full',
              children: <Widget>[
                WDiv(
                  // Fixed above `sm`, growing below it. A `flex-1` with a
                  // `max-w-*` beside it does not clamp: `flex-1` is an
                  // `Expanded`, whose tight minimum beats the maximum.
                  className: wide ? 'w-[470px] shrink-0' : 'flex-1 min-w-0',
                  child: _search(),
                ),
                // The missing-guide note rides with the count, as it does in
                // the other two directions. Without it this one stated the
                // count and left the EPG gap to a rail below the fold, so a
                // user met it one blank card at a time and read it as the app
                // failing rather than as their provider not sending it. Stating
                // the number once turns a recurring glitch into a fact about
                // their subscription.
                // On a scrim, like the search field beside it. This is the one
                // line in the hero that sits over unscrimmed artwork, and the
                // fixture's first backdrop is a bright sky: muted foreground on
                // it was well under the contrast floor the rest of this palette
                // is tested against.
                WDiv(
                  className: 'flex-1 min-w-0 flex flex-row justify-end',
                  children: <Widget>[
                    WDiv(
                      className: 'shrink-0 rounded-full bg-scrim-strong px-3 py-1.5',
                      child: WText(
                        note == null ? controller.countLabel : '${controller.countLabel} · $note',
                        className: 'text-xs font-semibold text-fg line-clamp-1',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // `Align`, and it is load-bearing rather than decorative. A
          // `Positioned` carrying both `left` and `right` hands its child a
          // TIGHT width, and `BoxConstraints.enforce` clamps a `max-w-*` into
          // the incoming range: `clamp(620, 1352, 1352)` is 1352, so the cap on
          // the content block was silently discarded and the hero ran the full
          // width of the window. `Align` loosens the constraint, which is what
          // lets the cap apply.
          //
          // The same mechanism kills a `max-w-*` under any tight parent, not
          // only under a `flex-1`.
          Positioned(
            left: PageGutter.value,
            right: PageGutter.value,
            bottom: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _heroContent(channel, live, next, wide: wide),
            ),
          ),
          if (live != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlayProgress(value: live.progressAt(GuideController.now), tone: 'live', size: 'lg'),
            ),
        ],
      ),
    );
  }

  Widget _heroContent(Channel channel, Programme? live, Programme? next, {required bool wide}) {
    final int left = live == null ? 0 : live.endMinute - GuideController.now;

    return WDiv(
      className: 'flex flex-col gap-3 w-full max-w-[620px]',
      children: <Widget>[
        // Attribution first, at label scale. The channel is what is CARRYING
        // the programme, so it reads like a byline rather than like a title.
        WDiv(
          className: 'flex flex-row items-center gap-2',
          children: <Widget>[
            if (channel.status != ChannelStatus.idle)
              WDiv(
                className: 'shrink-0',
                child: StatusBadge(status: channel.status, solid: true),
              ),
            WDiv(
              className: 'shrink-0 rounded bg-scrim px-1.5 py-1',
              child: ChannelMark(channel: channel, size: 'sm'),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(
                '${channel.name} · ${channel.numberLabel}',
                className: 'text-sm font-semibold text-fg line-clamp-1',
              ),
            ),
          ],
        ),
        WText(live?.title ?? 'Akış bilgisi yok', className: 'text-3xl sm:text-5xl font-bold text-fg line-clamp-2'),
        if (live?.subtitle != null) WText(live!.subtitle!, className: 'text-base text-fg-muted line-clamp-1'),
        if (live != null)
          WText(
            '${live.startLabel} - ${live.endLabel} · ${left > 0 ? '$left dk kaldı' : 'bitmek üzere'}',
            className: 'text-sm font-medium text-primary',
          ),
        if (live?.description != null && wide)
          WText(live!.description!, className: 'text-sm text-fg-muted line-clamp-2 max-w-prose'),
        // One filled button. The references agree on this without exception:
        // Netflix has one white Play, Plex has one amber Devam, and everything
        // beside it is a ghost or an icon.
        //
        // `wrap` with no `flex` beside it. `flex` and `wrap` are the same
        // parser family, so the last one written wins and `flex flex-row wrap`
        // is a wrapping row while `wrap flex` is not: write the one you want
        // last, or write it alone. The row carries a button, a star and up to
        // four fact chips, which is past 414 pixels.
        WDiv(
          className: 'wrap items-center gap-2',
          children: <Widget>[
            WDiv(
              className: 'shrink-0',
              child: WAnchor(
                onTap: () {},
                semanticLabel: live == null ? '${channel.name} izle' : '${live.title} izle',
                child: const WDiv(
                  className: '''
                    flex flex-row items-center gap-2
                    h-11 px-6 rounded-full
                    bg-primary text-on-primary
                    hover:bg-primary-hover
                    focus:ring-2 focus:ring-focus-ring
                  ''',
                  children: <Widget>[
                    WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
                    WText('İzle', className: 'text-sm font-bold'),
                  ],
                ),
              ),
            ),
            // Sibling of the play anchor, not a child. A WAnchor's
            // `semanticLabel` replaces its descendants' text, so a star nested
            // inside would be unreachable to a screen reader and invisible to
            // the walk that drives this app through the same tree.
            WDiv(
              className: 'shrink-0',
              child: FavouriteButton(
                starred: channel.favourite,
                subject: channel.name,
                shape: 'circle',
                onToggle: () => controller.toggleFavourite(channel),
              ),
            ),
            for (final String fact in channel.facts)
              WDiv(
                className: 'shrink-0',
                child: FactChip(label: fact),
              ),
          ],
        ),
        if (next != null)
          WText('Sırada ${next.startLabel} · ${next.title}', className: 'text-xs text-fg-muted line-clamp-1'),
      ],
    );
  }

  Widget _rail(GuideRail rail, bool wide) {
    final double width = wide ? 260 : 200;

    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.top}',
      children: <Widget>[
        // No trailing count. On a 1440 pixel screen a right-aligned number sits
        // a thousand pixels from the title it counts and reads as an orphan;
        // the rail's own length is already visible in the rail.
        WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: rail.title, source: rail.source),
        ),
        Rail(
          // Asked of the tile rather than worked out here. A rail states its
          // cell height before the cell is laid out, so a caller doing this
          // arithmetic itself is a caller guessing at a component's internals.
          height: LiveTile.heightFor(width),
          itemCount: rail.channels.length,
          itemBuilder: (BuildContext context, int index) {
            final Channel channel = rail.channels[index];

            return LiveTile(
              channel: channel,
              programme: channel.programmeAt(GuideController.now),
              now: GuideController.now,
              width: width,
              onTap: () => controller.selectChannel(channel),
              onFavourite: () => controller.toggleFavourite(channel),
            );
          },
        ),
      ],
    );
  }
}
