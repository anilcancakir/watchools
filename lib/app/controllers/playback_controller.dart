import 'dart:async';

import 'package:magic/magic.dart';
import 'package:watchools_player/watchools_player.dart';

import '../models/channel.dart';
import '../models/provider_fault.dart';
import '../playback/playback_engine.dart';
import '../provider/provider_session.dart';

/// What a screen reads of playback, and nothing more.
///
/// A narrow interface beside the controller rather than the controller itself,
/// so a widget test drives the playback screen with no container, no provider
/// session and no panel behind it. `PlaybackController` implements it and is
/// what the app binds; a test passes a hand-written double.
///
/// Note what is absent, because the absence is the design: there is **no URL
/// on this contract and there must never be one**. A stream URL carries the
/// subscription password in its path, so a screen that could read one is a
/// screen that could put it in a semantics label, and a semantics label is
/// exactly what an accessibility tree and a dusk snapshot print.
abstract interface class PlaybackFacade {
  /// The channel being watched, or null when nothing is.
  Channel? get channel;

  /// What the counters say right now.
  PlaybackHealth get health;

  /// Why the provider is not delivering, or null when it is.
  ProviderFault? get fault;

  /// Whether the last attempt found no URL for its channel.
  bool get unplayable;

  /// Pauses when playing, resumes when paused.
  Future<void> togglePause();

  /// Ends playback and releases the provider connection.
  Future<void> stop();

  /// Hands the engine the surface it renders into, and opens whatever is
  /// waiting for one.
  Future<void> attach(PlaybackSurface surface);

  /// Reports that the surface handed over by [attach] is going away.
  Future<void> detach();

  /// Opens [channel], or holds it until a surface arrives.
  Future<void> play(Channel channel);

  /// Re-opens the channel already chosen, which is what a fault's retry means.
  Future<void> retry();
}

/// What a screen asks to start, hold and end playback of one channel.
///
/// The object between a tap and the engine. Everything above it talks to this
/// controller, everything below it to [PlaybackEngine], and neither end knows
/// the other exists.
///
/// ### It never sees the credential
///
/// The URL a stream needs carries the subscription password in its **path**,
/// and this controller asks [ProviderSession.streamUrlFor] for a finished
/// [Uri] rather than deriving one. So it imports no `XtreamStreamUrl`, no
/// `XtreamCredentials` and no `XtreamAccount`, holds the `Uri` only as a local
/// while it hands it to the engine, and never turns one into a `String`. That
/// is the whole of its claim to being low risk: the secret passes through
/// opaquely and there is no member a screen could read it from.
///
/// ### It repaints on a verdict, not on a tick
///
/// A tick arrives about twice a second. Notifying per tick would repaint the
/// overlay 120 times a minute for a picture that did not change, so
/// [refreshUI] fires only when [PlaybackHealth] actually moves. The tick's
/// other fields are the detector's business and no screen binds to them.
///
/// ### The surface comes from the widget, not from here
///
/// [PlaybackEngine.attach] needs the identifier Flutter minted for the platform
/// view, and only the widget owning that view can supply it. So [attach] is
/// this controller's own seam for the screen to call from
/// `onPlatformViewCreated`, and [play] before it is a programming error rather
/// than a state to handle: the engine would open the stream, advance its
/// counters and report health while rendering into nothing, which is silent on
/// a real platform.
class PlaybackController extends SimpleMagicController implements PlaybackFacade {
  // No `static get instance` here, unlike the other two controllers, and the
  // absence is structural rather than an omission: `Magic.findOrPut` needs a
  // zero-argument constructor and this one requires its engine, which is the
  // point. `AppServiceProvider.register()` binds the single instance with the
  // real engine, and a view resolves it with `Magic.find<PlaybackController>()`
  // like any other. A zero-argument accessor would have to build an engine,
  // which is how a test ends up driving a platform that is not there.

  /// Builds the engine this controller drives, on first use.
  ///
  /// A factory rather than an instance, and the indirection is load-bearing
  /// rather than taste. `MpvPlaybackEngine`'s constructor subscribes to the
  /// plugin's `EventChannel`, which reaches `ServicesBinding.instance`, so
  /// constructing one during `AppServiceProvider.register()` makes **every**
  /// test that boots the providers throw `Binding has not yet been
  /// initialized`. Measured: it broke the provider driver's own security test,
  /// which has no widget binding and no reason to want one. Deferring the build
  /// to first use puts the platform contact where a platform exists.
  ///
  /// A test passes `() => FakePlaybackEngine()`, which needs no platform at
  /// all, and is a first-class deliverable for exactly that reason.
  final PlaybackEngine Function() _engineFactory;

  PlaybackEngine? _resolvedEngine;

  /// The provider handle passed in, or null to resolve one from the container.
  /// Follows `GuideController`'s shape: pass one in a test, leave it null in
  /// the app.
  final ProviderSession? _sessionOverride;

  StreamSubscription<PlaybackTick>? _ticks;

  Channel? _channel;

  /// The verdict the last repaint was about.
  ///
  /// Not a copy of the current health: [health] reads the engine directly, and
  /// this is only the value a new tick is compared against to decide whether
  /// anything visible moved. A cached copy would go stale between the engine
  /// accepting a tick and the broadcast stream delivering it, which is a
  /// microtask later, and every reader in between would see the old verdict.
  PlaybackHealth _notified = PlaybackHealth.idle;

  bool _unplayable = false;

  /// Whether a surface has been handed over.
  ///
  /// Tracked here rather than asked of the engine, because the interface has no
  /// member for it and adding one would put a question on a six-implementation
  /// contract that only this controller's own ordering needs.
  bool _attached = false;

  /// A channel chosen before a surface existed, waiting for one.
  ///
  /// The line-up taps `play` and then pushes the route, so the platform view
  /// that mints the surface is one frame away when the choice is made. Holding
  /// the channel is what makes the engine's attach-before-load rule true by
  /// construction rather than by whoever calls in the right order.
  Channel? _pending;

  /// Creates the controller over [engine].
  ///
  /// [session] is what [play] asks for a URL and what [fault] reads; pass one
  /// in a test, leave it null in the app.
  PlaybackController({required PlaybackEngine Function() engine, ProviderSession? session})
    : _engineFactory = engine,
      _sessionOverride = session {
    _session.addListener(_onSessionChanged);
  }

  ProviderSession get _session => _sessionOverride ?? Magic.findOrPut(ProviderSession.new);

  /// The engine, built and subscribed to on first ask.
  ///
  /// The tick subscription is taken here rather than in the constructor for the
  /// same reason the engine is: `ticks` on the real implementation is a
  /// platform channel, and a controller bound at `register()` must not touch
  /// one. Taken once, because a second `listen` on the plugin's own broadcast
  /// stream silently steals it from the first.
  PlaybackEngine get _engine {
    final PlaybackEngine? resolved = _resolvedEngine;

    if (resolved != null) return resolved;

    final PlaybackEngine engine = _engineFactory();

    _resolvedEngine = engine;
    _ticks = engine.ticks.listen(_onTick);

    return engine;
  }

  /// The channel being watched, or null when nothing is.
  @override
  Channel? get channel => _channel;

  /// What the counters say right now, straight from the engine's detector.
  ///
  /// Six members rather than a boolean, and three of them are measured shapes a
  /// naive reading collapses into one: `starving` is a live window's normal
  /// wait, `stalled` is a freeze that outlasted the grace, and `notPresenting`
  /// is an asleep display, which recovers on wake and which no production
  /// player models at all. A screen that folds any of them together tells the
  /// user the wrong thing.
  ///
  /// Read through to the engine rather than cached. The engine settles its
  /// verdict when it accepts a tick, but the tick reaches this controller's
  /// subscription a microtask later, so a cached copy is wrong for exactly as
  /// long as it takes the broadcast stream to deliver.
  ///
  /// Reads the engine only if one has been built. `idle` is the honest answer
  /// before then, and asking [_engine] here would make a getter subscribe to a
  /// platform channel, which is the side effect this controller's own Must NOT
  /// forbids.
  @override
  PlaybackHealth get health => _resolvedEngine?.health ?? PlaybackHealth.idle;

  /// Whether the last [play] found no URL for its channel.
  ///
  /// One flag for all four of [ProviderSession.streamUrlFor]'s null cases, and
  /// that is deliberate: none of them is a fault, and a screen can say only one
  /// true thing about them, which is that this channel cannot be played from
  /// what the app currently knows. A genuine fault arrives through [fault]
  /// instead, with the vocabulary the notice already renders.
  @override
  bool get unplayable => _unplayable;

  /// Why the provider is not delivering, or null when it is.
  ///
  /// The session's own verdict rather than a second vocabulary. `evicted` is
  /// the member this surface needs most: it is what a `max_connections: 1`
  /// account produces when another device takes the slot, and the only fault
  /// whose retry costs that other device its stream.
  @override
  ProviderFault? get fault => _session.fault;

  /// Whether this controller is holding one of the account's connection slots.
  ///
  /// A member rather than a closure in the composition root, and that is the
  /// correction rather than a preference. `AppServiceProvider` hands this to
  /// [ProviderSession] as its playback gate, and `lib/app/providers/` is
  /// outside the CI coverage denominator, so while the logic lived there it was
  /// asserted only by two hand copies in a test file, which had **drifted apart
  /// from each other and from the original**. Deleting a clause of the real one
  /// turned nothing red. Now there is one expression and the test reads it.
  ///
  /// Three clauses, each closing a hole the others leave.
  ///
  /// `health != idle` covers the four states a naive `== playing` would miss: a
  /// paused, starving, stalled or not-presenting core is still an open core
  /// holding the slot.
  ///
  /// `channel != null` closes the window before the first tick. [health]
  /// reports `idle` from the [play] call until one arrives, and [StallDetector]
  /// extends that to every tick before the first decoded frame, so a core that
  /// is still connecting reads "not playing" while holding the slot.
  ///
  /// `!unplayable` is what stops the second clause over-reaching. [play] keeps
  /// the channel through a refusal so the screen can name what it will not
  /// play, and without this the gate would then report a held connection for a
  /// channel that never opened a core: no URL was derived, nothing was sent,
  /// and yet every catalogue refresh would be refused until the route popped.
  ///
  /// Over-reporting costs a skipped refresh, which the next one fixes.
  /// Under-reporting costs the viewer their stream, on an account whose
  /// measured `max_connections` is 1.
  bool get holdsConnection => (_channel != null && !_unplayable) || health != PlaybackHealth.idle;

  /// Hands the engine the surface it renders into, once.
  ///
  /// Called by the widget that owns the platform view, from
  /// `onPlatformViewCreated`: the identifier is minted synchronously but is
  /// only valid to pass on after that callback has fired.
  /// Also opens whatever was chosen before a surface existed, which is the
  /// ordinary path: the line-up calls [play] and then pushes the route.
  @override
  Future<void> attach(PlaybackSurface surface) async {
    await _engine.attach(surface);

    _attached = true;

    final Channel? pending = _pending;

    if (pending == null) return;

    _pending = null;

    await play(pending);
  }

  /// Reports that the surface is going away, and ends the session with it.
  ///
  /// Called from the screen's `dispose`, which is the only moment Dart hears
  /// about this at all. The native side prunes the view on its own
  /// (`WatchoolsPlayerPlugin.swift:186-191`) and **stops the core** when the
  /// pruned view is the attached one, so a route pop kills playback whether or
  /// not anybody asked. Without this, three things follow from that silence,
  /// all of them measured against the Swift rather than guessed:
  ///
  /// 1. [_attached] would stay true against a forgotten view id, so the second
  ///    visit to the screen would take [play]'s open-now branch, send the dead
  ///    id and get `no-view` back, having set no [_pending] for the new
  ///    surface to consume. A black screen with no fault, on every visit after
  ///    the first.
  /// 2. [_channel] would stay set forever, and it is half of the closure
  ///    `AppServiceProvider` gives [ProviderSession] as its playback gate. The
  ///    gate would latch closed and no catalogue refresh would ever run again,
  ///    because [onClose] is the only other thing that clears it and a bound
  ///    controller is never closed in this app.
  /// 3. The engine's wakelock is Dart-side state, so a core the native layer
  ///    stopped by itself would leave the display held awake indefinitely.
  ///
  /// No [refreshUI] here, deliberately: this runs from a `dispose`, and
  /// notifying a widget that is being torn down is a `setState` after dispose.
  @override
  Future<void> detach() async {
    _attached = false;
    _pending = null;
    _channel = null;
    _unplayable = false;
    _notified = PlaybackHealth.idle;

    // Only a core that exists. `_engine` would BUILD one, which on the real
    // implementation means subscribing to a platform channel during teardown.
    await _resolvedEngine?.stop();
  }

  /// Opens [channel], replacing whatever was playing.
  ///
  /// Reports rather than throws when no URL can be derived, because a
  /// fixture-built channel has no `streamId` by design and the screen has to be
  /// able to say so. The report is cleared by the next channel that does work,
  /// so a user who picks a bad one and then a good one is not left looking at a
  /// stale message.
  @override
  Future<void> play(Channel channel) async {
    final Uri? source = _session.streamUrlFor(channel);

    if (source == null) {
      // The channel is kept rather than cleared, so the screen can name what
      // it is refusing. Clearing it made the report read "this channel cannot
      // be played" with no channel on screen to attach that to, and left
      // [retry] with nothing to re-open either.
      _channel = channel;
      _pending = null;
      _unplayable = true;
      refreshUI();

      return;
    }

    _channel = channel;
    _unplayable = false;
    // Reset with the rest, because the verdict this holds is about the stream
    // being replaced. The load takes [health] back to `idle`, so a stale
    // `_notified` makes [_onTick] compare the new stream's first verdict
    // against the old stream's and skip the repaint when they match. Nothing
    // is visibly wrong today only because `StallDetector` never returns
    // `starving` or `stalled` on the first tick of a stamp, which is a
    // property of another package's class rather than of this one: the day it
    // does, a retry that lands in the state it replaced would repaint nothing
    // and the buffering line would silently never appear.
    _notified = PlaybackHealth.idle;

    // Held rather than opened when no surface exists yet, and this ordering is
    // the whole reason the field is here. A tap on the line-up calls `play`
    // and THEN pushes the route, so the platform view that mints the surface
    // does not exist at this point: opening now would throw
    // `StateError: attach a surface before load` into a future nobody awaits,
    // and the user would see a black screen with no fault at all. The screen's
    // `attach` is what consumes this.
    if (!_attached) {
      _pending = channel;
      refreshUI();

      return;
    }

    _pending = null;

    await _engine.load(source, userAgent: _session.playbackUserAgent);

    refreshUI();
  }

  /// Re-opens the channel already chosen.
  ///
  /// What a fault's retry means on this surface: `ProviderNotice.onRetry` is
  /// "make the request again", and for `unreachable` or `evicted` the request
  /// to make again is the load. Toggling the pause of a core that never opened
  /// is not a retry, which is what this method exists to stop the screen from
  /// doing.
  @override
  Future<void> retry() async {
    final Channel? channel = _channel ?? _pending;

    if (channel == null) return;

    await play(channel);
  }

  /// Pauses when playing and resumes when paused.
  ///
  /// Reads the engine's verdict rather than a flag of its own, so a pause the
  /// user triggered on the remote and a pause the app triggered agree. Neither
  /// direction moves [health] by itself: the tick that comes back carrying
  /// `paused` is what does that, which is how mpv behaves and therefore what
  /// this controller must be written against.
  ///
  /// Reads [_resolvedEngine] rather than [_engine], so a control tapped before
  /// anything played does not BUILD an engine to send a command no core can
  /// answer. On the real implementation that construction subscribes to a
  /// platform channel, which is the side effect [detach] and [onClose] already
  /// avoid the same way.
  @override
  Future<void> togglePause() async {
    final PlaybackEngine? engine = _resolvedEngine;

    if (engine == null) return;

    await (health == PlaybackHealth.paused ? engine.resume() : engine.pause());
  }

  /// Ends playback and releases the provider connection.
  ///
  /// Its own command rather than a side effect of leaving the screen, because
  /// the measured connection budget on a real subscription is **one**: a
  /// session left open is the reason the next device in the house cannot watch.
  @override
  Future<void> stop() async {
    _channel = null;
    // Cleared with the rest, because a stop is the user saying they are done
    // with this channel. Leaving it would make the next `attach` open a stream
    // nobody asked for: the back affordance stops and then pops, and the pop
    // is what disposes the view whose replacement mints the next surface.
    _pending = null;
    _notified = PlaybackHealth.idle;
    _unplayable = false;

    await _engine.stop();

    refreshUI();
  }

  /// Reads one tick, and repaints only if the verdict moved.
  ///
  /// The tick itself is unread on purpose: its nine counters are the detector's
  /// input, and the engine's own [PlaybackEngine.health] is the only conclusion
  /// this controller is entitled to draw from them. Reading a field here would
  /// be a second, worse detector.
  void _onTick(PlaybackTick _) {
    final PlaybackHealth verdict = _engine.health;

    if (verdict == _notified) return;

    _notified = verdict;
    refreshUI();
  }

  /// Repaints when the session's fault moves, which is the half of this
  /// controller's state it does not own.
  void _onSessionChanged() => refreshUI();

  @override
  void onClose() {
    _ticks?.cancel();
    _ticks = null;
    _session.removeListener(_onSessionChanged);

    // Stops the core rather than leaving it to the screen's disposal, because
    // there is no native teardown signal to wait for and the connection budget
    // is one. Only a core that exists: `_engine` would BUILD one here, which on
    // the real implementation means subscribing to a platform channel during
    // teardown to immediately stop something that never started.
    _resolvedEngine?.stop();
    _channel = null;
    _notified = PlaybackHealth.idle;

    super.onClose();
  }
}
