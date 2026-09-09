import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A spike, not the player.
///
/// It answers one question: does libmpv render into a `CAMetalLayer` that
/// Flutter composites? The `PlaybackEngine` the research calls for, with buffer,
/// live offset, position, telemetry and fault as first-class members, gets
/// written once that is settled, and it will not look like this.
class WatchoolsPlayer {
  static const MethodChannel _channel = MethodChannel('watchools_player');

  /// Opens [url] in the platform view.
  ///
  /// [userAgent] is per provider rather than per app: panels behind Cloudflare
  /// challenge generic clients and allowlist player signatures, so a provider
  /// carries its own. Normalise the header key to exactly `User-Agent`
  /// elsewhere in the app; here it reaches mpv's own option and the casing does
  /// not matter.
  static Future<void> play(String url, {String? userAgent}) {
    return _channel.invokeMethod<void>('play', <String, Object?>{
      'url': url,
      'userAgent': userAgent,
    });
  }

  /// What the renderer is doing.
  ///
  /// `cacheSeconds` is nullable because mpv's own documentation calls the
  /// underlying guess "very unreliable, and often the property will not be
  /// available at all". Read it as a hint, never as a gate.
  static Future<PlayerState> state() async {
    final Map<Object?, Object?>? raw =
        await _channel.invokeMethod<Map<Object?, Object?>>('state');

    return PlayerState.fromNative(raw ?? const <Object?, Object?>{});
  }

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Captures the app's own window twice and reports how much moved.
  ///
  /// A spike affordance. An app may capture its own window without Screen
  /// Recording permission, while a helper outside the process cannot, which is
  /// why this has to live behind the channel to be usable at all.
  static Future<Map<Object?, Object?>> captureSelf(String path) async {
    final Map<Object?, Object?>? raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('captureSelf', <String, Object?>{'path': path});

    return raw ?? const <Object?, Object?>{};
  }
}

/// What the native side reports back.
@immutable
class PlayerState {
  /// Whether a core exists at all.
  final bool running;

  /// mpv's `current-vo`. Empty until the video output configures, which is the
  /// signal that the renderer came up rather than merely that the demuxer did.
  final String videoOutput;

  /// Decoded frame size. Zero before the first video reconfig.
  final int width;
  final int height;

  /// Seconds of demuxer cache, when mpv is willing to guess.
  final double? cacheSeconds;

  const PlayerState({
    required this.running,
    required this.videoOutput,
    required this.width,
    required this.height,
    required this.cacheSeconds,
  });

  /// Reads the native map, which uses NSNull for an unavailable property.
  factory PlayerState.fromNative(Map<Object?, Object?> raw) {
    final Object? cache = raw['cacheSeconds'];

    return PlayerState(
      running: raw['running'] == true,
      videoOutput: raw['videoOutput'] as String? ?? '',
      width: raw['width'] as int? ?? 0,
      height: raw['height'] as int? ?? 0,
      cacheSeconds: cache is num ? cache.toDouble() : null,
    );
  }

  /// Whether the video output configured and decoded a frame size.
  ///
  /// Not the same as "a stream opened": the measurement that motivated this
  /// package found a channel whose audio played while its video track never
  /// resolved, reported as ready with no error anywhere.
  bool get hasPicture => videoOutput.isNotEmpty && width > 0 && height > 0;
}

/// The surface mpv draws into.
///
/// Gestures do not reach Flutter's arena through a macOS platform view, so every
/// control belongs in Flutter above this widget rather than inside it. That is
/// where they want to be anyway, for one design across touch, mouse and D-pad.
class WatchoolsPlayerView extends StatelessWidget {
  const WatchoolsPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    // No hit-test behaviour is set, because there is nothing useful to set it
    // to: Flutter's gesture arena does not hand gestures to a macOS platform
    // view at all, so a tap here is the platform's business and every control
    // lives in Flutter above this widget.
    return const AppKitView(viewType: 'watchools_player/view');
  }
}
