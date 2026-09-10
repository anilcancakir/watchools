import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/controllers/playback_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/playback/fake_playback_engine.dart';
import 'package:watchools/app/playback/playback_engine.dart';
import 'package:watchools/app/protocol/xtream/xtream_client.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/provider_session.dart';
import 'package:watchools_player/watchools_player.dart';

/// The one panel shape these tests need: a healthy handshake and one live
/// channel that carries a `stream_id`, which is what makes
/// [ProviderSession.streamUrlFor] answer non-null.
MagicResponse _panel(MagicRequest request) {
  final String action = request.queryParameters?['action'] as String? ?? '';

  switch (action) {
    case '':
      return MagicResponse(
        data: <String, dynamic>{
          'user_info': <String, dynamic>{
            'auth': 1,
            'status': 'Active',
            'exp_date': null,
            'max_connections': '2',
            'active_cons': '0',
            'allowed_output_formats': <String>['m3u8', 'ts'],
          },
          'server_info': <String, dynamic>{'timestamp_now': 1700000000, 'time_now': '2023-11-14 00:00:00'},
        },
        statusCode: 200,
      );
    case 'get_live_categories':
      return MagicResponse(
        data: <Map<String, dynamic>>[
          <String, dynamic>{'category_id': '1', 'category_name': 'Ulusal'},
        ],
        statusCode: 200,
      );
    case 'get_live_streams':
      return MagicResponse(
        data: <Map<String, dynamic>>[
          <String, dynamic>{
            'num': 2,
            'name': '02 H.264 AAC | RAW TS',
            'stream_id': 10002,
            'category_id': '1',
            'epg_channel_id': null,
            'tv_archive': 0,
          },
        ],
        statusCode: 200,
      );
    default:
      return MagicResponse(data: const <dynamic>[], statusCode: 200);
  }
}

/// A tick carrying only what [StallDetector] reads, so a test states the
/// shape it means rather than nine fields it does not.
///
/// [monotonicNs] is the discriminator for every freeze threshold, so it is
/// required: a sequence that forgets to advance it is a sequence that cannot
/// cross the grace.
PlaybackTick _tick({
  required int monotonicNs,
  double? timePos,
  bool paused = false,
  bool coreIdle = false,
  bool? underrun = false,
  bool demuxerIdle = false,
}) => PlaybackTick(
  session: 1,
  monotonicNs: monotonicNs,
  timePos: timePos,
  paused: paused,
  coreIdle: coreIdle,
  forwardBytes: 80000,
  inputRate: 500000,
  underrun: underrun,
  demuxerIdle: demuxerIdle,
);

const Channel _playable = Channel(
  number: 2,
  name: '02 H.264 AAC | RAW TS',
  group: 'Ulusal',
  status: ChannelStatus.live,
  streamId: 10002,
);

/// What a fixture-built channel looks like: no provider identity at all.
const Channel _fixtureBuilt = Channel(number: 2, name: 'TRT 1', group: 'Ulusal', status: ChannelStatus.live);

void main() {
  MagicTest.init();

  final XtreamCredentials credentials = XtreamCredentials(
    baseUrl: 'http://panel.example:8080',
    username: 'demo',
    password: 'demo',
    userAgent: 'watchools/test',
  );

  setUp(() {
    DatabaseManager().setConnection(sqlite3.openInMemory());
    Magic.singleton(XtreamClient.driverKey, () => FakeNetworkDriver(stubs: _panel));
  });

  tearDown(() {
    DatabaseManager().dispose();
    Vault.unfake();
  });

  /// A session that has handshaken and holds one playable channel.
  Future<ProviderSession> readySession() async {
    Vault.fake();
    await credentials.save();

    final ProviderSession session = ProviderSession();
    await session.start();
    await session.refresh();

    return session;
  }

  group('play', () {
    test('loads exactly the URL the session derived, and nothing it built itself', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      // Asked of the session rather than typed out. A hand-written expectation
      // agrees with itself instead of with the thing under test, which is how
      // wave 1 let a percent-encoding mismatch through.
      expect(engine.source, session.streamUrlFor(_playable));
      expect(engine.source, isNotNull);
      expect(controller.channel, _playable);
      expect(engine.commands, contains(FakePlaybackCommand.load));
    });

    test('carries the per-provider user agent, which resellers key access to', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      expect(engine.userAgent, 'watchools/test');
    });

    test('reports a reason for an unplayable channel rather than throwing or loading', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_fixtureBuilt);

      expect(controller.unplayable, isTrue);
      // Kept rather than cleared, so the screen can name what it is refusing.
      expect(controller.channel, _fixtureBuilt);
      expect(engine.commands, isNot(contains(FakePlaybackCommand.load)));
    });

    test('clears the unplayable report once a playable channel follows', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_fixtureBuilt);
      await controller.play(_playable);

      expect(controller.unplayable, isFalse);
      expect(controller.channel, _playable);
    });
  });

  group('togglePause', () {
    test('reaches the engine, and moves no verdict by itself', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      engine.emit(_tick(monotonicNs: 0, timePos: 10));
      engine.emit(_tick(monotonicNs: 1000000000, timePos: 11));

      expect(controller.health, PlaybackHealth.playing);

      await controller.togglePause();

      // The command reached the engine, but the verdict is the tick's to
      // change, which is how mpv behaves and therefore what the screen must
      // be written against.
      expect(engine.commands, contains(FakePlaybackCommand.pause));
      expect(controller.health, PlaybackHealth.playing);

      engine.emit(_tick(monotonicNs: 2000000000, timePos: 11, paused: true));

      expect(controller.health, PlaybackHealth.paused);
    });

    test('resumes on a second call, reading the engine rather than a local flag', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      engine.emit(_tick(monotonicNs: 0, timePos: 10));
      await controller.togglePause();
      engine.emit(_tick(monotonicNs: 1000000000, timePos: 10, paused: true));
      await controller.togglePause();

      expect(engine.commands, contains(FakePlaybackCommand.resume));
    });
  });

  group('notification', () {
    test('fires on a health change and not on every tick', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      int notifications = 0;
      controller.addListener(() => notifications++);

      // Ten ticks that all read `playing`: one verdict change, so one repaint.
      // A tick arrives twice a second, so notifying per tick would repaint the
      // overlay 120 times a minute for nothing visible.
      for (int i = 0; i < 10; i++) {
        engine.emit(_tick(monotonicNs: i * 1000000000, timePos: 10 + i.toDouble()));
      }

      // `ticks` is a broadcast stream, so a listener runs a microtask after
      // `emit` rather than inside it. Draining the queue is what makes the
      // count below about the controller instead of about scheduling.
      await Future<void>.delayed(Duration.zero);

      expect(controller.health, PlaybackHealth.playing);
      expect(notifications, 1);

      // And the other direction, which is what stops this test passing on a
      // controller that never notifies at all: a real change must fire.
      engine.emit(_tick(monotonicNs: 10000000000, timePos: 20, paused: true));
      await Future<void>.delayed(Duration.zero);

      expect(controller.health, PlaybackHealth.paused);
      expect(notifications, 2);
    });

    test('an asleep display is reported as itself, not as a stall', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      // The measured idle-display shape (`.ac/research/player-layer.md:587`):
      // the position freezes while the buffer stays full and the demuxer is
      // satisfied, because nothing is presenting. It recovers on wake, so no
      // variant switch fixes it.
      engine.emit(_tick(monotonicNs: 0, timePos: 0.08));
      engine.emit(_tick(monotonicNs: 30000000000, timePos: 0.08, demuxerIdle: true));

      expect(controller.health, PlaybackHealth.notPresenting);
    });
  });

  group('stop and teardown', () {
    test('stop reaches the engine and forgets the channel', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      await controller.stop();

      expect(engine.commands, contains(FakePlaybackCommand.stop));
      expect(controller.channel, isNull);
      expect(controller.health, PlaybackHealth.idle);
    });

    test('onClose stops the core and detaches from both sources', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      // A tick before teardown, so the session has actually been playing. It
      // also gives the engine a stamp to measure a later tick against: with no
      // stamp at all, a post-stop tick is indistinguishable from a first one
      // and the fake accepts it, which would make the assertion below pass for
      // the wrong reason.
      engine.emit(_tick(monotonicNs: 0, timePos: 10));
      await Future<void>.delayed(Duration.zero);

      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.onClose();

      // The connection budget on the measured account is one, so a session
      // left open is the reason the next device in the house cannot watch.
      expect(engine.commands, contains(FakePlaybackCommand.stop));

      // Detached from the engine, provable rather than asserted: a tick after
      // teardown reaches nobody, so no verdict moves and nothing repaints.
      // `ChangeNotifier.hasListeners` is `@protected`, so the session detach is
      // observed the same way, through the absence of an effect.
      engine.emit(_tick(monotonicNs: 60000000000, timePos: 99, paused: true));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
      expect(controller.health, PlaybackHealth.idle);
    });
  });

  group('the connection gate the composition root closes', () {
    // The closure `AppServiceProvider.register()` passes to `ProviderSession`,
    // written out here so its logic is tested without booting the providers.
    // The real one reads the controller through the container; this one reads
    // the same controller directly, and the predicate is the part that matters.
    test('an open core of any health blocks a refresh, and only idle lets it through', () async {
      final ProviderSession playbackSession = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: playbackSession);

      bool isPlaying() => controller.health != PlaybackHealth.idle;

      expect(isPlaying(), isFalse, reason: 'nothing has played, so the slot is free');

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      engine.emit(_tick(monotonicNs: 0, timePos: 10));
      engine.emit(_tick(monotonicNs: 1000000000, timePos: 11));

      expect(controller.health, PlaybackHealth.playing);
      expect(isPlaying(), isTrue);

      // A paused core still holds the connection. Reading `== playing` here
      // instead would let a refresh evict a viewer who had merely paused, and
      // the measured account allows exactly one stream.
      engine.emit(_tick(monotonicNs: 2000000000, timePos: 11, paused: true));

      expect(controller.health, PlaybackHealth.paused);
      expect(isPlaying(), isTrue);

      // A frozen clock with the buffer full is an asleep display, which is
      // still an open core.
      engine.emit(_tick(monotonicNs: 30000000000, timePos: 11, demuxerIdle: true));

      expect(controller.health, PlaybackHealth.notPresenting);
      expect(isPlaying(), isTrue);

      await controller.stop();

      expect(isPlaying(), isFalse, reason: 'stop released the slot');
    });
  });

  // The ordering the line-up actually produces: `play` first, the route push
  // second, so the surface arrives a frame after the choice. Asserted here
  // rather than through the screen, because a screen test resolves a session
  // with no credential, `streamUrlFor` returns null, and every assertion about
  // what the engine saw then passes because nothing happened at all. Two tests
  // added with the ordering fix did exactly that.
  group('a channel chosen before a surface exists', () {
    test('is held rather than opened, and opens when the surface arrives', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      // No attach yet. The URL is derivable, so this is the state the ordering
      // defect actually occurred in: the earlier version called `load` here,
      // which threw `StateError` into an unawaited future.
      await controller.play(_playable);

      expect(engine.commands, isEmpty);
      expect(controller.channel, _playable);
      expect(controller.unplayable, isFalse);

      await controller.attach(const PlaybackSurface(platformViewId: 7));

      // Attach before load, which is the engine's own rule, and the held
      // channel is what was opened.
      expect(engine.commands, <FakePlaybackCommand>[FakePlaybackCommand.attach, FakePlaybackCommand.load]);
      expect(engine.source, session.streamUrlFor(_playable));
    });

    test('is dropped by a stop, so the next surface opens nothing', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.play(_playable);
      await controller.stop();
      await controller.attach(const PlaybackSurface(platformViewId: 7));

      expect(engine.commands, isNot(contains(FakePlaybackCommand.load)));
    });

    test('retry re-opens the held channel, before any surface has arrived', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.play(_playable);
      await controller.retry();

      // Still held, not opened: `retry` is `play` again and the surface is
      // still absent. What it must not do is lose the channel.
      expect(controller.channel, _playable);
      expect(engine.commands, isEmpty);

      await controller.attach(const PlaybackSurface(platformViewId: 7));

      expect(engine.commands, contains(FakePlaybackCommand.load));
    });

    test('retry re-opens an already playing channel through the engine', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      await controller.retry();

      // Two loads, which is what "make the request again" means for the two
      // faults whose panel offers it. A retry that toggled pause instead would
      // be toggling a core that never opened.
      expect(engine.commands.where((FakePlaybackCommand c) => c == FakePlaybackCommand.load).length, 2);
    });

    test('retry with nothing chosen does nothing at all', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.retry();

      expect(engine.commands, isEmpty);
    });
  });

  group('detach, which is the only signal Dart gets that the surface is gone', () {
    test('stops the core and forgets the surface, so the next visit holds instead of loading', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);
      await controller.detach();

      // The native side stops the core on its own when it prunes the view
      // (`WatchoolsPlayerPlugin.swift:186-191`), so this is Dart catching up
      // with what already happened rather than initiating it.
      expect(engine.commands, contains(FakePlaybackCommand.stop));
      expect(controller.channel, isNull);
      expect(controller.health, PlaybackHealth.idle);

      // The second visit. `play` comes before the new surface again, and it
      // must hold: sending the previous view id gets `no-view` back, and the
      // earlier version did exactly that on every visit after the first.
      final int loadsBefore = engine.commands.where((FakePlaybackCommand c) => c == FakePlaybackCommand.load).length;

      await controller.play(_playable);

      expect(
        engine.commands.where((FakePlaybackCommand c) => c == FakePlaybackCommand.load).length,
        loadsBefore,
        reason: 'no surface is attached, so the channel is held',
      );

      await controller.attach(const PlaybackSurface(platformViewId: 8));

      expect(engine.commands.where((FakePlaybackCommand c) => c == FakePlaybackCommand.load).length, loadsBefore + 1);
      expect(engine.surface?.platformViewId, 8);
    });

    test('releases the gate the composition root closes, which would otherwise latch', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      // The real closure from `AppServiceProvider.register()`, verbatim.
      bool isPlaying() => controller.channel != null || controller.health != PlaybackHealth.idle;

      await controller.attach(const PlaybackSurface(platformViewId: 7));
      await controller.play(_playable);

      expect(isPlaying(), isTrue);

      // A route pop with no press of the back affordance, which is the
      // ordinary way to leave a screen. Without this the channel would stay
      // set for the life of the process, the gate would never reopen, and no
      // catalogue refresh would ever run again.
      await controller.detach();

      expect(isPlaying(), isFalse);
    });

    test('is safe before any engine has been built, which is a screen opened and left', () async {
      final ProviderSession session = await readySession();
      final PlaybackController controller = PlaybackController(
        engine: () => throw StateError('the engine must not be built by detach'),
        session: session,
      );

      await controller.detach();
    });
  });

  group('the fault the screen renders', () {
    test('comes from the session rather than a second vocabulary', () async {
      final ProviderSession session = await readySession();
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final PlaybackController controller = PlaybackController(engine: () => engine, session: session);

      expect(controller.fault, session.fault);
    });
  });
}
