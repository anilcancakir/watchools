import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/controllers/playback_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../../app/models/provider_fault.dart';
import '../components/artwork/index.dart';
import '../components/channel_mark/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/live_tile/index.dart';
import '../components/play_progress/index.dart';
import '../components/provider_notice/index.dart';
import '../components/rail/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/guide_toolbar_metrics.dart';
import 'support/guide_view_switch.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';
import 'support/search_field.dart';

/// `Şimdi`: the screen is about the current minute.
///
/// Netflix's television layout is the starting point (full-bleed key art, one
/// content block in the left third, two buttons, rails underneath) and the
/// departure is the subject. Netflix's hero is a title, which is the same
/// object all day. This one is a broadcast: it has a start, an end, a bar
/// showing how much of it is gone, and a named successor. That is the one piece
/// of information a static channel grid cannot carry, and it is the whole
/// argument for this view.
///
/// The rails are editorial rather than taxonomic, which the references all do
/// and none of them can do as usefully as a live product: `Daha yeni başladı`
/// and `Yarım saat içinde` are questions only a schedule can answer.
///
/// It is the arrival screen. `Zaman` is the other half of the same line-up and
/// is one tap away on the toolbar's switch.
@immutable
class NowLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Where the hero's play affordance goes, defaulting to pushing the route.
  ///
  /// Only the **navigation** is a seam, because `MagicRouter` throws `Router
  /// not initialized` without a `MaterialApp.router` above it and a widget test
  /// has none. Everything else the affordance does (select, then hand the
  /// channel to the playback controller) runs in a test as it runs in the app,
  /// which is the correction to a first version where the whole sequence sat in
  /// an untested default branch.
  final VoidCallback? onNavigate;

  /// The playback handle, or null to resolve one from the container.
  final PlaybackFacade? playbackOverride;

  /// Creates the [NowLayout].
  const NowLayout({super.key, required this.controller, this.onNavigate, this.playbackOverride});

  /// Starts [channel] and goes to the playback screen.
  ///
  /// Selects first, so returning from playback finds the hero showing what was
  /// just watched rather than whatever was selected before it.
  ///
  /// `play` before the push and not after, which reads backwards and is
  /// correct: the controller **holds** a channel chosen before a surface
  /// exists and opens it when the screen's `attach` arrives. Pushing first and
  /// playing after would race the platform view's creation instead.
  void _play(Channel channel) {
    controller.selectChannel(channel);
    (playbackOverride ?? Magic.find<PlaybackController>()).play(channel);
    (onNavigate ?? () => MagicRoute.to('/izle'))();
  }

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
            // preference. The field used to live inside the hero on one branch
            // and inside a plain column on the other, so the keystroke that
            // emptied the line-up rebuilt it from scratch and took `WInput`'s
            // `FocusNode` with it: measured in a browser, typing `z`, `q`, `x`,
            // `v` into this view left the field holding `z`, while the same
            // keys in `Zaman`, whose toolbar was already outside its branch,
            // produced `zqxv`. A `GlobalKey` carried the element but not the
            // web text-editing connection, and neither did forcing the focus
            // back. One position is the only shape that works.
            // The toolbar reads its OWN width, not the window's: it sits inside a
            // column the nav rail has narrowed, and `wide` is the rail's own
            // viewport breakpoint. See `guideToolbarOneLineAt`.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  _toolbar(oneLine: constraints.maxWidth >= guideToolbarOneLineAt),
            ),
            PageGutter.gap,
            // Out of the branch for the same reason as the toolbar, one rung
            // down. It is a horizontal `ListView.builder`, so it owns a scroll
            // position, and inside the branch a viewer who had scrolled to a
            // far category got it back at zero the moment their query stopped
            // matching. `Zaman` puts it in this exact place.
            CategoryStrip(controller: controller),
            PageGutter.gap,
            WDiv(className: 'flex-1 w-full', child: _body(wide)),
          ],
        ),
      ],
    );
  }

  /// The body: a provider fault, an empty result, or the hero plus the rails.
  ///
  /// A fault takes precedence over an empty result, because they are
  /// different statements: an empty [matches] can mean a search found
  /// nothing while the line-up is healthy, while a fault means the provider
  /// itself is the problem, and the fault is the more specific of the two.
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

    // Non-null: `matches` is a filtered subset of `channels`, so a non-empty
    // match list guarantees `channels` is non-empty and `channel` (which
    // falls back to `channels.first`) cannot be null on this branch.
    final Channel channel = controller.channel!;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _heroScope(channel, wide: wide)),
        const SliverToBoxAdapter(child: PageGutter.gap),
        SliverList.builder(
          itemCount: controller.rails.length,
          itemBuilder: (BuildContext context, int index) => _rail(controller.rails[index], wide),
        ),
        // One gutter, not the 96 that used to clear the floating switcher.
        // The switch is in the toolbar now, so a tail that size is just an
        // unexplained hole under the last rail.
        const SliverToBoxAdapter(child: PageGutter.gap),
      ],
    );
  }

  /// What replaces the hero and the rails when nothing matched.
  ///
  /// Only the body. The search, the categories and the view switch are above
  /// this and shared with the populated branch, which is both the fix for the
  /// focus bug and what the doc for this method always claimed: a no-results
  /// screen that hides the controls that caused it forces the user to guess how
  /// to get back, and on a remote there is no obvious way to. The switch is on
  /// that list for a second reason: the other view is a legitimate answer to an
  /// empty result, and losing the way to it here would strand a viewer on the
  /// one cut of the line-up that found nothing.
  Widget _emptyBody() {
    return GuideEmpty(controller: controller);
  }

  /// The hero, rebuilt only when the minute, the selection or the width moves.
  ///
  /// It is the largest block on the screen and the query is not one of its
  /// inputs, so before this it redrew the artwork, both scrims, the title, the
  /// countdown, the play button, the star and every fact chip on each character
  /// the user typed into the field above it.
  ///
  /// `wide` is in the selected value even though it is not a controller field,
  /// and leaving it out is the trap this optimisation brings with it: the
  /// builder captures it from the enclosing `build`, a cached subtree cannot
  /// see anything its closure captured, and the hero would then hold whichever
  /// form it was first built in until the clock or the selection happened to
  /// move. `MediaQuery` read INSIDE the subtree would not need this, because a
  /// dependent element is rebuilt directly rather than through its parent;
  /// `wide` is read outside it.
  /// [channel] arrives as an argument rather than being read off the
  /// controller inside the selector, and that is about the branch above rather
  /// than about caching. `_body` reaches this line only after ruling out a
  /// fault and an empty result, which is what makes `controller.channel`
  /// non-null; the selector closure runs again on every notification, including
  /// the one that empties the line-up, so reading it there would put a `!` on a
  /// field that is null at exactly that moment. It is still IN the selected
  /// tuple, so a change of channel still busts the cache: the parent rebuilds,
  /// the new closure returns a different record, and the cached subtree is
  /// discarded.
  Widget _heroScope(Channel channel, {required bool wide}) {
    return MagicSelector<GuideController, (Channel, Programme?, int, bool)>(
      controller: controller,
      selector: (GuideController c) => (channel, c.programme, c.now, wide),
      builder: ((Channel, Programme?, int, bool) state) => _hero(state.$1, state.$2, now: state.$3, wide: state.$4),
    );
  }

  /// The hero: what is on the selected channel right now.
  ///
  /// Every input is a parameter, none is read off the controller. A cached
  /// subtree cannot see anything its closure captured, so a field read here
  /// would hold whatever it said when the subtree was first built.
  Widget _hero(Channel channel, Programme? live, {required int now, required bool wide}) {
    final Programme? next = channel.nextAfter(now);

    // 440 at desktop, not 520.
    //
    // The toolbar and the category strip are pinned above this now, which costs
    // roughly 156 pixels the hero used to have, and a 520 pixel hero then
    // pushed the first rail's caption row below the fold on a 900 pixel window:
    // the channel name and the `N dk kaldı` under each card, which is the half
    // of a live tile that says what it is. `showcase_layout` was cut from 540
    // to 440 for exactly this, by exactly this measurement.
    return WDiv(
      className: 'w-full h-[420px] sm:h-[440px] relative',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: live?.imageUrl,
            fallback: const WDiv(className: 'w-full h-full bg-surface-container'),
          ),
          Scrim.left,
          Scrim.bottom,
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
              child: _heroContent(channel, live, next, now: now, wide: wide),
            ),
          ),
          if (live != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlayProgress(value: live.progressAt(now), tone: 'live', size: 'lg'),
            ),
        ],
      ),
    );
  }

  /// The search field, the missing-guide count and the view switch.
  ///
  /// Above the scrolling body rather than over the hero's artwork, which is
  /// what makes the field's position independent of the result count. It also
  /// settles a consistency debt: `Zaman` already pinned its toolbar in exactly
  /// this place, so the two live views now differ below the toolbar and nowhere
  /// above it, and the doctrine's rule that search is a peer of navigation
  /// rather than a mode is kept on both.
  ///
  /// No scrim on any of it any more. The bar sits on the page surface, so the
  /// count is a plain label and the switch takes its normal form; a
  /// `bg-scrim-strong` chip here would be a dark pill on a dark page with
  /// nothing behind it to justify the contrast.
  ///
  /// One line when the row can hold one, two when it cannot, and the threshold
  /// is the row's OWN width rather than the window's. That distinction is the
  /// whole defect this method shipped: the arrangement used to key off `wide`,
  /// which is the nav rail's 640 pixel viewport breakpoint, while the single
  /// line needs the fixed 470 pixel field plus both gaps plus the switch plus
  /// enough of the count to be worth reading. Between those two numbers the row
  /// spilled, by 110 pixels on the running app and by up to 148 measured in a
  /// widget test at 640. `CLAUDE.md` names this exact trap first among the
  /// four, and prescribes this exact fix: a component whose columns depend on
  /// real width takes a `double` and decides in Dart.
  ///
  /// Stacked is not a fallback. At 414 pixels the count is a whole sentence
  /// (`1 sonuç · 1 kanalda akış yok`), and once the field has text its clear
  /// button appears and the row runs 5.6 pixels past the screen. The catalogue
  /// toolbar reached the same conclusion for the same reason.
  ///
  /// The switch is last on the line at both widths and is the fixed-width
  /// element, so the count grows leftwards into the space instead of pushing a
  /// control around as the user types.
  ///
  /// The count carries the missing-guide note as the grid view does. Without it
  /// this one stated the count and left the EPG gap to a rail below the fold,
  /// so a user met it one blank card at a time and read it as the app failing
  /// rather than as their provider not sending it. That note is also why the
  /// threshold reserves the count a readable minimum rather than letting it
  /// ellipsise to nothing: a single line whose count has been squeezed to a few
  /// pixels has dropped the sentence entirely and says less than two lines do.
  Widget _toolbar({required bool oneLine}) {
    final String? note = controller.noGuideNote;

    // `flex-1 min-w-0` and not `shrink-0`, and this is the fix rather than a
    // preference: the count is the only element on this row that has no width
    // of its own, so it has to be the one that gives. It used to be
    // `shrink-0`, which made `line-clamp-1` decorative, since a clamp with no
    // bounded width has nothing to clamp against. Measured on the running app
    // against a real provider: a 110 pixel overflow at an 800 pixel window,
    // where the note makes the sentence `8 kanal · 8 kanalda akış yok`.
    //
    // The alignment is per branch rather than shared, because the count sits
    // against the switch on one line and against the left edge on two. Only
    // the wide branch reads as "grows leftwards into the space", and passing
    // `text-right` there is what preserves that; the narrow branch keeps the
    // count where the eye already finds it.
    Widget count({required String align}) => WDiv(
      className: 'flex-1 min-w-0',
      child: WText(
        note == null ? controller.countLabel : '${controller.countLabel} · $note',
        className: 'text-xs text-fg-muted $align line-clamp-1',
      ),
    );

    final Widget search = WDiv(
      className: oneLine ? 'w-[470px] shrink-0' : 'w-full',
      child: SearchField(value: controller.query, onChanged: controller.search),
    );

    if (!oneLine) {
      return WDiv(
        className: 'flex flex-col items-start gap-2 w-full ${PageGutter.x} ${PageGutter.top}',
        children: <Widget>[
          search,
          WDiv(
            className: 'flex flex-row items-center gap-2 w-full',
            children: <Widget>[
              count(align: 'text-left'),
              GuideViewSwitch(controller: controller),
            ],
          ),
        ],
      );
    }

    return WDiv(
      className: 'flex flex-row items-center gap-3 w-full ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        // No bare spacer any more: the count is the flexible child now, so a
        // second one would split the free space between them and the count
        // would start truncating while half the row stood empty. It is still
        // three children, and the switch is still the fixed element anchoring
        // the right edge.
        search,
        count(align: 'text-right'),
        GuideViewSwitch(controller: controller),
      ],
    );
  }

  Widget _heroContent(Channel channel, Programme? live, Programme? next, {required int now, required bool wide}) {
    final int left = live == null ? 0 : live.endMinute - now;

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
                // The play affordance is what navigates; the tile's own tap
                // keeps selecting. The hero exists to preview, so a tap that
                // both previewed and left the screen would make the preview
                // unreachable.
                onTap: () => _play(channel),
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
          itemWidth: width,
          itemCount: rail.channels.length,
          itemBuilder: (BuildContext context, int index) {
            final Channel channel = rail.channels[index];

            return LiveTile(
              channel: channel,
              programme: channel.programmeAt(controller.now),
              now: controller.now,
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
