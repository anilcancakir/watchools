import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/models/programme.dart';
import '../channel_mark/index.dart';
import '../favourite_button/index.dart';

/// One channel's strip in the guide: a pinned logo cell, then the schedule laid
/// out against a shared time axis.
///
/// Block width is proportional to duration, which is what makes a guide a guide
/// rather than a list. A 15 minute news bulletin and a three hour match have to
/// look like what they are before the user reads either title.
///
/// The row does not scroll on its own. Every row shares one horizontal offset
/// from the parent, or the axis stops meaning anything the moment two rows
/// disagree about where 20:00 is.
@immutable
class EpgRow extends StatelessWidget {
  /// The channel this strip belongs to.
  final Channel channel;

  /// Minutes from midnight at the left edge of the visible window.
  final int windowStart;

  /// How many minutes the window spans.
  final int windowMinutes;

  /// Logical pixels per minute, shared by every row and the axis header.
  final double pixelsPerMinute;

  /// Minutes from midnight for the now marker.
  final int nowMinute;

  /// The programme currently pointed at, so the row can render it focused.
  final Programme? selected;

  /// Fired when a block is picked.
  final void Function(Channel, Programme)? onSelect;

  /// Fired when the logo cell's star is picked.
  final VoidCallback? onToggleFavourite;

  /// Creates an [EpgRow].
  const EpgRow({
    super.key,
    required this.channel,
    required this.windowStart,
    required this.windowMinutes,
    required this.pixelsPerMinute,
    required this.nowMinute,
    this.selected,
    this.onSelect,
    this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(className: 'flex flex-row gap-1 h-[72px]', children: <Widget>[_logoCell(), _blocks()]);
  }

  /// The pinned cell: the channel's mark, its number, and its star.
  ///
  /// The star is here rather than nowhere. A time axis is about programmes, so
  /// the obvious place for a per-channel action is the channel column, and
  /// leaving it out made favouriting reachable only after switching to the list
  /// view: an action you have to change mode to reach is an action nobody uses.
  Widget _logoCell() {
    return WDiv(
      className: '''
        w-[112px] h-[72px] shrink-0
        rounded-lg overflow-hidden
        bg-surface-container
      ''',
      child: Stack(
        children: <Widget>[
          WDiv(
            className: 'flex flex-col items-center justify-center gap-1 w-[112px] h-[72px]',
            children: <Widget>[
              // `ChannelMark` rather than a bare `Image.network`: provider
              // logos 404 constantly, and the mark's initials fallback keeps
              // the cell reading as a channel instead of collapsing to a
              // generic television icon that says the same on every row.
              ChannelMark(channel: channel, size: 'sm'),
              WText(
                channel.numberLabel,
                className: 'text-[10px] text-fg-disabled',
                textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
              ),
            ],
          ),
          Positioned(
            right: 2,
            top: 2,
            child: FavouriteButton(
              starred: channel.favourite,
              subject: channel.name,
              shape: 'badge',
              onToggle: onToggleFavourite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocks() {
    final int windowEnd = windowStart + windowMinutes;
    final List<Programme> visible = channel.schedule
        .where((Programme p) => p.endMinute > windowStart && p.startMinute < windowEnd)
        .toList();

    if (visible.isEmpty) {
      return const WDiv(
        className: '''
          flex-1 h-[72px] rounded-lg
          bg-surface-container
          border border-color-border-subtle
          flex items-center px-4
        ''',
        child: WText('Yayın akışı yok', className: 'text-xs text-fg-disabled'),
      );
    }

    return Expanded(
      child: ClipRect(
        child: Stack(children: <Widget>[for (final Programme programme in visible) _positioned(programme, windowEnd)]),
      ),
    );
  }

  Widget _positioned(Programme programme, int windowEnd) {
    // Clamped to the window so a programme that started before the left edge
    // still shows, cut off, rather than pushing every later block sideways.
    final int from = programme.startMinute.clamp(windowStart, windowEnd);
    final int to = programme.endMinute.clamp(windowStart, windowEnd);

    return Positioned(
      left: (from - windowStart) * pixelsPerMinute,
      width: (to - from) * pixelsPerMinute - 4,
      top: 0,
      bottom: 0,
      child: _block(programme),
    );
  }

  Widget _block(Programme programme) {
    final bool isNow = programme.contains(nowMinute);
    final bool isSelected = identical(programme, selected);

    return WAnchor(
      onTap: onSelect == null ? null : () => onSelect!(channel, programme),
      semanticLabel: '${channel.name} ${programme.title}',
      child: WDiv(
        className: '''
          h-full rounded-lg px-3
          flex flex-col justify-center gap-0.5
          overflow-hidden
          bg-surface-container
          border border-color-border-subtle
          duration-150 ease-out
          hover:bg-surface-container-high
          focus:ring-2 focus:ring-focus-ring
          current:border-color-epg-now
          selected:bg-inverse selected:border-color-border
        ''',
        // `selected` wins over `current`: the block the user is pointed at is
        // the one that must read first, even when it is not the live one.
        states: <String>{if (isNow) 'current', if (isSelected) 'selected'},
        children: <Widget>[
          WText(
            programme.title,
            className: isSelected
                ? 'text-xs font-semibold text-on-inverse truncate'
                : 'text-xs font-semibold text-fg truncate',
          ),
          WText(
            '${programme.startLabel} - ${programme.endLabel}',
            className: isSelected ? 'text-[10px] text-on-inverse truncate' : 'text-[10px] text-fg-muted truncate',
            textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
          ),
          if (isNow) _progress(programme),
        ],
      ),
    );
  }

  /// A [FractionallySizedBox], not a `WindStyle(widthFactor:)`.
  ///
  /// `wind_parser.dart:222` reads the style cache only when `baseStyle` is
  /// null, so passing `style:` re-parses the className on every frame. This
  /// screen was paying eight of those per rebuild.
  Widget _progress(Programme programme) {
    return WDiv(
      className: 'h-0.5 rounded-full bg-surface-container-high mt-1 overflow-hidden',
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: programme.progressAt(nowMinute),
        child: const WDiv(className: 'h-0.5 rounded-full bg-epg-now'),
      ),
    );
  }
}
