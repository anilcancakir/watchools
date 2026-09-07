import 'package:flutter/foundation.dart';

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

  /// How long the programme runs, in minutes.
  int get durationMinutes => endMinute - startMinute;

  /// Whether [minute] falls inside this programme.
  bool contains(int minute) => minute >= startMinute && minute < endMinute;

  /// How far through the programme [minute] is, clamped to 0..1.
  double progressAt(int minute) => ((minute - startMinute) / durationMinutes).clamp(0.0, 1.0);

  /// `20:00` in tabular-friendly form.
  String get startLabel => _hhmm(startMinute);

  /// `20:55`.
  String get endLabel => _hhmm(endMinute);

  static String _hhmm(int minute) {
    final String h = (minute ~/ 60 % 24).toString().padLeft(2, '0');
    final String m = (minute % 60).toString().padLeft(2, '0');

    return '$h:$m';
  }
}
