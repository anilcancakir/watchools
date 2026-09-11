import 'package:flutter/foundation.dart';

import '../protocol/xtream/xtream_json.dart';

/// One entry in a channel's schedule.
///
/// Times are minutes from midnight rather than `DateTime`. A real programme
/// carries a `DateTime` plus the provider's timezone offset, because the
/// Xtream timeshift endpoint interprets start times in the server's local time
/// and that is the source of most "catch-up played the wrong show" bugs. A
/// fixture does not need that, and an int keeps the mockup deterministic.
@immutable
class Programme {
  /// Minutes from midnight when this programme starts.
  final int startMinute;

  /// Minutes from midnight when it ends.
  final int endMinute;

  /// The programme title, from XMLTV `<title>`.
  final String title;

  /// The XMLTV `<sub-title>`, usually an episode name.
  final String? subtitle;

  /// The XMLTV `<desc>`, shown in the hero and nowhere else.
  final String? description;

  /// Backdrop artwork. A provider that sends none is the normal case; the
  /// gradient behind it has to stand on its own.
  final String? imageUrl;

  /// The XMLTV `<episode-num>` rendered for display, `S10 · E13`.
  final String? episode;

  /// Creates a [Programme].
  const Programme({
    required this.startMinute,
    required this.endMinute,
    required this.title,
    this.subtitle,
    this.description,
    this.imageUrl,
    this.episode,
  });

  /// Builds a [Programme] from a decoded `get_short_epg` /
  /// `get_simple_data_table` listing (`tool/xtream-mock/server.mjs:355`), or
  /// `null` when the listing has no parsable `start` or `end`.
  ///
  /// [referenceMidnight] is the panel-local calendar day the caller has
  /// chosen as minute zero for the WHOLE schedule this listing belongs to,
  /// typically the earliest listing's own day: it must be the same value
  /// across every call for one channel's schedule, or a listing that starts
  /// exactly at the reference's midnight reads as minute 0 while an earlier
  /// listing that ran past midnight reads as, say, 1470, which is the
  /// intended shape (`CLAUDE.md`'s never-wrapped rule) rather than a bug.
  ///
  /// The wire's `start_timestamp` / `stop_timestamp` are absolute epochs, but
  /// converting an epoch into "minutes since the panel's local midnight"
  /// needs the panel's UTC offset, which only `xmltv.php` states
  /// (`explore-mock-surface.md`); the JSON actions never do. `start` and
  /// `end`, by contrast, are already formatted in the panel's local time, so
  /// this reads those two strings and takes a plain wall-clock difference
  /// from [referenceMidnight], sidestepping the offset entirely. Both sides
  /// go through [DateTime.parse] with no zone suffix, which Dart resolves as
  /// the device's own local zone: the one caveat is a listing and its
  /// [referenceMidnight] straddling this device's own DST transition, which
  /// would skew the result by the transition's offset. The panel's calendar
  /// has no DST of its own, so this is a device-clock hedge, not a
  /// panel-clock one.
  static Programme? fromXtream(Map<String, dynamic> listing, {required DateTime referenceMidnight}) {
    final DateTime? start = _parsePanelLocal(readNullableString(listing, 'start'));
    final DateTime? stop = _parsePanelLocal(readNullableString(listing, 'end'));

    if (start == null || stop == null) return null;

    final DateTime midnight = DateTime(referenceMidnight.year, referenceMidnight.month, referenceMidnight.day);

    return Programme(
      startMinute: start.difference(midnight).inMinutes,
      endMinute: stop.difference(midnight).inMinutes,
      title: readBase64Text(listing, 'title') ?? '',
      description: readBase64Text(listing, 'description'),
    );
  }

  /// Parses a panel-local `YYYY-MM-DD HH:MM:SS` string, or `null` when
  /// [value] is missing or not in that shape.
  static DateTime? _parsePanelLocal(String? value) {
    if (value == null) return null;

    try {
      return DateTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// How long the programme runs, in minutes.
  int get durationMinutes => endMinute - startMinute;

  /// Whether [minute] falls inside this programme.
  bool contains(int minute) => minute >= startMinute && minute < endMinute;

  /// How far through the programme [minute] is, clamped to 0..1.
  ///
  /// Zero duration answers 0 rather than NaN. It is the most common malformed
  /// XMLTV entry (a `stop` equal to its `start`), and `NaN.clamp(0, 1)` returns
  /// NaN rather than clamping, which then reaches `FractionallySizedBox` and
  /// asserts. A guide that throws on bad EPG is worse than one that draws an
  /// empty bar.
  double progressAt(int minute) {
    if (durationMinutes <= 0) return 0;

    return ((minute - startMinute) / durationMinutes).clamp(0.0, 1.0);
  }

  /// `20:00` in tabular-friendly form.
  String get startLabel => _hhmm(startMinute);

  /// `20:55`.
  String get endLabel => _hhmm(endMinute);

  /// A minute-of-day label, correct for a **negative** minute too.
  ///
  /// The unit is minutes since the schedule's reference midnight and it is
  /// allowed to go negative: `get_short_epg`'s first listing is the programme
  /// already on air, which began the previous evening, so after a post-midnight
  /// re-anchor a window legitimately starts at -30. Dart's `~/` truncates
  /// toward zero, so `-30 ~/ 60` is `0` while `-30 % 60` is `30`, and the naive
  /// form printed `00:30` for half past eleven the night before. The hour is
  /// floored and both operands normalised instead.
  ///
  /// Block placement was never affected, only the printed label and the ruler,
  /// which is why this survived every layout test.
  static String _hhmm(int minute) {
    final int hour = ((minute / 60).floor() % 24 + 24) % 24;
    final String h = hour.toString().padLeft(2, '0');
    final String m = (((minute % 60) + 60) % 60).toString().padLeft(2, '0');

    return '$h:$m';
  }
}
