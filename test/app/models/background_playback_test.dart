import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/models/background_playback.dart';

void main() {
  group('BackgroundPlayback.parse', () {
    test('reads back every value storedValue writes', () {
      for (final BackgroundPlayback choice in BackgroundPlayback.values) {
        expect(BackgroundPlayback.parse(choice.storedValue), choice, reason: 'round trip failed for $choice');
      }
    });

    test('is stop for a credential that carries no setting', () {
      expect(BackgroundPlayback.parse(null), BackgroundPlayback.stop);
    });

    test('is stop for a name written by a build that knew more members than this one', () {
      expect(BackgroundPlayback.parse('holographicProjection'), BackgroundPlayback.stop);
    });

    test('is stop for an empty string, which a hand-edited vault blob can carry', () {
      expect(BackgroundPlayback.parse(''), BackgroundPlayback.stop);
    });
  });

  group('BackgroundPlayback.storedValue', () {
    test('is null for stop, so the credential blob gains no key for a user who never chose', () {
      expect(BackgroundPlayback.stop.storedValue, isNull);
    });

    test('is the member name for the two choices that are not the default', () {
      expect(BackgroundPlayback.audio.storedValue, 'audio');
      expect(BackgroundPlayback.pictureInPicture.storedValue, 'pictureInPicture');
    });
  });

  group('the member order', () {
    // The default is read off the first member in more than one place, and a
    // reordering that made `audio` first would silently keep every backgrounded
    // stream alive on an account whose measured connection limit is 1.
    test('puts stop first, because it is the default the whole feature degrades to', () {
      expect(BackgroundPlayback.values.first, BackgroundPlayback.stop);
    });
  });
}
