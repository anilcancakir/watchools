import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/models/programme.dart';
import '../channel_mark/index.dart';
import '../fact_chip/index.dart';
import '../favourite_button/index.dart';
import '../status_badge/index.dart';

/// One channel in the list view.
///
/// The list exists because the guide cannot serve a whole line-up. A time axis
/// needs a schedule, and a large share of any real provider's channels have no
/// EPG at all. This row is about the channel rather than the programme, so it
/// reads the same whether the guide arrived or not. The now-playing line is an
/// addition when it exists, never a hole when it does not.
///
/// No borders anywhere, deliberately. A border per row in a list of ten
/// thousand is ten thousand hairlines, and the eye reads the grid instead of
/// the content. Separation comes from a tonal step and from the accent bar,
/// which carries the status colour and gives the column a rhythm at a glance.
///
/// The bar also sidesteps a Wind defect worth knowing about:
/// `border_parser.dart:221` falls back to a hardcoded `#E5E7EB` when no colour
/// token matched, and `border-transparent` matches nothing, so `border
/// border-transparent` paints a near-white hairline with no dark-mode peer.
@immutable
class ChannelRow extends StatelessWidget {
  /// The channel to render.
  final Channel channel;

  /// Minutes from midnight, for the now-playing line.
  final int nowMinute;

  /// Whether this row is the one the user is pointed at.
  final bool selected;

  /// How much width the row actually has, in logical pixels.
  ///
  /// A number rather than a `md:` / `lg:` / `xl:` prefix, and the difference is
  /// load-bearing. Wind's breakpoints read the VIEWPORT, not the parent, so a
  /// row inside an 860 pixel column of a 1440 pixel window evaluates `xl:` as
  /// true and builds a 220 pixel next-column plus a fact strip it has no room
  /// for. That is exactly what happened in the panelled direction: five
  /// simultaneous right-overflows, from half a pixel to twenty seven, on a
  /// screen where nothing looked wrong.
  ///
  /// The thresholds below are the sum of the columns each one admits, so a
  /// column is only built once the row can actually hold it.
  final double available;

  /// Fired when the row is picked.
  final VoidCallback? onTap;

  /// Fired when the star is picked.
  final VoidCallback? onToggleFavourite;

  /// Creates a [ChannelRow].
  const ChannelRow({
    super.key,
    required this.channel,
    required this.nowMinute,
    required this.available,
    this.selected = false,
    this.onTap,
    this.onToggleFavourite,
  });

  /// Below this the row is the channel and what is on it, and nothing else.
  static const double _nowFloor = 640;

  /// Adds the next-programme column.
  static const double _nextFloor = 900;

  /// Adds the fact chips.
  static const double _factFloor = 1080;

  @override
  Widget build(BuildContext context) {
    final Programme? now = channel.programmeAt(nowMinute);
    final bool wide = available >= _nowFloor;

    // The star sits OUTSIDE the row's anchor, not inside it. Nested inside, the
    // row's own `Semantics` swallowed it: the end-to-end walk found no
    // favourite control on this row at all, while the screenshot clearly showed
    // one, which is exactly the failure a screen reader would hit. Two sibling
    // targets also removes a real ambiguity, since tapping the star used to
    // select the row as well.
    return WDiv(
      className: '''
        flex flex-row items-center
        h-[60px] rounded-lg overflow-hidden
        bg-surface-container
        duration-150 ease-out
        hover:bg-surface-container-high
        selected:bg-surface-container-high
      ''',
      states: selected ? const <String>{'selected'} : const <String>{},
      children: <Widget>[
        WDiv(
          className: 'flex-1 min-w-0',
          child: WAnchor(
            onTap: onTap,
            semanticLabel: _label(now),
            child: WDiv(
              className: 'flex flex-row items-center h-[60px] focus:ring-2 focus:ring-focus-ring',
              children: <Widget>[
                _accentBar(),
                _number(),
                _logo(),
                // Identity takes the remainder at every width. Everything
                // after it is fixed-width and drops out at its own threshold,
                // so the name always has somewhere to go instead of
                // overflowing.
                _identity(now, wide: wide),
                if (wide) ...<Widget>[
                  if (now != null) _now(now) else _noSchedule(),
                  if (available >= _nextFloor) _next(),
                  if (available >= _factFloor) _facts(),
                ],
              ],
            ),
          ),
        ),
        _star(),
      ],
    );
  }

  /// Everything the row says, in one sentence.
  ///
  /// A `WAnchor`'s `semanticLabel` REPLACES the text of everything under it, so
  /// a label of just the number and the name meant a screen reader was told
  /// `014 Haber Global` and never that the channel has no schedule, while the
  /// row on screen said so plainly. The end-to-end walk hit the same wall from
  /// the other side: it could not find the designed no-EPG state in the
  /// semantics tree, because the tree did not have it.
  ///
  /// Built from the row's own content rather than from a fixed template, so the
  /// two cannot drift.
  String _label(Programme? now) {
    final StringBuffer out = StringBuffer()
      ..write(channel.numberLabel)
      ..write(' ')
      ..write(channel.name);

    if (now == null) {
      out.write(', Yayın akışı yok');
    } else {
      out.write(', ${now.title}, ${now.startLabel} - ${now.endLabel}');
    }

    return out.toString();
  }

  /// A four pixel column of the status colour, full height, flush left.
  ///
  /// It replaces the border and does more than one: scanning the list, the eye
  /// picks up which channels are on air before it reads a single word.
  Widget _accentBar() {
    final String tone = switch (channel.status) {
      ChannelStatus.live => 'bg-live',
      ChannelStatus.recording => 'bg-recording',
      ChannelStatus.catchup => 'bg-catchup',
      ChannelStatus.idle => 'bg-surface-container-high',
    };

    // `shrink-0` is load-bearing, not decoration. The row clips (`overflow-hidden`)
    // and `w_div.dart:704` wraps every non-`shrink-0` child of a clipping row in a
    // bare `Flexible`, which defaults to `flex: 1`. A four pixel bar would then
    // claim an equal share of the free width against the identity column's
    // `Expanded` and leave the remainder unallocated.
    return WDiv(className: 'w-1 h-[60px] shrink-0 $tone');
  }

  Widget _number() {
    return WText(
      channel.numberLabel,
      className: 'w-11 shrink-0 pl-2 md:pl-3 text-xs text-fg-disabled',
      textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
    );
  }

  Widget _logo() => ChannelMark(channel: channel, size: 'sm');

  Widget _identity(Programme? now, {required bool wide}) {
    // The grow claim gets its own element and the column lives inside it, so
    // that `flex-1` and `flex flex-col` never land on one WDiv: they sit in the
    // same parser family and the last class in a family wins.
    return WDiv(
      className: 'flex-1 min-w-0 ml-2 md:ml-3',
      child: WDiv(
        className: 'flex flex-col min-w-0',
        children: <Widget>[
          WDiv(
            className: 'flex flex-row items-center gap-2 w-full min-w-0',
            children: <Widget>[
              WDiv(
                className: 'flex-1 min-w-0',
                child: WText(channel.name, className: 'text-sm font-semibold text-fg truncate'),
              ),
              // Dropped on a narrow row: the accent bar down the left edge
              // already says live, catch-up or recording, and at this width the
              // badge took the whole row and squeezed the name to nothing.
              if (wide)
                WDiv(
                  className: 'shrink-0',
                  child: StatusBadge(status: channel.status),
                ),
            ],
          ),
          // On a narrow row the dedicated now-column is gone, so what is on air
          // moves under the name. Dropping it entirely would leave the row
          // saying only which channels exist, which is not what anyone opens a
          // guide for.
          if (!wide && now != null)
            WDiv(
              className: 'flex flex-row items-center gap-1.5 w-full min-w-0',
              children: <Widget>[
                WText(
                  now.startLabel,
                  className: 'text-xs font-semibold text-epg-now',
                  textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                ),
                WDiv(
                  className: 'flex-1 min-w-0',
                  child: WText(now.title, className: 'text-xs text-fg-muted truncate'),
                ),
              ],
            )
          // A narrow row with no programme says so, rather than falling back to
          // the group and saying nothing. The wide row has a dedicated column
          // for this (`_noSchedule`), and a phone dropping the sentence while
          // the desktop keeps it means the doctrine's third rule holds on one
          // screen size and not the other: a provider's EPG gap is the common
          // case, and a row that quietly shows less is how a user comes to read
          // it as the app failing.
          else
            WText(wide ? channel.group : 'Yayın akışı yok', className: 'text-xs text-fg-disabled truncate'),
        ],
      ),
    );
  }

  Widget _now(Programme now) {
    return WDiv(
      className: 'flex flex-col w-[300px] shrink-0 gap-1.5 ml-4',
      children: <Widget>[
        WDiv(
          className: 'flex flex-row items-baseline gap-2',
          children: <Widget>[
            WText(
              now.startLabel,
              className: 'text-xs font-semibold text-epg-now',
              textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(now.title, className: 'text-xs text-fg truncate'),
            ),
          ],
        ),
        _progress(now.progressAt(nowMinute)),
      ],
    );
  }

  /// The bar is a [FractionallySizedBox], not a `WindStyle(widthFactor:)`.
  ///
  /// Passing `style:` to a W-widget bypasses the parser cache outright:
  /// `wind_parser.dart:222` reads the cache only when `baseStyle == null`, so
  /// every such bar re-parsed its className on every frame. Measured on this
  /// screen it was eight bypasses per rebuild against 403 hits.
  Widget _progress(double value) {
    return WDiv(
      className: 'h-0.5 rounded-full bg-surface-container-high overflow-hidden',
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value,
        child: const WDiv(className: 'h-0.5 rounded-full bg-epg-now'),
      ),
    );
  }

  Widget _noSchedule() {
    // Quiet rather than absent. A provider that sends no EPG is normal, and a
    // row that simply stops halfway reads as a rendering bug.
    return const WDiv(
      className: 'w-[300px] shrink-0 ml-4',
      child: WText('Yayın akışı yok', className: 'text-xs text-fg-disabled'),
    );
  }

  /// What follows the current programme, in the space a fixed now-column
  /// leaves empty. Air there reads as a layout bug; the next title reads as the
  /// answer to the question the progress bar just raised.
  Widget _next() {
    final Programme? next = channel.nextAfter(nowMinute);

    if (next == null) return const SizedBox.shrink();

    return WDiv(
      className: 'flex flex-row items-baseline gap-2 ml-6 w-[220px] shrink-0',
      children: <Widget>[
        WText(
          next.startLabel,
          className: 'text-xs text-fg-disabled',
          textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
        ),
        WDiv(
          className: 'flex-1 min-w-0',
          child: WText(next.title, className: 'text-xs text-fg-muted truncate'),
        ),
      ],
    );
  }

  Widget _facts() {
    if (channel.facts.isEmpty) return const SizedBox.shrink();

    return WDiv(
      className: 'flex flex-row gap-1 shrink-0 ml-4',
      children: <Widget>[for (final String fact in channel.facts) FactChip(label: fact)],
    );
  }

  /// The `shrink-0` wrapper is the same `overflow-hidden` guard the accent bar
  /// carries, in the one shape that works here: `w_div.dart:750` only honours
  /// `shrink-0` on a `WDiv` or a `WText`, so the button's own `WAnchor` root
  /// carrying it is still wrapped in a `Flexible` and still claims a share of
  /// the row.
  Widget _star() {
    return WDiv(
      className: 'shrink-0 mr-1',
      child: FavouriteButton(starred: channel.favourite, subject: channel.name, onToggle: onToggleFavourite),
    );
  }
}
