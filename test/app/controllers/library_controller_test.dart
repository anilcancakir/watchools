import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/app/models/title_item.dart';

/// The catalogue controller.
///
/// Same reasoning as the line-up's: these are the claims the end-to-end walk
/// can only see through whatever a layout chose to render, and the resume
/// behaviour in particular has exactly one right answer that is worth pinning
/// somewhere faster than a browser.
void main() {
  late LibraryController controller;

  /// The fixture series that is finished through S02B01 and part way into
  /// S02B02, which is the only arrangement where `upNext` is unambiguous.
  ///
  /// Re-read from the list each call rather than captured, because starring
  /// replaces the instance.
  TitleItem bozkir() => controller.titles.firstWhere((TitleItem t) => t.name == 'Bozkır Hattı');

  setUp(() => controller = LibraryController());

  group('scope', () {
    test('starts on the whole catalogue', () {
      expect(controller.scope, LibraryScope.all);
      expect(controller.matches.length, controller.titles.length);
    });

    test('films excludes series and series excludes films', () {
      controller.showScope(LibraryScope.movies);
      expect(controller.matches.every((TitleItem t) => !t.isSeries), isTrue);

      controller.showScope(LibraryScope.series);
      expect(controller.matches.every((TitleItem t) => t.isSeries), isTrue);

      controller.showScope(LibraryScope.all);
      expect(controller.matches.length, controller.titles.length);
    });

    test('the selection follows the scope rather than pointing off screen', () {
      controller.select(controller.titles.firstWhere((TitleItem t) => t.isSeries));
      controller.showScope(LibraryScope.movies);

      expect(controller.selected.isSeries, isFalse);
      expect(controller.matches, contains(controller.selected));
    });

    test('a scope with matches keeps a selection that is still in it', () {
      final TitleItem film = controller.titles.firstWhere((TitleItem t) => !t.isSeries);
      controller.select(film);
      controller.showScope(LibraryScope.movies);

      expect(controller.selected, same(film));
    });
  });

  group('categories', () {
    test('match the provider category OR the genre list', () {
      // A viewer who taps Dram means either, because `category_name` is one
      // string while `genre` carries several.
      controller.selectCategory('Dram');

      expect(controller.matches, isNotEmpty);
      expect(controller.matches.every((TitleItem t) => t.category == 'Dram' || t.genres.contains('Dram')), isTrue);
      expect(
        controller.matches.any((TitleItem t) => t.category != 'Dram' && t.genres.contains('Dram')),
        isTrue,
        reason: 'the fixture has a title that only matches Dram by genre',
      );
    });

    test('İzlemeye devam et shows only what was started and not finished', () {
      controller.selectCategory('İzlemeye devam et');

      expect(controller.matches, isNotEmpty);
      expect(controller.matches.every((TitleItem t) => t.inProgress), isTrue);
    });

    test('Favoriler shows only starred titles', () {
      controller.selectCategory('Favoriler');
      final int starred = controller.matches.length;

      expect(starred, greaterThan(0), reason: 'the fixture ships two pre-starred titles');
      expect(controller.matches.every((TitleItem t) => t.favourite), isTrue);
    });

    test('Tümü widens again', () {
      controller.selectCategory('Komedi');
      expect(controller.matches.length, lessThan(controller.titles.length));

      controller.selectCategory('Tümü');
      expect(controller.matches.length, controller.titles.length);
    });
  });

  group('search', () {
    test('reaches episode titles, not only the top level', () {
      // People remember the episode, not the season number.
      controller.search('Sınır Taşı');

      expect(controller.matches.length, 1);
      expect(controller.matches.first.name, 'Bozkır Hattı');
    });

    test('covers the name and the year', () {
      controller.search('Sessiz');
      expect(controller.matches.map((TitleItem t) => t.name), contains('Sessiz Şehir'));

      controller.search('1998');
      expect(controller.matches, isNotEmpty);
      expect(controller.matches.every((TitleItem t) => t.year == 1998), isTrue);
    });

    test('an unmatched term empties the catalogue rather than throwing', () {
      controller.search('zzzzzz');

      expect(controller.matches, isEmpty);
      expect(controller.sections, isEmpty);
      expect(controller.continueWatching, isEmpty);
    });
  });

  group('the counts every layout renders', () {
    test('countLabel says başlık without a query and sonuç with one', () {
      expect(controller.countLabel, endsWith('başlık'));

      controller.search('Sınır');
      expect(controller.countLabel, endsWith('sonuç'));
    });

    test('noArtworkNote counts the matches with no poster and hides at zero', () {
      expect(controller.noArtworkNote, isNotNull);

      controller.search('Sessiz Şehir');
      expect(controller.matches.length, 1);
      expect(controller.matches.first.posterUrl, isNotNull);
      expect(controller.noArtworkNote, isNull);
    });
  });

  group('the title screen', () {
    test('opens on the season the next episode is in, not season one', () {
      controller.select(bozkir());

      expect(controller.season, 2);
      expect(bozkir().upNext?.code, 'S02B02');
    });

    test('a movie has no meaningful season and does not crash asking', () {
      controller.select(controller.titles.firstWhere((TitleItem t) => !t.isSeries));

      expect(controller.season, 1);
    });

    test('opening a title leaves the catalogue filters alone', () {
      // The two routes share one controller, so the title screen is the one
      // place a stray write would silently reset what the viewer had narrowed
      // to and only show up when they pressed back.
      controller.selectCategory('Dram');
      controller.showScope(LibraryScope.movies);
      final int matched = controller.matches.length;

      controller.select(controller.matches.last);
      controller.selectSeason(1);

      expect(controller.category, 'Dram');
      expect(controller.scope, LibraryScope.movies);
      expect(controller.matches.length, matched);
    });

    test('selecting a season holds', () {
      controller.select(bozkir());
      controller.selectSeason(3);

      expect(controller.season, 3);
      expect(bozkir().episodesOf(3), isNotEmpty);
    });
  });

  group('favourites', () {
    test('starring keeps the selection on the new instance', () {
      final TitleItem target = controller.titles.firstWhere((TitleItem t) => !t.favourite);
      controller.select(target);
      controller.toggleFavourite(target);

      expect(controller.selected.favourite, isTrue);
      expect(controller.selected.name, target.name);
    });

    test('starring an unselected title leaves the selection alone', () {
      final TitleItem selected = controller.selected;
      final TitleItem other = controller.titles.lastWhere((TitleItem t) => t.name != selected.name);
      controller.toggleFavourite(other);

      expect(controller.selected.name, selected.name);
    });
  });

  group('the rails Vitrin draws', () {
    test('continueWatching is what was started and not finished', () {
      expect(controller.continueWatching, isNotEmpty);
      expect(controller.continueWatching.every((TitleItem t) => t.inProgress), isTrue);
    });

    test('sections cover every match exactly once', () {
      final int counted = controller.sections.fold(0, (int n, (String, List<TitleItem>) s) => n + s.$2.length);

      expect(counted, controller.matches.length);
    });
  });

  group('the frame caches', () {
    test('hand back the same list until something changes', () {
      expect(controller.matches, same(controller.matches));
      expect(controller.sections, same(controller.sections));
    });

    test('are dropped by a scope change, a category change and a star', () {
      final List<TitleItem> before = controller.matches;

      controller.showScope(LibraryScope.series);
      expect(controller.matches, isNot(same(before)));

      final List<TitleItem> byScope = controller.matches;
      controller.selectCategory('Dram');
      expect(controller.matches, isNot(same(byScope)));

      final List<TitleItem> byCategory = controller.matches;
      controller.toggleFavourite(controller.titles.first);
      expect(controller.matches, isNot(same(byCategory)));
    });
  });
}
