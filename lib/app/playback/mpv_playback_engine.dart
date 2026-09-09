import 'dart:async';

import 'package:flutter/services.dart';
import 'package:magic/magic.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:watchools_player/watchools_player.dart';

import 'playback_engine.dart';

/// The [PlaybackEngine] over libmpv, through the `watchools_player` plugin.
///
/// macOS today, because that is the one target the plugin has a native half
/// for. Nothing above this class knows that: the six implementations coming
/// after it are selected behind the interface, and this one owns no policy the
/// others would have to copy.
///
/// ### Every line the native side says is redacted here
///
/// A stream URL carries the subscription password in its **path**, mpv is
/// subscribed to its own log at `warn`
/// (`MpvEngine.swift:127`) and its lines are forwarded verbatim (`:465`), and
/// FFmpeg's reconnect warning names the URL it is retrying. That channel is the
/// only signal a subscription token is lapsing, so it cannot be switched off;
/// it has to be cleaned instead, and this class is where.
///
/// Two properties make that a guarantee rather than a habit. Native text enters
/// this class at exactly **one** place, [_receive], and the redactor is the
/// first thing applied to it. And it leaves at exactly one place, a [Log] call:
/// **no member of [PlaybackEngine] carries text at all**, so a redacted line
/// has nowhere else to go. That is stronger than "redacted before forwarding",
/// and a later reader adding a text member to the interface would be the change
/// that weakens it.
///
/// The redactor arrives as a function rather than as an `XtreamCredentials`,
/// because a redactor is the one provider concept an engine may hold and a
/// provider is not. `XtreamCredentials.redact` is what the app passes; the
/// engine cannot tell.
///
/// ### One subscription upstream
///
/// `WatchoolsPlayer.events` is subscribed to once, in the constructor, and
/// fanned out from the broadcast controller this class owns.
/// `receiveBroadcastStream` sets one message handler per channel name
/// (`platform_channel.dart:697`), so a second subscriber silently steals the
/// stream from the first and either one's cancel tears down both. Two consumers
/// of an engine (a screen and, later, the variant ladder) are the ordinary
/// case, and they read [ticks], which has no such limit.
///
/// Eagerly, not on the first listener: [health] is answerable by a consumer
/// that reads it and never listens to [ticks], and a detector fed only while
/// somebody is watching would report a verdict about the ticks it happened to
/// see.
///
/// `captureSelf` is deliberately unreachable from here. It captures the app's
/// own window as a compositing proof, it is a spike affordance, and a product
/// surface has no business offering it.
class MpvPlaybackEngine implements PlaybackEngine {
  /// Turns any native text into something that can be written down.
  ///
  /// Takes prose rather than a `Uri`, because a log line has no URL boundary to
  /// find and a parser that guesses one wrong passes the secret through.
  final String Function(String) _redact;

  final StreamController<PlaybackTick> _ticks = StreamController<PlaybackTick>.broadcast();

  /// One detector for the engine's life rather than one per load.
  ///
  /// The grace is a user-exposed setting, and the detector resets its own
  /// anchor whenever the stamp changes, which [_generation] guarantees it does
  /// on every load.
  final StallDetector _detector = StallDetector();

  late final StreamSubscription<PlayerEvent> _upstream;

  PlaybackSurface? _surface;

  /// How many loads this engine has opened, which is the stamp it hands out.
  ///
  /// Its own counter, because the transport's cannot keep the interface's first
  /// promise. `PlayerTick.session` is mpv's `playlist_entry_id`, and
  /// `MpvEngine.start` calls `mpv_create` per load while refusing a second
  /// while a core is alive (`MpvEngine.swift:84`, `WatchoolsPlayerPlugin.swift:56`),
  /// so every load runs on a **fresh** core whose first entry id is 1 again.
  /// `MpvEventPump.session` is not reset by `stop()` either. The stamp
  /// therefore repeats rather than increases, and forwarding it would do worse
  /// than nothing: [StallDetector] resets on a stamp change, so a new channel
  /// starting at position 0 after one that reached 300 would read as a position
  /// that went backwards inside one session, which is a freeze verdict on a
  /// healthy stream.
  int _generation = 0;

  /// The generation of the load that is currently open, or null when none is.
  ///
  /// Null before the first [load], after [stop] and after [dispose], which is
  /// what makes a straggler unaccepted and [health] idle in all three. It is
  /// also the whole staleness rule here, and that is a genuine narrowing of the
  /// fake's two-rule check: the fake compares stamps because its ticks carry a
  /// stamp worth comparing, and this transport's does not. A tick arriving
  /// between a [load] and the [stop] that ends it is attributed to that load,
  /// so a straggler from the previous core that survives the load boundary is
  /// counted as the new load's first tick. Bounded rather than open: `stop()`
  /// detaches the sampler synchronously (`MpvEngine.swift:307`), so nothing new
  /// is sampled after [load] awaits it, and only a payload already handed to
  /// the main queue can still arrive.
  int? _loaded;

  /// The stamp the last accepted tick carried, or null before the first one.
  int? _session;

  /// Whether a tick of the **current** load has been read.
  ///
  /// Separate from [_session], which keeps the last stamp handed out even
  /// across a load. This one is what makes [health] idle between a load and its
  /// first tick: the detector's last verdict is about the stream just replaced.
  bool _reading = false;

  /// Toggles the display's sleep prevention. Production default is
  /// [WakelockPlus.toggle]; a test substitutes it to assert without a real
  /// display, since `wakelock_plus` exposes only static methods.
  ///
  /// An idle macOS display stops libmpv presenting and freezes `time-pos` at
  /// the first frame (`player-layer.md:585-590`: `underrun` false,
  /// `demuxerIdle` true, `fw-bytes` growing, recovers on wake), which reads
  /// exactly like a lapsed subscription token and was once filed as a code
  /// regression before being retracted. Held here rather than by the screen so
  /// it follows the core's lifetime, not a route's.
  final Future<void> Function({required bool enable}) _toggleWakelock;

  /// Whether this engine currently holds the wakelock.
  ///
  /// Boolean rather than a counter: `load` is `stop()`-then-`play()` on every
  /// call, including a second `load` with no intervening interface-level
  /// `stop`, so an unconditional enable on every `load` would ask the platform
  /// to hold twice without ever asking it to release twice. Gating on this
  /// flag makes a second hold structurally impossible rather than merely
  /// untested, and it is what [stop] and [dispose] check before releasing, so
  /// neither one ever asks for a release nothing granted.
  bool _awake = false;

  /// Takes the redactor under its public name, `redact:`, which is what a
  /// private initializing formal is spelled as at a call site. `toggleWakelock`
  /// follows the same shape, defaulting to the real plugin.
  MpvPlaybackEngine({required this._redact, this._toggleWakelock = WakelockPlus.toggle}) {
    _upstream = WatchoolsPlayer.events.listen(_receive);
  }

  @override
  Stream<PlaybackTick> get ticks => _ticks.stream;

  @override
  int? get session => _session;

  @override
  PlaybackHealth get health => _reading ? _detector.health : PlaybackHealth.idle;

  /// Keeps the surface. Nothing crosses to the platform.
  ///
  /// The one place the interface and the transport disagree in shape: the
  /// plugin takes the view identifier in `play(int viewId, String url)` and in
  /// `dispose(int viewId)` rather than once, so the identifier is held here and
  /// reaches the platform at [load]. An engine's surface does not change, so
  /// there is nothing for a second call to reconcile.
  @override
  Future<void> attach(PlaybackSurface surface) {
    _surface = surface;

    return Future<void>.value();
  }

  /// Throws [StateError] when no surface has been attached.
  ///
  /// Structural rather than a policy: `play` needs a view identifier and
  /// without a surface there is none to send, so the alternative is a call the
  /// native side rejects with `no-view` after the round trip. The failure it
  /// prevents is silent on a real platform, where an engine with no surface
  /// opens the stream, advances its counters and reports health while rendering
  /// into nothing.
  @override
  Future<void> load(Uri source, {String? userAgent}) async {
    final PlaybackSurface? surface = _surface;

    if (surface == null) {
      throw StateError('MpvPlaybackEngine: attach a surface before load; play takes a view id in every call.');
    }

    // 1. `MpvEngine.start` refuses while a core is alive, so a channel change
    //    has to close the previous one first. Unconditional rather than only
    //    when this engine opened it: a hot restart leaves the native plugin,
    //    its factory and its running core standing while the Dart side starts
    //    over, and a core this object never opened refuses `play` just the
    //    same. With no core it is a no-op.
    await WatchoolsPlayer.stop();

    // 2. Before the platform call, so the first ticks of the new core are
    //    attributed rather than dropped: the sampler starts inside `start`.
    _loaded = ++_generation;
    _reading = false;

    // 3. The only call that hands the secret to the native side, so it is the
    //    only one whose failure could hand it back. Nothing in the plugin's
    //    messages names the URL today; this is what keeps that true when
    //    somebody adds `"could not open \(url)"`. `details` is dropped rather
    //    than forwarded because it is not text and cannot be cleaned, and the
    //    native side sends none.
    try {
      await WatchoolsPlayer.play(surface.platformViewId, source.toString(), userAgent: userAgent);

      // 4. Only once play has actually succeeded: a failed load leaves no core
      //    alive, and enabling here first would hold the display awake for a
      //    stream that never opened, with nothing left to release it.
      if (!_awake) {
        _awake = true;
        await _toggleWakelock(enable: true);
      }
    } on PlatformException catch (failure) {
      _loaded = null;

      final String? message = failure.message;

      throw PlatformException(code: failure.code, message: message == null ? null : _redact(message));
    }
  }

  /// Writes mpv's `pause` flag.
  ///
  /// [pause] and [resume] are one native call with two arguments rather than
  /// two calls, so there is no second method to look for. Neither moves
  /// [health]: the tick that comes back carrying `paused` is what does that,
  /// which is how mpv behaves and therefore what every consumer must be written
  /// against.
  @override
  Future<void> pause() => WatchoolsPlayer.setPaused(true);

  @override
  Future<void> resume() => WatchoolsPlayer.setPaused(false);

  /// Closes the session and releases the provider connection.
  ///
  /// The local state goes first, so a tick sampled before the core heard about
  /// this is dropped rather than reported against a session that is over. The
  /// wakelock release is guarded by [_awake] rather than unconditional: a
  /// `stop` on an engine that never opened a core, or that already released
  /// one, must not ask the platform for a release it never granted.
  @override
  Future<void> stop() async {
    _loaded = null;
    _reading = false;

    if (_awake) {
      _awake = false;
      await _toggleWakelock(enable: false);
    }

    await WatchoolsPlayer.stop();
  }

  /// Tears the engine down from Dart, on nothing the native side says.
  ///
  /// There is no native teardown signal to wait for: `AppKitView` disposal is
  /// deferred to the next compositor present and the platform view has no
  /// "about to dispose" hook, so an engine that waited would keep a core
  /// rendering into a layer whose view is gone.
  ///
  /// The order is the whole of it. The subscription is cancelled before the
  /// controller closes, because an event arriving at a closed controller throws
  /// rather than being ignored. Cancelling does not disturb another reader: the
  /// broadcast controller behind `receiveBroadcastStream` only runs its
  /// `onCancel`, which is what nulls the shared message handler, when its last
  /// listener leaves, and a later listener re-installs it. The core is stopped
  /// even though the view's own widget also calls `WatchoolsPlayer.dispose`,
  /// because the measured connection budget on a real subscription is one and
  /// this object may outlive that widget by a frame.
  ///
  /// `WatchoolsPlayer.dispose(viewId)` is deliberately not called from here:
  /// the view is the widget's to forget, and pruning it under a widget that
  /// still owns it would leave the next `play` with no view to render into.
  ///
  /// The wakelock release sits with the other local state, ahead of the
  /// cancel/stop/close sequence above: it does not depend on the upstream
  /// subscription or the controller, so it is guarded by [_awake] and released
  /// as early as the rest of the local bookkeeping rather than reordering
  /// anything that sequence relies on.
  @override
  Future<void> dispose() async {
    _loaded = null;
    _reading = false;

    if (_awake) {
      _awake = false;
      await _toggleWakelock(enable: false);
    }

    await _upstream.cancel();
    await WatchoolsPlayer.stop();
    await _ticks.close();
  }

  /// The one door native text comes through.
  ///
  /// A tick goes to [_read]. Anything carrying text is redacted here, in the
  /// first expression that touches it, and written to the log; that covers
  /// today's `log` event and whatever later event carries a line, because the
  /// branch is keyed on the text rather than on the event name.
  ///
  /// `endFile` and `eventsLost` are read and dropped, which is deliberate
  /// rather than forgotten: a clean EOF on a live stream is a fault and a
  /// dropped-event gap invalidates any conclusion drawn from silence, but
  /// [PlaybackEngine] has no member that can carry either, and inventing one
  /// belongs with the fault classification the protocol layer already models.
  void _receive(PlayerEvent event) {
    final PlaybackTick? tick = event.tick;

    if (tick != null) {
      _read(tick);

      return;
    }

    final String? text = event.text;

    if (text == null) return;

    final String line = 'mpv: ${_redact(text)}';

    // Mapped rather than passed through. mpv spells its levels `fatal`,
    // `error` and `warn`, and the Log facade's console driver scores an
    // unknown level as debug (`console_logger_driver.dart:41`), so forwarding
    // mpv's own spelling would file every reconnect warning below the
    // threshold a release build prints.
    if (event.level == 'error' || event.level == 'fatal') {
      Log.error(line);

      return;
    }

    Log.warning(line);
  }

  /// Accepts one tick against the load that is open, or drops it.
  void _read(PlaybackTick tick) {
    final int? generation = _loaded;

    if (generation == null) return;

    final PlaybackTick stamped = _restamped(tick, generation);

    _session = generation;
    _reading = true;
    _detector.read(stamped);
    _ticks.add(stamped);
  }

  /// [tick] with this engine's stamp in place of the transport's.
  ///
  /// A field-for-field copy, which is exactly what [PlaybackTick] being an
  /// alias was chosen to avoid, and it is here because the alternative is
  /// worse: see [_generation] for what the transport's stamp actually does.
  /// The failure mode that decision named (a dropped field reads as unknown,
  /// and unknown is never healthy) is closed two ways rather than trusted:
  /// every parameter of `PlayerTick` is required, so a field added there breaks
  /// this call site at compile time, and a test asserts all nine survive.
  PlaybackTick _restamped(PlaybackTick tick, int session) => PlaybackTick(
    session: session,
    monotonicNs: tick.monotonicNs,
    timePos: tick.timePos,
    paused: tick.paused,
    coreIdle: tick.coreIdle,
    forwardBytes: tick.forwardBytes,
    inputRate: tick.inputRate,
    underrun: tick.underrun,
    demuxerIdle: tick.demuxerIdle,
  );
}
