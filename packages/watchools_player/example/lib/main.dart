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
  final TextEditingController _url = TextEditingController(
    text: 'http://127.0.0.1:3300/live/demo/demo/10001.m3u8',
  );

  PlayerState? _state;
  String? _error;
  Timer? _poll;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    // Autoplay so the spike can be measured without driving the UI. The
    // platform view has to exist before mpv is handed its layer, and the view
    // is built on the first frame, so this waits for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 300), _play);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _url.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() => _error = null);
    try {
      await WatchoolsPlayer.play(_url.text, userAgent: 'VLC/3.0.20 LibVLC/3.0.20');
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final PlayerState next = await WatchoolsPlayer.state();
        if (mounted) setState(() => _state = next);
        // Written out so the spike can be measured without Screen Recording
        // permission and without reading pixels: `videoOutput` and a non-zero
        // size are what say the renderer configured inside the platform view.
        // Inside the sandbox container, not /tmp: a sandboxed macOS app cannot
        // write there and the failure is silent, which is how the first attempt
        // at this measurement produced nothing at all.
        await File('${Directory.systemTemp.path}/watchools_player_state.json').writeAsString(jsonEncode(<String, Object?>{
          'running': next.running,
          'videoOutput': next.videoOutput,
          'width': next.width,
          'height': next.height,
          'hasPicture': next.hasPicture,
          'cacheSeconds': next.cacheSeconds,
        }));

        // Once there is a picture, prove Flutter is compositing it rather than
        // covering it, then stop measuring.
        if (next.hasPicture && !_captured) {
          _captured = true;
          final Map<Object?, Object?> motion =
              await WatchoolsPlayer.captureSelf('${Directory.systemTemp.path}/window.png');
          await File('${Directory.systemTemp.path}/watchools_player_motion.json')
              .writeAsString(jsonEncode(motion.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v))));
        }
      });
    } on PlatformException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState? state = _state;

    return Scaffold(
      body: Column(
        children: <Widget>[
          // Flutter chrome above the platform view, which is the composition
          // this spike is really testing: an externally drawn CAMetalLayer with
          // Flutter's own layers around it.
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
                const Positioned.fill(child: WatchoolsPlayerView()),
                // Flutter content drawn over the video, so a black frame here
                // would be the base-layer bug rather than a playback failure.
                Positioned(
                  left: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: Colors.black.withValues(alpha: 0.6),
                    child: Text(
                      _error != null
                          ? 'error: $_error'
                          : state == null
                              ? 'idle'
                              : 'vo=${state.videoOutput.isEmpty ? "none" : state.videoOutput}  '
                                  '${state.width}x${state.height}  '
                                  'picture=${state.hasPicture ? "YES" : "no"}  '
                                  'cache=${state.cacheSeconds?.toStringAsFixed(1) ?? "-"}s',
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
}
