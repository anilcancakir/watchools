import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/models/programme.dart';
import '../artwork/index.dart';
import '../channel_mark/index.dart';
import '../favourite_button/index.dart';
import '../play_progress/index.dart';
import '../scrim/index.dart';
import '../status_badge/index.dart';

/// A card whose subject is the programme on air, not the channel carrying it.
///
/// This is the doctrine's first rule in one widget. Netflix's unit is a title,
/// which is the same object all day; ours is a channel, which is a different
/// object every forty minutes. So the emphasised line is what is on now, the
/// channel is the attribution beneath it, and the progress bar shows the one
/// thing no competitor's static grid gives you: how much of it is left.
///
/// Two states, and the second one is not an error. A provider's EPG coverage is
/// partial, so a tile with no programme is normal and gets a designed
/// appearance at the same size: the channel mark at display scale on a plain
/// field, and a caption that says so. A layout whose cards collapse or blank
/// out for a third of the line-up reads as broken.
@immutable
class LiveTile extends StatelessWidget {
  /// The channel this tile stands for.
  final Channel channel;

  /// What is on it now, or null when the provider sent no guide for it.
  final Programme? programme;

  /// Minutes from midnight, for the progress bar and the time remaining.
  final int now;

  /// Card width in logical pixels. The artwork is 16:9 within it.
  final double width;

  /// Opens the channel.
  final VoidCallback onTap;

  /// Stars the channel.
  final VoidCallback onFavourite;

  /// Creates a [LiveTile].
  const LiveTile({
    super.key,
    required this.channel,
    required this.programme,
    required this.now,
    required this.onTap,
    required this.onFavourite,
    this.width = 260,
  });

  /// The rendered height of a tile [width] pixels wide.
  ///
  /// A 16:9 frame, the `gap-2` beneath it, and the caption's fixed height.
  /// Exposed because a `Rail` has to state its cell height before the cell is
  /// laid out, and the only place that can know it is here. The first version
  /// of this let the caller work it out and the caller was eight pixels short,
  /// which put a `RenderFlex overflowed` on every card of every rail.
  static double heightFor(double width) => width * 9 / 16 + 8 + 44;

  @override
  Widget build(BuildContext context) {
    final Programme? live = programme;

    return SizedBox(
      width: width,
      child: WDiv(
        className: 'flex flex-col gap-2',
        children: <Widget>[
          WAnchor(
            onTap: onTap,
            semanticLabel: _label(live),
            // The ring sits on a WDiv inside the anchor rather than on the
            // anchor: WAnchor takes no className at all, it only publishes
            // hover and focus to its descendants through a WindStateProvider.
            //
            // A ring and not an accent fill. On a remote, focus moves on every
            // keypress and selection does not, so the two have to be different
            // shapes of signal or the user cannot tell where they are.
            child: WDiv(
              className: 'rounded-lg overflow-hidden focus:ring-2 focus:ring-focus-ring',
              child: AspectRatio(aspectRatio: 16 / 9, child: _art(live)),
            ),
          ),
          // The caption is a sibling of the anchor rather than a child, and the
          // star is a sibling of both. A WAnchor's `semanticLabel` REPLACES its
          // descendants' text in the semantics tree, so a star nested inside
          // the anchor is invisible to a screen reader and to the end-to-end
          // walk that drives this app through the same tree.
          WDiv(
            className: 'flex flex-row items-start gap-2 w-full h-[44px] overflow-hidden',
            children: <Widget>[
              WDiv(
                className: 'flex flex-col gap-0.5 flex-1',
                children: <Widget>[
                  WText(live?.title ?? channel.name, className: 'text-sm font-semibold text-fg line-clamp-1'),
                  WText(_caption(live), className: 'text-xs text-fg-muted line-clamp-1'),
                ],
              ),
              WDiv(
                // `shrink-0` is ignored on a WAnchor: Wind's skip list
                // type-checks only WDiv and WText, so the star has to be
                // wrapped to keep its width. Defect 2 in
                // `.ac/research/ecosystem-defects.md`.
                className: 'shrink-0',
                child: FavouriteButton(starred: channel.favourite, subject: channel.name, onToggle: onFavourite),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _art(Programme? live) {
    if (live == null) {
      // The no-guide state. The mark goes to display scale rather than sitting
      // in a corner: with nothing to say about the programme, the channel IS
      // the subject and the card should look like it meant that.
      return WDiv(
        className: 'w-full h-full bg-surface-container items-center justify-center',
        child: ChannelMark(channel: channel, size: 'xl'),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Artwork(
          src: live.imageUrl,
          slotWidth: width,
          fallback: WDiv(
            className: 'w-full h-full bg-surface-container items-center justify-center',
            child: ChannelMark(channel: channel, size: 'lg'),
          ),
        ),
        Scrim.flat,
        Positioned(
          top: 8,
          left: 8,
          child: WDiv(
            className: 'rounded bg-scrim px-1.5 py-1',
            child: ChannelMark(channel: channel, size: 'sm'),
          ),
        ),
        if (channel.status != ChannelStatus.idle)
          Positioned(top: 8, right: 8, child: StatusBadge(status: channel.status, solid: true)),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: WText(
            '${live.startLabel} - ${live.endLabel}',
            className: 'text-xs font-semibold text-[#FFFFFF] dark:text-[#FFFFFF]',
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: PlayProgress(value: live.progressAt(now), tone: 'live'),
        ),
      ],
    );
  }

  String _caption(Programme? live) {
    if (live == null) return '${channel.numberLabel} · Akış bilgisi yok';

    final int left = live.endMinute - now;
    if (left <= 0) return '${channel.name} · ${live.endLabel}';

    return '${channel.name} · $left dk kaldı';
  }

  String _label(Programme? live) {
    if (live == null) return '${channel.name}, akış bilgisi yok';

    return '${channel.name}, ${live.title}, ${live.startLabel} - ${live.endLabel}';
  }
}
