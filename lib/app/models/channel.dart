import 'package:flutter/foundation.dart';

import 'programme.dart';

/// What a channel is doing right now.
///
/// These are the states DESIGN.md gives a colour to. Everything else about a
/// channel (resolution, codec, audio layout) is a fact and renders in a neutral
/// chip, because a row where every chip is coloured is a row where no chip
/// means anything.
enum ChannelStatus {
  /// On air now.
  live,

  /// Already aired, still replayable from the provider's archive.
  catchup,

  /// On air and being recorded.
  recording,

  /// Nothing on air and no archive. Renders with no badge at all.
  idle,
}

/// One channel in the user's provider line-up.
///
/// A plain value type, not a Magic ORM model: there is no data layer yet, and
/// the design phase needs a shape to render rather than a table to query. It
/// becomes a `Model` when the Xtream client lands.
@immutable
class Channel {
  /// The channel number the provider assigns, shown in tabular figures so a
  /// column of them aligns.
  final int number;

  /// The display name, from `tvg-name`.
  final String name;

  /// A one-word group, from `group-title`.
  final String group;

  /// What the channel is doing right now.
  final ChannelStatus status;

  /// The channel mark, from `tvg-logo`. Null is common and the fallback has to
  /// carry its own weight rather than leaving a hole.
  final String? logoUrl;

  /// Today's schedule, ordered by start time. Empty when the provider sent no
  /// EPG for this channel, which is normal rather than an error.
  final List<Programme> schedule;

  /// Technical facts, rendered as neutral chips: `1080p`, `H.265`, `5.1`.
  final List<String> facts;

  /// Whether the user starred it. Favourites are the only thing that makes a
  /// ten thousand channel line-up usable, so this is user state and it belongs
  /// on the device rather than on the provider.
  final bool favourite;

  /// Creates a [Channel].
  const Channel({
    required this.number,
    required this.name,
    required this.group,
    required this.status,
    this.logoUrl,
    this.schedule = const <Programme>[],
    this.facts = const <String>[],
    this.favourite = false,
  });

  /// Whether the provider sent any guide data for this channel.
  ///
  /// A large share of a real line-up answers false. A time axis has nothing to
  /// lay out for those, which is why the guide and the list are separate views
  /// rather than one view with holes in it.
  bool get hasSchedule => schedule.isNotEmpty;

  /// Returns a copy with [favourite] flipped.
  Channel toggleFavourite() => Channel(
    number: number,
    name: name,
    group: group,
    status: status,
    logoUrl: logoUrl,
    schedule: schedule,
    facts: facts,
    favourite: !favourite,
  );

  /// The programme covering [minute], or null when the guide has a hole there.
  Programme? programmeAt(int minute) {
    for (final Programme programme in schedule) {
      if (programme.contains(minute)) return programme;
    }

    return null;
  }

  /// The first programme starting after [minute], or null at the end of the
  /// guide window.
  ///
  /// A line-up row has dead space to the right of what is on now, and "what is
  /// next" is the thing a viewer actually wants there. It also answers the
  /// question a progress bar raises but does not settle: worth waiting out, or
  /// worth switching.
  Programme? nextAfter(int minute) {
    for (final Programme programme in schedule) {
      if (programme.startMinute > minute) return programme;
    }

    return null;
  }

  /// The channel number zero-padded to three digits, so a column lines up.
  String get numberLabel => number.toString().padLeft(3, '0');
}
