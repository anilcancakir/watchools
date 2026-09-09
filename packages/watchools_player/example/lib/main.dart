import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:watchools_player/watchools_player.dart';

/// Drives the spike by hand: open a channel, read back what the renderer says.
///
/// Deliberately plain Material rather than Wind. The app's own UI mandate is
/// Wind, and this example exists to answer a rendering question in the fewest
/// widgets possible; nothing here ships.
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SpikeScreen(),
    );
  }
}

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  /// The mock panel's H.264 channel. Nothing here talks to a real provider:
  /// that account allows one connection and a stray second one evicts whatever
  /// is playing.
  ///
  /// Overridable from the command line so a run can be scripted rather than
  /// typed, which is what the `expiring` account needs: it answers 509 fifteen
  /// seconds in, and that path is only observable by watching for the
  /// `endFile` event.
  ///
  /// ```sh
  /// flutter run -d macos \
  ///   --dart-define=WATCHOOLS_PLAYER_URL=http://127.0.0.1:3300/live/expiring/expiring/10001.m3u8
  /// ```
  final TextEditingController _url = TextEditingController(
    text: const String.fromEnvironment(
      'WATCHOOLS_PLAYER_URL',
      defaultValue: 'http://127.0.0.1:3300/live/demo/demo/10001.m3u8',
    ),
  );

  PlayerState? _state;
  String? _error;
  PlayerEvent? _lastEnd;
  final List<Map<String, Object?>> _seen = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _ticks = <Map<String, Object?>>[];
  Timer? _poll;
  StreamSubscription<PlayerEvent>? _events;
  int? _viewId;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    // mpv's own events rather than the poll below. The poll reads the renderer's
    // shape; only an event carries the reason a stream ended, and a lapsed
    // provider token ends it as a clean EOF that a later poll cannot see.
    _events = WatchoolsPlayer.events.listen((PlayerEvent event) {
      final PlayerTick? tick = event.tick;
      if (tick != null) {
        // Written separately from the rest, because this is the measurement
        // the headless harness could not take: it ran `vo=null, ao=null`, so a
        // healthy stream froze in it. Here `gpu-next` is running, and these
        // rows are what decide whether `underrun` discriminates a real stall.
        _ticks.add(<String, Object?>{
          'session': tick.session,
          'monotonicNs': tick.monotonicNs,
          'timePos': tick.timePos,
          'paused': tick.paused,
          'coreIdle': tick.coreIdle,
          'forwardBytes': tick.forwardBytes,
          'inputRate': tick.inputRate,
          'underrun': tick.underrun,
          'demuxerIdle': tick.demuxerIdle,
        });
        _write('watchools_player_ticks.json', <String, Object?>{
          'ticks': _ticks,
        });
        return;
      }

      // Every other event, not only the end: whether a fault produces any
      // event at all is the question, so an unrecorded one would answer it
      // wrongly.
      _seen.add(<String, Object?>{
        'name': event.name,
        'session': event.session,
        'reason': event.reason,
        'error': event.error,
        'level': event.level,
        'text': event.text,
      });
      _write('watchools_player_events.json', <String, Object?>{
        'events': _seen,
      });

      if (event.isEnd) {
        setState(() => _lastEnd = event);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _events?.cancel();
    _url.dispose();
    super.dispose();
  }

  /// Runs once the platform view exists, which is the only moment its
  /// identifier is known and the earliest mpv can be handed its layer. This
  /// replaced a fixed delay that was racing the first frame.
  Future<void> _onViewReady(int viewId) async {
    _viewId = viewId;

    // The control, before anything is playing: both rects must be still. A
    // video rect that moves here would mean the scoped measurement is reading
    // Flutter's own painting rather than mpv's layer.
    final Map<Object?, Object?> control = await WatchoolsPlayer.captureSelf(
      '${Directory.systemTemp.path}/window_control.png',
      viewId: viewId,
    );
    await _write('watchools_player_control.json', control);

    await _play();
  }

  Future<void> _play() async {
    final int? viewId = _viewId;
    if (viewId == null) {
      setState(() => _error = 'the platform view is not built yet');
      return;
    }

    setState(() {
      _error = null;
      _lastEnd = null;
    });

    try {
      await WatchoolsPlayer.play(
        viewId,
        _url.text,
        userAgent: 'VLC/3.0.20 LibVLC/3.0.20',
      );
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final PlayerState next = await WatchoolsPlayer.state();
        if (mounted) setState(() => _state = next);
        // Written out so the spike can be measured without Screen Recording
        // permission and without reading pixels: `videoOutput` and a non-zero
        // size are what say the renderer configured inside the platform view.
        await _write('watchools_player_state.json', <String, Object?>{
          'running': next.running,
          'videoOutput': next.videoOutput,
          'width': next.width,
          'height': next.height,
          'hasPicture': next.hasPicture,
          'cacheSeconds': next.cacheSeconds,
        });

        // Once there is a picture, prove Flutter is compositing it rather than
        // covering it, then stop measuring.
        if (next.hasPicture && !_captured) {
          _captured = true;
          final Map<Object?, Object?> motion =
              await WatchoolsPlayer.captureSelf(
                '${Directory.systemTemp.path}/window.png',
                viewId: viewId,
              );
          await _write('watchools_player_motion.json', motion);
        }
      });
    } on PlatformException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Inside the sandbox container, not `/tmp`: a sandboxed macOS app cannot
  /// write there and the failure is silent, which is how the first attempt at
  /// this measurement produced nothing at all.
  Future<void> _write(String name, Map<Object?, Object?> payload) {
    return File('${Directory.systemTemp.path}/$name').writeAsString(
      jsonEncode(
        payload.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState? state = _state;
    final PlayerEvent? end = _lastEnd;

    return Scaffold(
      body: Column(
        children: <Widget>[
          // Flutter chrome above the platform view, which is the composition
          // this spike is really testing: an externally drawn CAMetalLayer with
          // Flutter's own layers around it. Nothing here animates, so it also
          // serves as the still control for a motion measurement.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(child: TextField(controller: _url)),
                const SizedBox(width: 8),
                FilledButton(onPressed: _play, child: const Text('Play')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _poll?.cancel();
                    WatchoolsPlayer.stop();
                    setState(() => _state = null);
                  },
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: WatchoolsPlayerView(onReady: _onViewReady),
                ),
                // Flutter content drawn over the video, so a black frame here
                // would be the base-layer bug rather than a playback failure.
                Positioned(
                  left: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.black.withValues(alpha: 0.6),
                    child: Text(
                      _describe(state, end),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _describe(PlayerState? state, PlayerEvent? end) {
    if (_error != null) return 'error: $_error';
    if (end != null) return 'ended  reason=${end.reason}  error=${end.error}';
    if (state == null) return 'idle';

    return 'vo=${state.videoOutput.isEmpty ? "none" : state.videoOutput}  '
        '${state.width}x${state.height}  '
        'picture=${state.hasPicture ? "YES" : "no"}  '
        'cache=${state.cacheSeconds?.toStringAsFixed(1) ?? "-"}s';
  }
}
