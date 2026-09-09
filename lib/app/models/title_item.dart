import 'package:flutter/foundation.dart';

import '../protocol/xtream/xtream_json.dart';

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

  /// `48 dk`. The full runtime, always.
  ///
  /// The minutes REMAINING are a separate line beside it (`EpisodeRow`'s resume
  /// note), because an episode row has to answer both "how long is this" and
  /// "how much is left", and a single figure that silently changes meaning
  /// depending on whether you started it answers neither.
  String get runtimeLabel => '$minutes dk';
}

/// Splits a provider's flat fact list into the audio fact and the rest.
///
/// A provider sends `facts` as an unordered bag: `['4K','HDR','H.265','5.1']`
/// for one title and `['1080p','H.264','5.1']` for the next. Reading the audio
/// fact by position therefore prints the codec on one screen and `Bilinmiyor`
/// on another, which is worse than saying nothing: a technical stack that is
/// confidently wrong is the one thing this audience opens the page to check.
///
/// Matched on the value's shape instead. The set is closed in practice because
/// it is what an Xtream `audio_codec` and an XMLTV `<audio>` actually carry.
abstract final class StreamFacts {
  static const Set<String> _audio = <String>{'MONO', 'STEREO', '2.0', '5.1', '7.1', 'AAC', 'AC3', 'EAC3', 'DTS'};

  /// The audio fact, or null when the provider sent none.
  static String? audioIn(List<String> facts) {
    for (final String fact in facts) {
      if (_audio.contains(fact.toUpperCase())) return fact;
    }

    return null;
  }

  /// Everything that is not the audio fact, which is what the video row shows.
  static List<String> videoIn(List<String> facts) =>
      facts.where((String fact) => !_audio.contains(fact.toUpperCase())).toList();
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
/// A plain value type, and it stays one once the Xtream client lands: the
/// library controller filters and searches the catalogue in Dart
/// (`explore-controllers.md`), same as `Channel`, so there are no queries
/// here for an ORM model to serve, only a shape to render.
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
  /// because grouping is a view concern: the title screen groups by season and
  /// the catalogue's search reads the same list straight through.
  final List<Episode> episodes;

  /// How far through a movie the viewer got, 0 to 1. Always zero for a series,
  /// which resumes per episode instead.
  final double progress;

  /// Whether the user starred it.
  final bool favourite;

  /// The provider's identifier for this title: a movie's `stream_id`, a
  /// series' `series_id`. The two are different ID spaces that can collide
  /// numerically, and [kind] is what says which space this value came from.
  /// Null on a fixture-built title, which honestly has no provider.
  final int? providerId;

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
    this.providerId,
  });

  /// Builds a [TitleItem] from a decoded `get_vod_streams` (movie) entry
  /// (`tool/xtream-mock/server.mjs:226`). A series equivalent reads the same
  /// shape where the wire carries it; `get_series` answers `[]` on this mock,
  /// so that path is untested against an executable contract here.
  ///
  /// [categoryName] is the resolved `category_name` for the entry's
  /// `category_id`, the same lookup `Channel.fromXtream` takes for a
  /// channel's `group`.
  ///
  /// [kind] says which ID space [providerId] reads from: `stream_id` for a
  /// movie, `series_id` for a series.
  ///
  /// Every field this mock's entry does not carry (`genre`, `year`, cast)
  /// stays at [TitleItem]'s default rather than a guess: an empty [genres]
  /// or a zero [year] is the honest reading of a wire that sent nothing here,
  /// not a mapping gap. [minutes] reads `duration_secs`, which only
  /// `get_vod_info` sends, so it stays null when mapping a `get_vod_streams`
  /// entry directly.
  ///
  /// [facts] holds the container extension, uppercased, when the wire sent
  /// one (`mp4` | `mkv` | `avi`): it is the one technical fact a
  /// `get_vod_streams` entry actually carries.
  factory TitleItem.fromXtream(Map<String, dynamic> entry, {required TitleKind kind, required String categoryName}) {
    final bool series = kind == TitleKind.series;

    // The two actions do NOT share field names, which is the trap here. A
    // `get_vod_streams` movie carries `stream_icon`, `container_extension` and
    // `duration_secs`; a `get_series` entry carries `cover`, `plot`, `genre`
    // and `releaseDate` and none of the movie names. Reading the movie set on
    // a series gave every provider series a null poster and an empty genre
    // list, which `Vitrin` renders as the no-artwork fallback with a note
    // blaming the provider for our mapping. Confirmed against two independent
    // clients, `pbergman/xtream-codes-go` `series.go` (`SeriesId`, `Cover`,
    // `Plot`) and `ektotv/xtream-api` (`plot`, `genre`, `cast`,
    // `backdropPath`). The mock answers `get_series` with `[]`, which is
    // exactly why no test could see it.
    final String? poster = readNullableString(entry, series ? 'cover' : 'stream_icon');
    final String? backdrop = readNullableString(entry, 'backdrop_path');
    final String? containerExtension = series ? null : readNullableString(entry, 'container_extension');
    final int? durationSecs = series ? null : readInt(entry, 'duration_secs');

    return TitleItem(
      kind: kind,
      name: readNullableString(entry, 'name') ?? '',
      category: categoryName,
      year: _year(entry, series: series),
      posterUrl: (poster == null || poster.isEmpty) ? null : poster,
      backdropUrl: (backdrop == null || backdrop.isEmpty) ? null : backdrop,
      minutes: durationSecs == null ? null : (durationSecs / 60).round(),
      rating: readDouble(entry, 'rating'),
      genres: _genres(entry),
      synopsis: series ? readNullableString(entry, 'plot') : null,
      facts: containerExtension == null || containerExtension.isEmpty
          ? const <String>[]
          : <String>[containerExtension.toUpperCase()],
      providerId: series ? readInt(entry, 'series_id') : readInt(entry, 'stream_id'),
    );
  }

  /// The release year, from whichever field the action carries, or `0`.
  ///
  /// A series sends `releaseDate` as a `YYYY-MM-DD` string; a movie sends
  /// nothing at all in the list action, only in the deferred `get_vod_info`.
  /// `0` therefore means "not sent" and every render site treats it that way
  /// rather than printing it (see [metaLabel]).
  static int _year(Map<String, dynamic> entry, {required bool series}) {
    if (!series) return readInt(entry, 'year') ?? 0;

    final String? released = readNullableString(entry, 'releaseDate');
    if (released == null || released.length < 4) return 0;

    return int.tryParse(released.substring(0, 4)) ?? 0;
  }

  /// Genres, from the comma-separated `genre` string a series sends.
  ///
  /// Split and trimmed here rather than at a call site, because the wire sends
  /// one string and every consumer wants a list. A movie's list action sends
  /// no genre at all, so an empty list is the honest answer there.
  static List<String> _genres(Map<String, dynamic> entry) {
    final String? genre = readNullableString(entry, 'genre');
    if (genre == null || genre.trim().isEmpty) return const <String>[];

    return <String>[
      for (final String part in genre.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

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
  String? get lengthLabel {
    if (isSeries) return seasons.isEmpty ? null : '${seasons.length} sezon';

    final int? total = minutes;
    if (total == null || total <= 0) return null;

    final int hours = total ~/ 60;
    final int rest = total % 60;

    return hours == 0 ? '$rest dk' : '${hours}s ${rest}dk';
  }

  /// The year and the runtime as one line, with an absent part omitted.
  ///
  /// Nullable rather than coercing, and that is the whole point. A
  /// `get_vod_streams` entry carries **neither** a year nor a runtime: only
  /// the deferred detail actions do (`tool/xtream-mock/server.mjs:254-269`
  /// sends no `year` and no `duration_secs`), so a provider movie arrives with
  /// `year: 0` and a null [minutes]. Printing those verbatim produced
  /// `0 · 0 dk` on every poster caption, every hero and every title screen in
  /// a provider catalogue: two facts the provider never sent, stated as
  /// though it had. The fixtures always supplied both, which is why no widget
  /// test could see it.
  ///
  /// Empty when neither is known, which a caller renders as no line at all
  /// rather than as an empty one occupying its slot.
  String get metaLabel => <String>[if (year > 0) '$year', if (lengthLabel case final String length) length].join(' · ');

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
    providerId: providerId,
  );
}
