import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The redaction guarantee, asserted as a property of the tree rather than of
/// any one class.
///
/// `MpvPlaybackEngine`'s doc block claims the guarantee is **structural**: no
/// member of `PlaybackEngine` carries text, so a cleaned line has nowhere else
/// to go. That claim is only as good as the boundary around the one raw source,
/// and the boundary is not expressible in the type system:
/// `WatchoolsPlayer.events` is public, its `PlayerEvent.text` is whatever the
/// native side sent, and `playback_layout.dart` already imports the plugin for
/// `WatchoolsPlayerView`. So a screen subscribing past the engine would compile,
/// pass every other test, and put an unredacted FFmpeg line naming the
/// subscription URL into a widget, a semantics label or a log.
///
/// These read source because there is nothing else to read. A structural claim
/// that no test enforces is a habit, and this project has already paid for the
/// difference.
void main() {
  /// Every Dart file under [directory], recursively.
  List<File> dartFiles(String directory) =>
      Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();

  group('the raw event stream', () {
    test('is read by exactly one file, and that file is the engine', () {
      final List<File> sources = dartFiles('lib');

      // The guard first. Without it this test passes by reading nothing, which
      // is the shape of vacuous check this project keeps finding.
      expect(sources.length, greaterThan(50), reason: 'lib/ was not read, so nothing was checked');

      final List<String> readers = <String>[
        for (final File source in sources)
          if (source.readAsStringSync().contains('WatchoolsPlayer.events')) source.path,
      ];

      expect(readers, hasLength(1));
      expect(readers.single, endsWith('lib/app/playback/mpv_playback_engine.dart'));
    });

    test('is not reachable from any screen, which is where a label would print it', () {
      final List<File> screens = <File>[...dartFiles('lib/ui'), ...dartFiles('lib/resources')];

      expect(screens, isNotEmpty, reason: 'no screen files were read, so nothing was checked');

      for (final File screen in screens) {
        final String source = screen.readAsStringSync();

        // `PlayerEvent` as well as the stream, because holding the event type
        // at all in a screen is the step before reading its text.
        expect(
          source.contains('WatchoolsPlayer.events'),
          isFalse,
          reason: '${screen.path} reads the raw event stream, which carries unredacted native text',
        );
        expect(
          source.contains('PlayerEvent'),
          isFalse,
          reason: '${screen.path} handles a raw PlayerEvent, whose text is whatever the native side sent',
        );
      }
    });
  });

  group('the engine interface', () {
    test('carries no String in any member signature', () {
      // The other half of the same guarantee, and the one a future reader is
      // most likely to break by adding a convenience: a `String? get error` or
      // a `Stream<String> logs` would give a cleaned line somewhere to go, and
      // an uncleaned one too.
      //
      // Two allowances, both by name and both narrow. `userAgent` is the one
      // String that crosses, inbound, and it is a header value this app authors
      // rather than native output. And `PlaybackSurface.toString` interpolates
      // an `int` view id and nothing else, which is a value type doing what a
      // value type does; the class carries no other field to leak.
      final String source = File('lib/app/playback/playback_engine.dart').readAsStringSync();
      final Iterable<String> lines = source
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('///'))
          .where((String line) => !line.trimLeft().startsWith('//'));

      for (final String line in lines) {
        if (!line.contains('String')) continue;

        expect(
          line.contains('userAgent') || line.contains('toString'),
          isTrue,
          reason: 'a String crosses PlaybackEngine outside the two allowed places: $line',
        );
      }
    });
  });
}
