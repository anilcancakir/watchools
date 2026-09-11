import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

export 'src/stall_detector.dart';

/// A spike, not the player.
///
/// It answers one question: does libmpv render into a `CAMetalLayer` that
/// Flutter composites? The `PlaybackEngine` the research calls for, with buffer,
/// live offset, position, telemetry and fault as first-class members, gets
/// written once that is settled, and it will not look like this.
class WatchoolsPlayer {
  static const MethodChannel _channel = MethodChannel('watchools_player');
  static const EventChannel _events = EventChannel('watchools_player/events');

  /// Opens [url] in the platform view identified by [viewId].
  ///
  /// The identifier is required rather than implied because Flutter builds a
  /// platform view before the widget owning it settles and rebuilds it on a
  /// route change, so "the current view" points at whichever was created last,
  /// which during a push is the one about to be discarded.
  ///
  /// [userAgent] is per provider rather than per app: panels behind Cloudflare
  /// challenge generic clients and allowlist player signatures, so a provider
  /// carries its own. Normalise the header key to exactly `User-Agent`
  /// elsewhere in the app; here it reaches mpv's own option and the casing does
  /// not matter.
  static Future<void> play(int viewId, String url, {String? userAgent}) {
    return _channel.invokeMethod<void>('play', <String, Object?>{
      'viewId': viewId,
      'url': url,
      'userAgent': userAgent,
    });
  }

  /// mpv's own events, in place of polling [state].
  ///
  /// A poll cannot see what these carry, and for the fault that matters most it
  /// sees nothing at all. Measured against a lapsing provider token: no
  /// `endFile` ever arrives, and [state] keeps reporting a configured renderer
  /// with a cache duration frozen at the value it held when the token died. The
  /// only signal is a `log` event at `warn`, FFmpeg's own
  /// `http: Will reconnect ... error=End of file`, followed by an `error` line
  /// when it gives up.
  ///
  /// One field rather than a getter, and that is load-bearing rather than tidy.
  /// `receiveBroadcastStream` builds a **new** `StreamController` on every call
  /// whose `onListen` runs `binaryMessenger.setMessageHandler(name, ...)`
  /// (`platform_channel.dart:697`), and a binary messenger holds exactly one
  /// handler per channel name. So a second call's first listener silently
  /// steals the stream from the first: measured, the original listener then
  /// received nothing at all. Either one's `onCancel` also sets the handler to
  /// null and tears it down for both. The variant ladder and a mini player are
  /// two consumers by construction, so a getter here would have been a fault
  /// channel that goes quiet the moment a second reader arrives.
  ///
  /// `static final` is lazy in Dart, so the channel is not touched until
  /// somebody listens.
  static final Stream<PlayerEvent> events = _events
      .receiveBroadcastStream()
      .map(
        (Object? raw) => PlayerEvent.fromNative(
          (raw as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
        ),
      );

  /// What the renderer is doing.
  ///
  /// `cacheSeconds` is nullable because mpv's own documentation calls the
  /// underlying guess "very unreliable, and often the property will not be
  /// available at all". Read it as a hint, never as a gate.
  static Future<PlayerState> state() async {
    final Map<Object?, Object?>? raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('state');

    return PlayerState.fromNative(raw ?? const <Object?, Object?>{});
  }

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Writes mpv's `pause` flag.
  ///
  /// The other half of [PlayerTick.paused], which the native side already
  /// reads every tick: until this existed, nothing in the app could change
  /// what that field reports. Kept to pause on purpose: no seek, no volume,
  /// no speed, no track selection, because the `PlaybackEngine` this package
  /// is one step toward promises none of them yet.
  static Future<void> setPaused(bool paused) {
    return _channel.invokeMethod<void>('setPaused', paused);
  }

  /// Drops the native side's reference to [viewId] and tears the core down if
  /// that view was the one being rendered into.
  ///
  /// Called from [WatchoolsPlayerView]'s `dispose`. Without it mpv keeps
  /// rendering into a `CAMetalLayer` whose `NSView` Flutter has deallocated.
  static Future<void> dispose(int viewId) {
    return _channel.invokeMethod<void>('dispose', <String, Object?>{
      'viewId': viewId,
    });
  }

  /// Captures the app's own window twice and reports how much moved, inside the
  /// platform view and in the Flutter chrome above it.
  ///
  /// A spike affordance, and a conditional one. Capture entitlement follows the
  /// **responsible** process rather than the app, so the same bundle measures
  /// real motion when launched from a terminal that holds Screen Recording
  /// permission and returns a uniform white image when launched through
  /// LaunchServices. The native side detects the uniform case and reports it as
  /// an `error` key, because otherwise it reads as zero motion, which is
  /// indistinguishable from a video that is not playing.
  ///
  /// Pass [viewId] for the scoped numbers. Call it once before [play] as the
  /// control: with no core started nothing should move, and a video rect that
  /// moves anyway means the measurement is reading something other than mpv.
  static Future<Map<Object?, Object?>> captureSelf(
    String path, {
    int? viewId,
  }) async {
    final Map<Object?, Object?>? raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('captureSelf', <String, Object?>{
          'path': path,
          'viewId': viewId,
        });

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

/// One sample of the counters, arriving twice a second while a core is alive.
///
/// A tick rather than property observers, and that is measured rather than
/// chosen: mpv sends a change event only when a property changes, so a counter
/// that **freezes** is invisible to an observer, and a frozen counter is exactly
/// how a lapsed provider token presents. `core-idle` was the candidate fast path
/// and reads false through an entire lapse, flipping only after the file ends.
@immutable
class PlayerTick {
  /// mpv's `playlist_entry_id` for the load this sample belongs to.
  ///
  /// Compare it before acting: a ladder that reopens during a stall otherwise
  /// treats the previous variant's last samples as the new variant's first.
  final int session;

  /// mpv's own monotonic clock, in nanoseconds.
  ///
  /// A tick delayed because the platform thread was blocked looks identical to
  /// a stalled stream from here. This is what separates the two, so a late tick
  /// is reported as a plugin fault rather than folded into the ladder.
  final int monotonicNs;

  /// Playback position. Null when mpv has none, which includes before the first
  /// frame.
  final double? timePos;

  /// Whether the user paused. Every stall threshold is gated on this, because a
  /// paused stream stops advancing by design.
  final bool paused;

  /// mpv's `core-idle`. Measured useless as a stall signal and carried anyway,
  /// because it is the one flag that distinguishes "nothing loaded" from
  /// "loaded and stuck".
  final bool coreIdle;

  /// Bytes buffered ahead of the decoder.
  ///
  /// **Not a stall predicate.** On a healthy continuous stream it sits at a
  /// steady 80 KB rather than growing, so "not advancing" is its normal state.
  final int? forwardBytes;

  /// Input rate in bytes per second, mpv's `raw-input-rate`. The same number
  /// `cache-speed` reports.
  final int? inputRate;

  /// Whether the reader thread could not satisfy a decoder request.
  ///
  /// Null when mpv did not report it. Null means unknown, never healthy: the
  /// field sits under mpv's "might be changed or removed" heading, so a default
  /// of false would claim health the core never asserted.
  final bool? underrun;

  /// Whether the demuxer has stopped reading because the cache is full. A
  /// healthy satisfied cache sets this, so it explains a quiet stream rather
  /// than condemning one.
  final bool? demuxerIdle;

  const PlayerTick({
    required this.session,
    required this.monotonicNs,
    required this.timePos,
    required this.paused,
    required this.coreIdle,
    required this.forwardBytes,
    required this.inputRate,
    required this.underrun,
    required this.demuxerIdle,
  });

  factory PlayerTick.fromNative(Map<Object?, Object?> raw) {
    final Object? position = raw['timePos'];

    return PlayerTick(
      session: raw['session'] as int? ?? 0,
      monotonicNs: raw['monotonicNs'] as int? ?? 0,
      timePos: position is num ? position.toDouble() : null,
      paused: raw['paused'] == true,
      coreIdle: raw['coreIdle'] == true,
      forwardBytes: raw['forwardBytes'] as int?,
      inputRate: raw['inputRate'] as int?,
      underrun: raw['underrun'] as bool?,
      demuxerIdle: raw['demuxerIdle'] as bool?,
    );
  }
}

/// What mpv reported, over [WatchoolsPlayer.events].
@immutable
class PlayerEvent {
  /// One of `tick`, `endFile`, `videoReconfig`, `log` or `eventsLost`. A name
  /// the native side chose rather than an enum, because the set will grow with
  /// the variant ladder and an unknown name has to survive the trip.
  final String name;

  /// mpv's `playlist_entry_id` for the load this event belongs to, stamped on
  /// every event so a reader can tell which load it is about.
  final int session;

  /// The counters, present only on `tick`.
  final PlayerTick? tick;

  /// mpv's `end-file` reason, present only on `endFile`.
  ///
  /// **`0` is EOF, not an error**, and a lapsed provider token that does end
  /// playback ends it as exactly that, so a live stream reporting a clean end of
  /// file is reporting a fault. Absence of this event is not health: a lapsed
  /// token on an HLS playlist produces no `endFile` at all.
  final int? reason;

  /// mpv's `end-file` error code, present only on `endFile`. Zero when the end
  /// was not an error.
  final int? error;

  /// The log line, present only on `log`.
  final String? text;

  /// The log level (`warn`, `error`, `fatal`), present only on `log`.
  final String? level;

  const PlayerEvent({
    required this.name,
    required this.session,
    this.tick,
    this.reason,
    this.error,
    this.text,
    this.level,
  });

  factory PlayerEvent.fromNative(Map<Object?, Object?> raw) {
    final String name = raw['event'] as String? ?? 'unknown';

    return PlayerEvent(
      name: name,
      session: raw['session'] as int? ?? 0,
      tick: name == 'tick' ? PlayerTick.fromNative(raw) : null,
      reason: raw['reason'] as int?,
      error: raw['error'] as int?,
      text: raw['text'] as String?,
      level: raw['level'] as String?,
    );
  }

  /// Whether playback stopped, for any reason including a clean EOF.
  bool get isEnd => name == 'endFile';

  /// Whether mpv dropped events before this one reached us.
  ///
  /// A reader that has seen this cannot conclude anything from the absence of
  /// an event, which on this channel is how a fault presents.
  bool get isGap => name == 'eventsLost';
}

/// The surface mpv draws into.
///
/// Stateful only to own the platform view's identifier: Flutter mints it at
/// creation and the native side needs it back at teardown, so the widget that
/// owns the view is the only place with both halves.
///
/// Gestures do not reach Flutter's arena through a macOS platform view, so every
/// control belongs in Flutter above this widget rather than inside it. That is
/// where they want to be anyway, for one design across touch, mouse and D-pad.
class WatchoolsPlayerView extends StatefulWidget {
  /// Fires once, with the identifier [WatchoolsPlayer.play] needs.
  final ValueChanged<int>? onReady;

  const WatchoolsPlayerView({super.key, this.onReady});

  @override
  State<WatchoolsPlayerView> createState() => _WatchoolsPlayerViewState();
}

class _WatchoolsPlayerViewState extends State<WatchoolsPlayerView> {
  int? _viewId;

  @override
  void dispose() {
    final int? viewId = _viewId;
    if (viewId != null) {
      // Unawaited on purpose: `dispose` cannot await, and the native side has
      // to hear about the teardown even though this frame is already gone.
      WatchoolsPlayer.dispose(viewId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No hit-test behaviour is set, because there is nothing useful to set it
    // to: Flutter's gesture arena does not hand gestures to a macOS platform
    // view at all, so a tap here is the platform's business and every control
    // lives in Flutter above this widget.
    return AppKitView(
      viewType: 'watchools_player/view',
      onPlatformViewCreated: (int viewId) {
        _viewId = viewId;
        widget.onReady?.call(viewId);
      },
    );
  }
}
