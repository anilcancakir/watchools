import 'package:flutter/foundation.dart';
import 'package:watchools_player/watchools_player.dart';

/// One sample of the counters, under the name the app's interface uses.
///
/// An alias rather than a class of its own, and that is a decision with a cost
/// worth writing down. A parallel class would have the same nine fields, because
/// [StallDetector] is the shared policy across all six engines and those nine
/// fields are exactly what it reads, so the parallel class would be a copy of
/// [PlayerTick] plus two mappings: one at the plugin edge to build it and one
/// back to feed the detector. Both mappings are field-for-field copies, and a
/// field dropped in either does not fail loudly: `underrun` null means unknown
/// and never healthy (`watchools_player.dart:227`), so a forgotten field
/// degrades into a fault verdict on a healthy stream.
///
/// The cost is that the plugin's type is this interface's type: a field added
/// to [PlayerTick] is a field added here. The day a second implementation
/// cannot fill one of the nine, this alias becomes a class and the mapping is
/// written once, in the implementations, rather than being carried by all of
/// them from the start.
///
/// `timePos` on this type is a **liveness signal**, not a playback offset. The
/// only question ever asked of it is whether it advanced since the last tick,
/// [StallDetector] is its only reader, and no screen binds to it: see the
/// absences on [PlaybackEngine].
typedef PlaybackTick = PlayerTick;

/// The thing an engine draws into, handed over once.
///
/// A wrapper around one integer, which is worth a type for a reason that is not
/// tidiness: the identifier is the only rendering handle that exists today, and
/// three are coming. A platform view has an identifier Flutter minted, an FFI
/// engine has a render callback plus a texture the framework registered, and
/// hls.js has a DOM element. All three are things the framework provides and
/// hands over once, so [PlaybackEngine.attach]'s signature can survive all
/// three; `attach(int)` could not, and every consumer holding the call would
/// have to be rewritten to add the second.
///
/// One field and no subclasses, because one rendering model exists. The other
/// two cannot be typed honestly from here, and the day the second arrives this
/// becomes a sealed hierarchy without touching the interface.
@immutable
class PlaybackSurface {
  /// The identifier Flutter minted for the platform view.
  ///
  /// Minted synchronously ahead of the native view existing, and only valid to
  /// pass on after `onPlatformViewCreated` has fired
  /// (`platform_views.dart:851-943`), which is why the widget owning the view is
  /// the only place a surface can be built.
  final int platformViewId;

  const PlaybackSurface({required this.platformViewId});

  @override
  bool operator ==(Object other) => other is PlaybackSurface && other.platformViewId == platformViewId;

  @override
  int get hashCode => platformViewId.hashCode;

  @override
  String toString() => 'PlaybackSurface(platformViewId: $platformViewId)';
}

/// Everything a screen may ask of playback.
///
/// One interface from the first playback screen, per `CLAUDE.md`: six
/// implementations are coming (Media3, AVPlayer, media_kit, hls.js, Tizen
/// AVPlay, tvOS) and three of them cannot be prototyped on this machine, so
/// anything left implicit here is a divergence waiting to happen. The contract
/// is therefore written down rather than demonstrated by the one implementation
/// that exists.
///
/// `abstract interface class` rather than `plugin_platform_interface`'s
/// `extends`-plus-token pattern. Both are defensible; this one is chosen
/// because an implementer who `implements` an interface **breaks loudly** when a
/// member is added, and for a contract whose absences are load-bearing that is
/// the direction that cannot rot: an inherited default would let an engine
/// silently answer a question it has no answer for. The package's own README
/// also records that the Flutter team is weighing its deprecation in favour of
/// Dart 3's class modifiers, which is what this uses.
///
/// ### What an implementation has to promise
///
/// 1. Every tick carries a session stamp, and the stamp **increases with each
///    [load]**. A transport that cannot promise that stamps its own counter.
/// 2. A tick stamped with a session below the current one is dropped: it
///    reaches neither [ticks] nor [health].
/// 3. [ticks] is a broadcast stream. Two readers are the ordinary case (a
///    screen and, later, the variant ladder), and on a method-channel transport
///    a second `receiveBroadcastStream` call silently steals the stream from the
///    first (`watchools_player.dart:46-58`).
/// 4. [health] comes from a [StallDetector] the implementation owns and feeds
///    every accepted tick. The policy is not the native side's: the grace is a
///    user-exposed setting, the same verdicts have to hold across six engines,
///    and CI builds no native target.
/// 5. [attach] happens before [load]. An engine with no surface renders into
///    nothing, which on a real platform is silent.
/// 6. **No member carries raw text.** See [load].
/// 7. [stop] and [dispose] are **idempotent, and safe to call after the surface
///    is gone.** This is the promise the consumer above actually relies on and
///    the one an implementer is most likely to break, because the platform can
///    tear the core down without saying so: `WatchoolsPlayerPlugin.swift:186-191`
///    stops the core when it prunes the attached platform view, and Dart hears
///    nothing, so `PlaybackController.detach` stops an engine that may already
///    be stopped. On mpv that happens to work, because `MpvEngine.swift:195-196`
///    opens with `guard let handle = mpv else { return }`. That is an
///    implementation property rather than a contract, and `ExoPlayer` after
///    `release()` is the counter-example, so it is written here instead of
///    inherited from what mpv happens to tolerate.
///
/// ### Three members this interface will never have
///
/// Their absence is the design, so an implementer who reads this looking for
/// the obvious omission finds the reason here instead of adding it back.
///
/// - **No scrub.** A live window slides: a provider serves the last few
///   segments it advertises, so a request to move inside the window is one the
///   window cannot honour, and one that lands outside it opens a fresh request
///   against a token that may already have lapsed.
/// - **No total length.** Live TV has none. A member returning null on every
///   live channel is a null every caller must handle and no caller can act on,
///   which is `video_player`'s shape (its length is required and non-nullable)
///   and the reason that shape assumes VOD.
/// - **No playback offset.** The progress a screen draws comes from
///   `GuideClock` plus `Programme` (`lib/app/support/guide_clock.dart`), in
///   minutes since the schedule's midnight, never from the engine. A member
///   named for a position invites a scrubber to bind to it, and the window
///   cannot satisfy a scrubber.
///
/// A live offset is a fourth candidate, deliberately not here yet: the only
/// precedent in four reference players is ExoPlayer's `getCurrentLiveOffset()`
/// with a `TIME_UNSET` sentinel, no Dart player has one, and nothing in the app
/// asks the question. It arrives with the caller that needs it.
///
/// ### The caller that will ask for an offset, and the shape to give it
///
/// One is already on screen. `showcase_layout.dart:98` renders an
/// `İzlemeye devam et` rail off `TitleItem.progress`, and
/// `ProviderSession.setTitleProgress` (`provider_session.dart:392`) has **no
/// caller anywhere in `lib/`**: the only thing that can ever write it is a VOD
/// session reading its own offset. So resume is unwired rather than deferred,
/// and it is the concrete demand for the third absence above.
///
/// When it lands, the shape is a **separate capability interface** that a
/// VOD-capable engine also implements, not nullable members added here. The
/// difference is the whole reason this contract is `abstract interface class`:
/// nullable members would make every live-only engine answer a question it has
/// no answer for, and answer it with a null that reads as "unknown", which is
/// never healthy. A second interface makes a live-only engine simply not
/// implement it, and makes a screen that needs a scrubber say so in its own
/// type.
///
/// Catch-up is a different case and genuinely deferred: `tv_archive` is set on
/// 20 of 2,976 channels on the measured account (`channel.dart:78-81`), so it
/// is carried and unused rather than unwired.
abstract interface class PlaybackEngine {
  /// Takes the surface this engine renders into, for its whole life.
  ///
  /// Once rather than per command. The plugin's `play(int viewId, String url)`
  /// puts view identity in every call, which a platform view can answer and an
  /// FFI engine with a render callback cannot, and hls.js cannot either. Every
  /// one of the three draws into something the framework provides and hands over
  /// once, so this is the shape all three fit.
  ///
  /// A [Future] because every implementation crosses to a platform here: the
  /// native side has to hear which surface before a load can present into it.
  Future<void> attach(PlaybackSurface surface);

  /// Opens [source], replacing whatever was playing.
  ///
  /// Replacing rather than queueing: the app's recovery from a lapsed provider
  /// token is a fresh open (no reconnect option survives one), and a channel
  /// change is the same call, so a queue would only ever hold something the
  /// user has already navigated away from.
  ///
  /// [source] is a [Uri] and nothing more. This interface knows no provider, no
  /// channel and no URL shape; deriving one is the protocol layer's job.
  ///
  /// [userAgent] is per provider rather than per app, because resellers key
  /// access control to it. Normalise the header name to exactly `User-Agent` in
  /// whatever builds it: ExoPlayer's lookup is case sensitive and a lowercase
  /// key silently ships its own.
  ///
  /// **Nothing here or anywhere on this interface returns text.** [source]
  /// carries the user's subscription password in its path and mpv forwards its
  /// own log lines verbatim, so a `String` member on a contract with six
  /// implementations and every screen as a consumer is a credential leak
  /// reachable from all of them. A fault that has to be surfaced is surfaced as
  /// a classified value; redaction for the diagnostics that do need a URL lives
  /// with the credential that owns the secret.
  Future<void> load(Uri source, {String? userAgent});

  /// Holds the picture where it is, without closing the connection.
  ///
  /// Nothing about this verdict is inferred: the engine reports [PlaybackHealth]
  /// from the ticks that follow, and a paused live stream stops advancing by
  /// design, which is what every freeze threshold is gated on.
  Future<void> pause();

  /// Resumes from wherever the provider is now, which on a live stream is not
  /// where [pause] left off.
  Future<void> resume();

  /// Closes the session and releases the provider connection.
  ///
  /// Its own command rather than a side effect of leaving a screen, because the
  /// measured connection budget on a real subscription is **one**: a session
  /// left open is the reason the next device in the house cannot watch.
  Future<void> stop();

  /// Tears the engine down for good and closes [ticks].
  ///
  /// Takes no surface, unlike the plugin's `dispose(int viewId)`. An engine
  /// holds exactly one surface from [attach], so passing it back would let a
  /// caller name a surface this engine never had.
  Future<void> dispose();

  /// The counters, as they arrive.
  ///
  /// The only observation channel, and a stream rather than a pollable snapshot
  /// because the fault that matters most is a **frozen** counter: mpv emits a
  /// change event only when a value changes, so a lapsed provider token, which
  /// freezes the position with the renderer still reporting health, is invisible
  /// to anything that waits to be told.
  Stream<PlaybackTick> get ticks;

  /// The stamp the accepted ticks carry, or null before the first one.
  ///
  /// Public because a consumer that keeps its own state across a channel change
  /// needs the same discriminator the engine uses: ticks from the load that was
  /// replaced are in flight on every real transport, and reading one as the
  /// current load's is what the stamp exists to prevent.
  int? get session;

  /// What the counters say right now.
  ///
  /// Six members rather than "ok or broken", three of them measured shapes that
  /// a naive detector collapses into one. Read [PlaybackHealth]'s own doc before
  /// branching on it; in particular `notPresenting` is an asleep display rather
  /// than a fault, and no production player models it at all.
  ///
  /// Reverts to `PlaybackHealth.idle` whenever there is no session to describe:
  /// after [stop], after [dispose], and between a [load] and its first tick. A
  /// verdict held over from the previous load is a verdict about a stream that
  /// is no longer playing.
  PlaybackHealth get health;
}
