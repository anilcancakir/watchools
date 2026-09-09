import 'package:flutter/foundation.dart';

import '../protocol/xtream/xtream_json.dart';
import '../support/guide_clock.dart';
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
/// A plain value type, not a Magic ORM model, and it stays one once the
/// Xtream client lands: both controllers filter and search the catalogue in
/// Dart (`explore-controllers.md`), so there are no queries here for an ORM
/// model to serve, only a shape to render.
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

  /// The live entry's `stream_id`. `get_short_epg` and a timeshift URL are
  /// both keyed on it, per channel. Null on a fixture-built channel, which
  /// honestly has no provider.
  final int? streamId;

  /// How far back the provider's archive reaches, in **days**, or null when
  /// there is no catch-up on this channel.
  ///
  /// Folded from the two fields the wire sends separately: `tv_archive` is a
  /// bare `0`/`1` flag and `tv_archive_duration` a bare number, and a panel
  /// can send a non-zero duration beside a zero flag, in which case there is
  /// no archive. Null rather than `0` so the absence is one state instead of
  /// two.
  ///
  /// Carried rather than used. Deriving a catch-up URL needs five competing
  /// path conventions and the panel's own clock offset, which is deferred, and
  /// `tv_archive` is set on 20 of 2,976 channels on the measured real
  /// provider. It is stored from day one anyway so `ChannelStatus.catchup`
  /// becomes computable without a store migration. The unit is days because
  /// that is what the panel sends; verified against the mock
  /// (`tool/xtream-mock/server.mjs:216` sends `7`) and not against a real
  /// panel.
  final int? catchupDays;

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
    this.streamId,
    this.catchupDays,
  });

  /// Builds a [Channel] from a decoded `get_live_streams` entry
  /// (`tool/xtream-mock/server.mjs:203`).
  ///
  /// [categoryName] is the resolved `category_name` for the entry's
  /// `category_id`: the entry itself carries only the id, so the caller
  /// looks it up against `get_live_categories` once and passes the name in.
  ///
  /// [schedule] is built by the caller from `get_short_epg` listings through
  /// [Programme.fromXtream], not fetched here: that factory needs a
  /// schedule-wide reference midnight the caller decides once per channel,
  /// which this one has no reason to duplicate. An empty [schedule] is the
  /// normal case for a channel the provider sent no EPG for.
  ///
  /// [status] is never read off the wire, since no such field exists: it is
  /// computed against [clock], `ChannelStatus.live` when [schedule] holds a
  /// programme covering [clock]'s current minute, `ChannelStatus.idle`
  /// otherwise. `catchup` and `recording` both need state this factory has
  /// no access to (archive availability, a DVR job) and stay out of scope.
  factory Channel.fromXtream(
    Map<String, dynamic> entry, {
    required String categoryName,
    required GuideClock clock,
    List<Programme> schedule = const <Programme>[],
  }) {
    final String? logo = readNullableString(entry, 'stream_icon');

    return Channel(
      number: readInt(entry, 'num') ?? 0,
      name: readNullableString(entry, 'name') ?? '',
      group: categoryName,
      status: _statusAt(schedule, clock.minute),
      logoUrl: (logo == null || logo.isEmpty) ? null : logo,
      schedule: schedule,
      streamId: readInt(entry, 'stream_id'),
      catchupDays: _catchupDays(entry),
    );
  }

  /// The archive window in days, or null when this channel has no catch-up.
  ///
  /// Reads `tv_archive` as the authority and `tv_archive_duration` as the
  /// length, because the two disagree on real panels and the flag is the one
  /// that says whether an archive exists at all.
  static int? _catchupDays(Map<String, dynamic> entry) {
    if (readBool(entry, 'tv_archive') != true) return null;

    final int? days = readInt(entry, 'tv_archive_duration');

    return (days == null || days <= 0) ? null : days;
  }

  /// `ChannelStatus.live` when [schedule] has a programme covering [minute],
  /// `ChannelStatus.idle` otherwise. The only two states derivable from a
  /// schedule and a clock alone.
  static ChannelStatus _statusAt(List<Programme> schedule, int minute) {
    for (final Programme programme in schedule) {
      if (programme.contains(minute)) return ChannelStatus.live;
    }

    return ChannelStatus.idle;
  }

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
    streamId: streamId,
    catchupDays: catchupDays,
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
