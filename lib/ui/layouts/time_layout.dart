import 'package:flutter/material.dart' show Icons;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../../app/models/provider_fault.dart';
import '../components/channel_mark/index.dart';
import '../components/favourite_button/index.dart';
import '../components/provider_notice/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/guide_toolbar_metrics.dart';
import 'support/guide_view_switch.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';
import 'support/search_field.dart';
import 'support/time_axis.dart';

/// `Zaman`: a real broadcast grid.
///
/// The only view where 20:55 and 21:30 are on screen at the same moment, and
/// the only one where a programme that already ended is reachable. Both follow
/// from the same choice: time is an axis rather than a label, so the past is
/// simply the part of the axis to the left of the now line, and catch-up turns
/// it into something you can play.
///
/// No reference does this, because none of them has to. Netflix and Plex are
/// catalogues where every item is available at every moment; a broadcast
/// line-up is the one product where "when" is a real dimension, and refusing to
/// draw it is what makes most IPTV clients feel like a list of URLs.
///
/// A channel with no schedule gets one block spanning the whole window saying
/// so, at the same row height as everything else. An empty row would read as a
/// failed render in exactly the place a user is most likely to blame the app.
class TimeLayout extends StatefulWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [TimeLayout].
  const TimeLayout({super.key, required this.controller});

  @override
  State<TimeLayout> createState() => _TimeLayoutState();
}

class _TimeLayoutState extends State<TimeLayout> {
  /// Pixels per minute of the window. Six puts a thirty minute slot at 180
  /// pixels, which is the narrowest a Turkish programme title survives.
  static const double _ppm = 6;

  /// One grid row's height.
  static const double _row = 68;

  /// Below this the pinned identity column drops to its narrow form.
  ///
  /// At 414 pixels the page gutter leaves a 366 pixel row, and a 248 pixel
  /// identity column leaves 118 for the schedule: the grid overflowed by 34
  /// pixels and, where it did not, showed a sliver of one programme block. The
  /// narrow column carries the mark and the number and drops the name, which
  /// the mark already stands for.
  static const double _narrowAt = 720;

  /// The ruler and the grid body are separate horizontal viewports, and the
  /// identity column and the grid body are separate vertical ones. Flutter will
  /// not attach one `ScrollController` to two live positions, so each pair is
  /// kept in step by hand.
  ///
  /// `_syncing` is not defensive: without it, writing to the follower fires the
  /// follower's own listener, which writes back to the leader mid-frame and the
  /// two chase each other into a jitter that only shows up under a fast flick.
  final ScrollController _rulerH = ScrollController();
  final ScrollController _gridH = ScrollController();
  final ScrollController _markV = ScrollController();
  final ScrollController _gridV = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _gridH.addListener(() => _mirror(_gridH, _rulerH));
    _gridV.addListener(() => _mirror(_gridV, _markV));
    _markV.addListener(() => _mirror(_markV, _gridV));
  }

  void _mirror(ScrollController from, ScrollController to) {
    // Both guards fix the same reported failure and neither is defensive.
    //
    // `mounted`: a scroll listener can fire while the tree is being torn down,
    // and a `jumpTo` then schedules a frame nobody will see.
    //
    // The scheduler phase is the load-bearing one. `jumpTo` from inside the
    // persistent-callbacks phase asks for a render mid-frame, and on Flutter
    // web a hot restart has already disposed the old `EngineFlutterView` by the
    // time that render lands: every interaction with this view produced
    // `Trying to render a disposed EngineFlutterView`
    // (`engine/window.dart:99`). It was invisible until the walk's exception
    // gate was re-armed, because the framework reports it through
    // `PlatformDispatcher.onError` rather than through the buffer the gate used
    // to count.
    if (!mounted || _syncing || !to.hasClients || !from.hasClients) return;
    if (to.offset == from.offset) return;

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _mirror(from, to));
      return;
    }

    _syncing = true;
    to.jumpTo(from.offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _rulerH.dispose();
    _gridH.dispose();
    _markV.dispose();
    _gridV.dispose();
    super.dispose();
  }

  GuideController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 640;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 min-w-0 h-full',
          child: WDiv(
            className: 'flex flex-col w-full h-full',
            children: <Widget>[
              // One rhythm down the page: every block is the same distance from
              // the one above it, and the grid's own ruler carries the last of
              // those gaps as its top padding rather than butting against the
              // strip.
              // The toolbar reads its OWN width, not the window's: it sits inside a
              // column the nav rail has narrowed, and `wide` is the rail's own
              // viewport breakpoint. See `guideToolbarOneLineAt`.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    _toolbar(oneLine: constraints.maxWidth >= guideToolbarOneLineAt),
              ),
              PageGutter.gap,
              CategoryStrip(controller: controller),
              PageGutter.gap,
              WDiv(className: 'flex-1 w-full', child: _body(context)),
            ],
          ),
        ),
      ],
    );
  }

  /// The search field, the count and the view switch.
  ///
  /// The same arrangement `Şimdi` puts over its hero, at the same widths, in
  /// the same order: search, then the count, then the switch anchoring the
  /// right edge. The two views are meant to feel like two cuts of one screen
  /// rather than two screens, and a control that moves between them is the
  /// fastest way to break that.
  ///
  /// One line above `sm` and two below it. The count is a whole sentence
  /// (`23 kanal · 3 kanalda akış yok`), and beside a field and a two-segment
  /// switch it does not share 366 pixels with them.
  ///
  /// The field is fixed-width above `sm` rather than `flex-1` with a maximum
  /// beside it: `flex-1` is an `Expanded` and its tight minimum beats the
  /// maximum. `w-full shrink-0` is what the first version wrote and it
  /// overflowed by exactly the count's width, because `w-full` claims the whole
  /// row and `shrink-0` then refuses to give any of it back. The count then
  /// repeated that mistake one element along; see its own comment below.
  Widget _toolbar({required bool oneLine}) {
    final String? note = controller.noGuideNote;

    final Widget search = WDiv(
      className: oneLine ? 'w-[470px] shrink-0' : 'w-full',
      child: SearchField(value: controller.query, onChanged: controller.search),
    );

    // `flex-1 min-w-0` and not `shrink-0`, the same correction `Şimdi`'s
    // toolbar took and for the same reason: the count is the only element on
    // this row with no width of its own, so it has to be the one that gives.
    // `shrink-0` made `line-clamp-1` decorative, because a clamp with no
    // bounded width has nothing to clamp against, and the row overflowed by
    // the amount the sentence exceeded the space left over. Measured at 110
    // pixels on `Şimdi` at an 800 pixel window; this view carries the same
    // sentence in the same arrangement.
    //
    // The alignment is per branch: the count sits against the switch on one
    // line and against the left edge on two.
    Widget count({required String align}) => WDiv(
      className: 'flex-1 min-w-0',
      child: WText(
        note == null ? controller.countLabel : '${controller.countLabel} · $note',
        className: 'text-xs text-fg-muted $align line-clamp-1',
      ),
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
        // No bare spacer: the count is the flexible child now, and a second
        // one would split the free space and start truncating the sentence
        // while half the row stood empty.
        search,
        count(align: 'text-right'),
        GuideViewSwitch(controller: controller),
      ],
    );
  }

  /// A provider fault, an empty result, or the grid.
  ///
  /// A fault takes precedence over an empty result, because they are
  /// different statements: an empty [matches] can mean a search found
  /// nothing while the line-up is healthy, while a fault means the provider
  /// itself is the problem, and the fault is the more specific of the two.
  Widget _body(BuildContext context) {
    final ProviderFault? fault = controller.fault;
    if (fault != null) {
      return ProviderNotice(
        fault: fault,
        onRetry: controller.reload,
        onOpenSettings: () => MagicRoute.to('/saglayici'),
      );
    }

    return controller.matches.isEmpty ? GuideEmpty(controller: controller) : _grid(context);
  }

  Widget _grid(BuildContext context) {
    final List<Channel> rows = controller.matches;
    const double width = GuideController.windowMinutes * _ppm;
    final double nowX = (controller.now - controller.windowStart) * _ppm;
    final bool narrow = MediaQuery.sizeOf(context).width < _narrowAt;

    // The ruler's inset has to equal the identity column exactly, or every time
    // label is offset from the block it names by the difference. One value,
    // spent twice.
    //
    // 120 on a phone rather than 92: the star stays in the narrow cell, and a
    // mark, a number and a star do not fit in 92.
    final String column = narrow ? 'w-[120px] shrink-0' : 'w-[248px] shrink-0';

    return WDiv(
      className: 'flex flex-col w-full h-full',
      children: <Widget>[
        _ruler(column: column),
        WDiv(
          className: 'flex-1 w-full',
          child: WDiv(
            className: 'flex flex-row w-full h-full ${PageGutter.x} pb-4',
            children: <Widget>[
              WDiv(
                className: '$column h-full',
                child: ListView.builder(
                  controller: _markV,
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemExtent: _row,
                  itemBuilder: (BuildContext context, int index) => _identityCell(rows[index], narrow: narrow),
                ),
              ),
              WDiv(
                className: 'flex-1 min-w-0 h-full relative',
                child: SingleChildScrollView(
                  controller: _gridH,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ListView.builder(
                            controller: _gridV,
                            padding: EdgeInsets.zero,
                            itemCount: rows.length,
                            itemExtent: _row,
                            itemBuilder: (BuildContext context, int index) => _blocks(rows[index]),
                          ),
                        ),
                        // The now line, drawn over every row at once. It is the
                        // one element in this view that belongs to the
                        // whole grid rather than to a row, so it is painted on
                        // top of the list rather than repeated inside it.
                        Positioned(
                          left: nowX,
                          top: 0,
                          bottom: 0,
                          // No `h-full`: `top` plus `bottom` is already a tight
                          // height, and the class would only add a
                          // `LayoutBuilder`. See `_block` for the measurement.
                          child: const WDiv(className: 'w-[2px] bg-live'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The ruler, rebuilt only when the window, the minute or the column width
  /// moves.
  ///
  /// It draws ten half-hour ticks and knows nothing about the query, so a
  /// keystroke that re-filtered the rows below it used to redraw every one of
  /// them. `column` is in the selected value for the reason `now_layout`'s hero
  /// records: it is captured from the enclosing build, and a cached subtree
  /// cannot see anything its closure captured.
  Widget _ruler({required String column}) {
    return MagicSelector<GuideController, (int, int, String)>(
      controller: controller,
      selector: (GuideController c) => (c.windowStart, c.now, column),
      builder: ((int, int, String) state) => _rulerRow(windowStart: state.$1, now: state.$2, column: state.$3),
    );
  }

  /// Its left inset matches the identity column exactly, and it is a separate
  /// viewport rather than a row inside the grid so that scrolling down never
  /// scrolls the times away.
  Widget _rulerRow({required int windowStart, required int now, required String column}) {
    return WDiv(
      className: 'flex flex-row w-full shrink-0 ${PageGutter.x} pb-1',
      children: <Widget>[
        WDiv(
          className: '$column flex flex-row items-center',
          child: const WText('BUGÜN', className: 'text-[11px] font-bold text-fg-disabled'),
        ),
        WDiv(
          className: 'flex-1 min-w-0',
          child: SingleChildScrollView(
            controller: _rulerH,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: TimeAxis(pixelsPerMinute: _ppm, windowStart: windowStart, now: now),
          ),
        ),
      ],
    );
  }

  /// One channel in the pinned column.
  ///
  /// The narrow form drops the written name and keeps the mark, the number and
  /// the star. Dropping the name is the right cut rather than the convenient
  /// one: the mark is derived FROM the name, so it already stands for it, while
  /// the number is the only thing that separates two channels a provider gave
  /// near-identical names.
  ///
  /// It stacks the mark over the number rather than putting them in a row, and
  /// that is arithmetic rather than taste. In a row the 120 pixel column leaves
  /// the number twenty pixels after the star, the padding, the gaps and a 32
  /// pixel mark, and `001` needs nineteen at eleven point tabular: it fitted by
  /// a hair, wrapped one character per line the moment anything grew, and a
  /// four digit line-up would have wrapped outright. Stacked, the number has
  /// the whole cell width and the two together are 52 of the 60 available.
  ///
  /// The star stays. The first version of this cut it along with the name and
  /// the end-to-end walk failed on `Zaman: has a favourite control` at 414
  /// pixels: favourites are the one thing that makes a ten thousand channel
  /// line-up usable, so a view that cannot star on a phone is a view that does
  /// not work on a phone.
  Widget _identityCell(Channel channel, {required bool narrow}) {
    final bool selected = identical(channel, controller.channel);

    return WDiv(
      className: 'flex flex-row items-center gap-2 w-full h-[68px] pr-2',
      children: <Widget>[
        WDiv(
          className: 'flex-1 min-w-0',
          child: WAnchor(
            onTap: () => controller.selectChannel(channel),
            semanticLabel: '${channel.numberLabel} ${channel.name}',
            child: WDiv(
              className: narrow
                  ? '''
                    flex flex-col items-center justify-center gap-1
                    w-full h-[60px] px-1 rounded-lg
                    hover:bg-surface-container
                    focus:ring-2 focus:ring-focus-ring
                    selected:bg-surface-container-high
                  '''
                  : '''
                    flex flex-row items-center gap-2 w-full h-[60px] px-2 rounded-lg
                    hover:bg-surface-container
                    focus:ring-2 focus:ring-focus-ring
                    selected:bg-surface-container-high
                  ''',
              states: selected ? const <String>{'selected'} : const <String>{},
              children: <Widget>[
                WDiv(
                  className: 'shrink-0',
                  child: ChannelMark(channel: channel, size: 'sm'),
                ),
                if (narrow)
                  WDiv(
                    className: 'shrink-0',
                    child: WText(
                      channel.numberLabel,
                      className: 'text-[11px] text-fg-disabled',
                      textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                    ),
                  )
                else ...<Widget>[
                  WDiv(
                    className: 'flex-1 min-w-0',
                    child: WDiv(
                      className: 'flex flex-col',
                      children: <Widget>[
                        WText(channel.name, className: 'text-sm font-semibold text-fg line-clamp-1'),
                        WText(
                          channel.numberLabel,
                          className: 'text-xs text-fg-disabled',
                          textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                  if (channel.status == ChannelStatus.live)
                    const WDiv(className: 'shrink-0 size-2 rounded-full bg-live'),
                ],
              ],
            ),
          ),
        ),
        WDiv(
          className: 'shrink-0',
          child: FavouriteButton(
            starred: channel.favourite,
            subject: channel.name,
            onToggle: () => controller.toggleFavourite(channel),
          ),
        ),
      ],
    );
  }

  /// One channel's strip of programme blocks, positioned by time.
  Widget _blocks(Channel channel) {
    final int start = controller.windowStart;
    final int end = start + GuideController.windowMinutes;

    if (!channel.hasSchedule) {
      return const SizedBox(
        height: _row,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 4,
              bottom: 4,
              width: GuideController.windowMinutes * _ppm - 4,
              child: WDiv(
                className: '''
                  flex flex-row items-center gap-2 px-3 rounded-lg
                  border border-color-border-subtle
                ''',
                children: <Widget>[
                  WIcon(Icons.event_busy_outlined, className: 'text-sm text-fg-disabled'),
                  WText('Bu kanal için yayın akışı gelmedi', className: 'text-xs text-fg-disabled'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> blocks = <Widget>[];

    for (final Programme programme in channel.schedule) {
      if (programme.endMinute <= start || programme.startMinute >= end) continue;

      final int from = programme.startMinute < start ? start : programme.startMinute;
      final int to = programme.endMinute > end ? end : programme.endMinute;

      blocks.add(
        Positioned(
          left: (from - start) * _ppm,
          width: (to - from) * _ppm - 4,
          top: 4,
          bottom: 4,
          child: _block(channel, programme),
        ),
      );
    }

    return SizedBox(
      height: _row,
      child: Stack(children: blocks),
    );
  }

  Widget _block(Channel channel, Programme programme) {
    final int now = controller.now;
    final bool past = programme.endMinute <= now;
    final bool live = programme.contains(now);
    final bool selected = identical(programme, controller.programme);

    // Three tones for three relationships with the now line. Past is not
    // greyed-out-as-disabled: catch-up makes it playable, so it reads as
    // available-but-over rather than as unavailable, and it carries the same
    // history glyph the catch-up badge does.
    //
    // Past is an outline and future is a fill, rather than two fills a step
    // apart. `surface-container` and `surface-container-high` differ by about
    // four percent lightness, which is invisible across the gap the now line
    // puts between them: the grid read as one undifferentiated field until the
    // two sides were given different SHAPES instead of different shades.
    final String tone = live
        ? 'bg-epg-now-soft border-l-2 border-color-epg-now'
        : past
        ? 'border border-color-border-subtle'
        : 'bg-surface-container-high';

    return WAnchor(
      onTap: () => controller.selectProgramme(channel, programme),
      semanticLabel: '${channel.name}, ${programme.title}, ${programme.startLabel} - ${programme.endLabel}',
      child: WDiv(
        // No `w-full h-full`, and dropping them is a measured saving rather
        // than tidying. The `Positioned` above carries `left` + `width` and
        // `top` + `bottom`, so this box is already TIGHT on both axes and the
        // two classes changed nothing about the layout. `h-full` is not free
        // though: wind composes it as a `LayoutBuilder` whose bounded branch
        // returns `FractionallySizedBox(heightFactor: 1)`
        // (`w_div.dart:1721`), and a `LayoutBuilder` defers its subtree into a
        // second layout pass. One per programme block, on a grid that draws
        // hundreds.
        //
        // Same family as the `max-w-*` trap in `CLAUDE.md`, from the other
        // side: under a tight parent a sizing class does nothing, and here
        // doing nothing still cost a render object.
        className:
            '''
              flex flex-col justify-center gap-0.5 px-2 rounded-lg overflow-hidden
              hover:brightness-110
              focus:ring-2 focus:ring-focus-ring
              selected:ring-2 selected:ring-focus-ring
            '''
            ' $tone',
        states: selected ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          WDiv(
            className: 'flex flex-row items-center gap-1.5 w-full',
            children: <Widget>[
              if (past)
                const WDiv(
                  className: 'shrink-0',
                  child: WIcon(Icons.history_outlined, className: 'text-xs text-catchup'),
                ),
              WDiv(
                className: 'flex-1 min-w-0',
                child: WText(
                  programme.title,
                  className: past
                      ? 'text-xs font-medium text-fg-muted line-clamp-1'
                      : 'text-xs font-semibold text-fg line-clamp-1',
                ),
              ),
              if (live)
                const WDiv(
                  className: 'shrink-0',
                  child: StatusBadge(status: ChannelStatus.live),
                ),
            ],
          ),
          WText(
            '${programme.startLabel} - ${programme.endLabel}',
            className: 'text-[11px] text-fg-disabled',
            textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
