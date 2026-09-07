import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/models/title_item.dart';

TitleItem _movie({double progress = 0, int minutes = 120, double? rating}) => TitleItem(
  kind: TitleKind.movie,
  name: 'Sessiz Şehir',
  category: 'Aksiyon',
  year: 2024,
  minutes: minutes,
  rating: rating,
  progress: progress,
);

Episode _ep(int season, int number, {double progress = 0}) =>
    Episode(season: season, number: number, title: 'B$number', minutes: 50, progress: progress);

TitleItem _series(List<Episode> episodes) =>
    TitleItem(kind: TitleKind.series, name: 'Bozkır Hattı', category: 'Dram', year: 2022, episodes: episodes);

void main() {
  group('Episode', () {
    test('codes a season and number the way a Turkish catalogue does', () {
      expect(_ep(2, 4).code, 'S02B04');
      expect(_ep(11, 12).code, 'S11B12');
    });

    test('treats an accidental tap as unstarted and the credits as finished', () {
      // Both bounds exist so a continue-watching row does not fill up with
      // things nobody wants to resume.
      expect(_ep(1, 1, progress: 0.02).inProgress, isFalse);
      expect(_ep(1, 1, progress: 0.04).inProgress, isTrue);
      expect(_ep(1, 1, progress: 0.91).inProgress, isTrue);
      expect(_ep(1, 1, progress: 0.93).inProgress, isFalse);
      expect(_ep(1, 1, progress: 1).inProgress, isFalse);
    });
  });

  group('TitleItem.upNext', () {
    test('is null when the provider sent no episodes', () {
      expect(_series(const <Episode>[]).upNext, isNull);
    });

    test('prefers the part-watched episode over the next unwatched one', () {
      final Episode resume = _ep(2, 2, progress: 0.37);
      final TitleItem series = _series(<Episode>[_ep(1, 1, progress: 1), _ep(2, 1, progress: 1), resume, _ep(2, 3)]);

      expect(series.upNext, same(resume));
    });

    test('falls to the first unwatched episode when nothing is part-watched', () {
      final Episode next = _ep(2, 1);
      final TitleItem series = _series(<Episode>[_ep(1, 1, progress: 1), next, _ep(2, 2)]);

      expect(series.upNext, same(next));
    });

    test('falls to the very first episode when everything is finished', () {
      // A rewatch has to start somewhere, and an empty play button is worse
      // than one pointed at the pilot.
      final TitleItem series = _series(<Episode>[_ep(1, 1, progress: 1), _ep(1, 2, progress: 1)]);

      expect(series.upNext?.code, 'S01B01');
    });
  });

  group('TitleItem', () {
    test('reports seasons ascending and deduplicated', () {
      final TitleItem series = _series(<Episode>[_ep(3, 1), _ep(1, 1), _ep(1, 2), _ep(2, 1)]);

      expect(series.seasons, <int>[1, 2, 3]);
      expect(series.episodesOf(1).length, 2);
    });

    test('is in progress when any episode is, not when the container is', () {
      expect(_series(<Episode>[_ep(1, 1), _ep(1, 2)]).inProgress, isFalse);
      expect(_series(<Episode>[_ep(1, 1), _ep(1, 2, progress: 0.5)]).inProgress, isTrue);
    });

    test('labels length as hours and minutes for a film and seasons for a series', () {
      expect(_movie(minutes: 132).lengthLabel, '2s 12dk');
      expect(_movie(minutes: 47).lengthLabel, '47 dk');
      // The whole-hour case, where the minutes part is zero and still printed.
      expect(_movie(minutes: 180).lengthLabel, '3s 0dk');
      expect(_series(<Episode>[_ep(1, 1), _ep(2, 1)]).lengthLabel, '2 sezon');
    });

    test('labels a rating with the decimal comma Turkish uses', () {
      expect(_movie(rating: 7.8).ratingLabel, '7,8');
      expect(_movie(rating: 8).ratingLabel, '8,0');
      expect(_movie().ratingLabel, isNull);
    });

    test('toggling a favourite keeps every other field', () {
      final TitleItem before = _movie(progress: 0.4, rating: 7.1);
      final TitleItem after = before.toggleFavourite();

      expect(after.favourite, isTrue);
      expect(after.progress, before.progress);
      expect(after.rating, before.rating);
      expect(after.name, before.name);
      expect(after.toggleFavourite().favourite, isFalse);
    });
  });
}
