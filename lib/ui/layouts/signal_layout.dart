import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../components/channel_row/index.dart';
import '../components/epg_row/index.dart';
import '../components/hero_billboard/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';
import 'support/time_axis.dart';

/// Direction one: the line-up as a control surface.
///
/// Plex's answer, and the most information per pixel of the four. A billboard
/// for what is selected, then either a time axis or a dense row per channel,
/// with search, categories and favourites all on screen at once. It assumes
/// the user knows roughly what they want and is navigating, not browsing.
///
/// What it optimises: getting to a known channel in one glance, and reading
/// the whole schedule of a channel that has one.
///
/// What it sacrifices: artwork. Nothing here is large enough to be attractive,
/// and on a 10-foot screen a row this dense is unreadable.
@immutable
class SignalLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [SignalLayout].
  const SignalLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // A three hour time axis needs room. Below `md` there is none, so the
    // phone gets the list and no toggle at all: offering a mode that renders
    // as a wall of clipped blocks is worse than not offering it.
    final bool wide = wScreenIs(context, 'md');
    final GuideMode mode = wide ? controller.mode : GuideMode.list;

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 flex flex-col min-w-0',
          children: <Widget>[
            HeroBillboard(channel: controller.channel, programme: controller.programme, nowMinute: GuideController.now),
            _toolbar(showToggle: wide, mode: mode),
            CategoryStrip(controller: controller),
            WDiv(className: 'flex-1 min-w-0', child: _body(context, mode)),
          ],
        ),
      ],
    );
  }

  Widget _toolbar({required bool showToggle, required GuideMode mode}) {
    final String? note = controller.noGuideNote;

    return WDiv(
      className: 'flex flex-row items-center gap-3 px-4 md:px-8 pt-4',
      children: <Widget>[
        WDiv(
          className: 'flex-1 max-w-[320px] min-w-0',
          child: WInput(
            value: controller.query,
            onChanged: controller.search,
            placeholder: 'Kanal veya program ara',
            className: '''
              rounded-lg px-3 py-2
              bg-surface-container
              border border-color-border-subtle
              text-sm text-fg
              hover:border-color-border
              focus:border-color-focus-ring focus:ring-2 focus:ring-focus-ring
            ''',
          ),
        ),
        WText(controller.countLabel, className: 'shrink-0 text-xs text-fg-muted'),
        if (note != null) WText('· $note', className: 'text-xs text-fg-disabled'),
        const WDiv(className: 'flex-1'),
        if (showToggle) _modeToggle(),
      ],
    );
  }

  Widget _modeToggle() {
    return WDiv(
      className: '''
        flex flex-row gap-1 p-1 rounded-lg shrink-0
        bg-surface-container
        border border-color-border-subtle
      ''',
      children: <Widget>[
        _modeButton(GuideMode.guide, Icons.calendar_view_week_outlined, 'Rehber'),
        _modeButton(GuideMode.list, Icons.view_list_outlined, 'Liste'),
      ],
    );
  }

  Widget _modeButton(GuideMode mode, IconData icon, String label) {
    return WAnchor(
      onTap: () => controller.showMode(mode),
      child: WDiv(
        className: '''
          flex flex-row items-center gap-2
          rounded px-3 py-1.5
          text-xs font-semibold text-fg-disabled
          hover:text-fg
          focus:ring-2 focus:ring-focus-ring
          selected:bg-surface-container-high selected:text-fg
        ''',
        states: controller.mode == mode ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          WIcon(icon, className: 'text-sm'),
          WText(label, className: 'text-xs font-semibold'),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, GuideMode mode) {
    final List<Channel> rows = mode == GuideMode.guide ? controller.scheduled : controller.matches;

    if (rows.isEmpty) return GuideEmpty(controller: controller);

    return mode == GuideMode.guide ? _guide(rows) : _list(context, rows);
  }

  Widget _list(BuildContext context, List<Channel> rows) {
    final bool compact = !wScreenIs(context, 'md');

    return ListView.separated(
      primary: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 4),
      itemBuilder: (BuildContext context, int index) {
        final Channel channel = rows[index];

        return ChannelRow(
          channel: channel,
          nowMinute: GuideController.now,
          compact: compact,
          selected: identical(channel, controller.channel),
          onTap: () => controller.selectChannel(channel),
          onToggleFavourite: () => controller.toggleFavourite(channel),
        );
      },
    );
  }

  Widget _guide(List<Channel> rows) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The axis fills whatever width there is rather than assuming one. A
        // fixed pixels-per-minute leaves dead space on a wide monitor and clips
        // on a laptop, and dead space to the right of a guide reads as broken
        // rather than as roomy.
        const double railGutter = 64;
        const double logoColumn = 112 + 4;
        final double track = (constraints.maxWidth - railGutter - logoColumn).clamp(320.0, double.infinity);
        final double perMinute = track / GuideController.windowMinutes;

        return SingleChildScrollView(
          primary: true,
          child: WDiv(
            className: 'flex flex-col gap-1 px-8 py-4',
            children: <Widget>[
              TimeAxis(pixelsPerMinute: perMinute),
              // The now line is drawn once, over every row. Segments that
              // restart at each row boundary read as dashes rather than as a
              // single instant in time.
              Stack(
                children: <Widget>[
                  WDiv(
                    className: 'flex flex-col gap-1',
                    children: <Widget>[
                      for (final Channel channel in rows)
                        EpgRow(
                          channel: channel,
                          windowStart: GuideController.windowStart,
                          windowMinutes: GuideController.windowMinutes,
                          pixelsPerMinute: perMinute,
                          nowMinute: GuideController.now,
                          selected: controller.programme,
                          onSelect: controller.selectProgramme,
                          onToggleFavourite: () => controller.toggleFavourite(channel),
                        ),
                    ],
                  ),
                  Positioned(
                    left: logoColumn + (GuideController.now - GuideController.windowStart) * perMinute,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const IgnorePointer(child: WDiv(className: 'bg-epg-now rounded-full')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
