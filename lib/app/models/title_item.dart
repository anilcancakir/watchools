import 'package:flutter/foundation.dart';

/// What kind of catalogue entry this is.
///
/// A provider sends movies and series through separate Xtream endpoints with
/// different shapes, but the browse surface treats them as one catalogue: the
/// user does not think in endpoints, and a search that only covers half the
/// library is a search nobody trusts.
enum TitleKind {
  /// One playable stream with a runtime.
  movie,

  /// A container of seasons and episodes, with no runtime of its own.
  series,
}

/// One episode of a series.
///
/// The runtime and the still are per episode because a provider sends them per
/// episode. The resume position is ours: nothing in the Xtream protocol carries
/// it, so it lives on the device and is the reason a catalogue is worth
/// browsing at all on a second visit.
@immutable
class Episode {
  /// Season number, one-based as the provider sends it.
  final int season;

  /// Episode number within the season, one-based.
  final int number;

  /// The episode title. Often absent in a real feed, where it arrives as
  /// `Episode 4`; the fixture keeps real titles so the layouts can be judged at
  /// their best rather than at their worst.
  final String title;

  /// A one-paragraph synopsis, or null when the provider sent none.
  final String? synopsis;

  /// Runtime in minutes.
  final int minutes;

  /// The episode still.
  final String? imageUrl;

  /// How far through the episode the viewer got, 0 to 1. Zero means unwatched.
  final double progress;

  /// Creates an [Episode].
  const Episode({
    required this.season,
    required this.number,
    required this.title,
    required this.minutes,
    this.synopsis,
    this.imageUrl,
    this.progress = 0,
  });

  /// `S02B04`, the label a Turkish catalogue uses.
  String get code => 'S${season.toString().padLeft(2, '0')}B${number.toString().padLeft(2, '0')}';

  /// Whether the viewer started this episode and did not finish it.
  ///
  /// The thresholds matter more than they look. Below 3% is an accidental tap
  /// rather than a start, and above 92% is the closing credits rather than an
  /// unfinished episode: without both bounds a "continue watching" row fills up
  /// with things nobody wants to resume.
  bool get inProgress => progress > 0.03 && progress < 0.92;

  /// `48 dk`, or the minutes left when the episode is part-watched.
  String get runtimeLabel => '$minutes dk';
}

/// One person in a title's cast or crew.
///
/// The portrait is nullable and usually null. Every reference renders a missing
/// one as a grey circle carrying initials rather than dropping the person, and
/// that is the whole reason this is a type rather than a pair of strings: the
/// fallback has to be somebody's decision.
@immutable
class CastMember {
  /// The person's name.
  final String name;

  /// What they did: a character name, `Yönetmen`, `Senarist`.
  final String role;

  /// The portrait, or null.
  final String? imageUrl;

  /// Creates a [CastMember].
  const CastMember({required this.name, required this.role, this.imageUrl});
}

/// One movie or series in the user's VOD catalogue.
///
/// A plain value type for the same reason [Episode] is: there is no data layer
/// yet, and the design phase needs a shape to render. It becomes a `Model` when
/// the Xtream client lands.
@immutable
class TitleItem {
  /// Movie or series.
  final TitleKind kind;

  /// The display name, from the provider's `name`.
  final String name;

  /// The provider's category, its `category_name`. Unordered and inconsistently
  /// spelled in a real feed, exactly like a channel's `group-title`.
  final String category;

  /// Release year, or the first year for a series.
  final int year;

  /// The 2:3 poster. Null is common and the fallback has to carry its own
  /// weight, which is why the poster-led layouts are the ones that suffer.
  final String? posterUrl;

  /// The 16:9 backdrop, used by a hero. Sent far less often than a poster.
  final String? backdropUrl;

  /// Runtime in minutes for a movie, null for a series.
  final int? minutes;

  /// Rating out of ten, or null when the provider sent none.
  final double? rating;

  /// Genre labels, from the provider's `genre` string split on commas.
  final List<String> genres;

  /// A one-paragraph synopsis, or null.
  final String? synopsis;

  /// Technical facts, rendered as neutral chips: `4K`, `H.265`, `5.1`.
  final List<String> facts;

  /// Cast and crew, in billing order. Empty is common in a real feed and is a
  /// designed state on the detail screen rather than a dropped section.
  final List<CastMember> cast;

  /// Every episode, flat and ordered. Empty for a movie.
  ///
  /// Flat rather than nested by season, because a provider sends it flat and
  /// because grouping is a view concern: the two directions that group by
  /// season and the one that does not both read the same list.
  final List<Episode> episodes;

  /// How far through a movie the viewer got, 0 to 1. Always zero for a series,
  /// which resumes per episode instead.
  final double progress;

  /// Whether the user starred it.
  final bool favourite;

  /// Creates a [TitleItem].
  const TitleItem({
    required this.kind,
    required this.name,
    required this.category,
    required this.year,
    this.posterUrl,
    this.backdropUrl,
    this.minutes,
    this.rating,
    this.genres = const <String>[],
    this.synopsis,
    this.facts = const <String>[],
    this.cast = const <CastMember>[],
    this.episodes = const <Episode>[],
    this.progress = 0,
    this.favourite = false,
  });

  /// Whether this is a series.
  bool get isSeries => kind == TitleKind.series;

  /// Season numbers present, ascending and deduplicated.
  List<int> get seasons {
    final Set<int> found = <int>{for (final Episode episode in episodes) episode.season};

    return found.toList()..sort();
  }

  /// The episodes of [season], in order.
  List<Episode> episodesOf(int season) => episodes.where((Episode e) => e.season == season).toList();

  /// The episode to offer on the play button: the part-watched one if there is
  /// one, otherwise the first unwatched, otherwise the very first.
  ///
  /// This is the whole point of a series page. A viewer who has to remember
  /// which episode they were on is a viewer the catalogue failed.
  Episode? get upNext {
    if (episodes.isEmpty) return null;

    for (final Episode episode in episodes) {
      if (episode.inProgress) return episode;
    }
    for (final Episode episode in episodes) {
      if (episode.progress <= 0.03) return episode;
    }

    return episodes.first;
  }

  /// Whether the viewer started this and did not finish it. Same bounds as
  /// [Episode.inProgress], and for a series it asks the same of any episode.
  bool get inProgress {
    if (isSeries) return episodes.any((Episode e) => e.inProgress);

    return progress > 0.03 && progress < 0.92;
  }

  /// How many episodes the viewer has not started, or null for a movie and for
  /// a fully-watched series.
  ///
  /// Plex puts this in a square badge on the corner of the poster rather than
  /// in the caption, and it is the single most useful number on a series card:
  /// it answers "is there anything here for me" without opening anything. Null
  /// rather than zero, so the caller renders no badge instead of a badge
  /// announcing nothing.
  int? get unwatchedCount {
    if (!isSeries) return null;

    final int count = episodes.where((Episode e) => e.progress <= 0.03).length;

    return count == 0 ? null : count;
  }

  /// `1s 52dk` for a movie, `3 sezon` for a series.
  String get lengthLabel {
    if (isSeries) return '${seasons.length} sezon';

    final int total = minutes ?? 0;
    final int hours = total ~/ 60;
    final int rest = total % 60;

    return hours == 0 ? '$rest dk' : '${hours}s ${rest}dk';
  }

  /// `7,8`, with the decimal comma Turkish uses, or null when unrated.
  String? get ratingLabel => rating?.toStringAsFixed(1).replaceAll('.', ',');

  /// Returns a copy with [favourite] flipped.
  TitleItem toggleFavourite() => TitleItem(
    kind: kind,
    name: name,
    category: category,
    year: year,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    minutes: minutes,
    rating: rating,
    genres: genres,
    synopsis: synopsis,
    facts: facts,
    cast: cast,
    episodes: episodes,
    progress: progress,
    favourite: !favourite,
  );
}
