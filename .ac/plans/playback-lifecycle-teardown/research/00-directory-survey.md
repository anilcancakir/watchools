# Directory survey

Topic: issue #27. An app-lifecycle observer that releases the libmpv core, the account's single
connection slot and the wakelock when the app is backgrounded, and decides what `resumed` means.

## Where this lands

`packages/watchools_player/` is the plugin (macOS only, a `macos/` directory and nothing else).
`lib/app/playback/` holds the interface, the fake and the mpv implementation. `lib/app/controllers/
playback_controller.dart` is what the screen reads, and `lib/resources/views/playback_view.dart` is
the screen. The issue argues the observer belongs with the ENGINE rather than the screen, for the
same reason the wakelock does: it follows the core's lifetime, not a route's.

## What the issue asserts, and what is verified

VERIFIED by grep: no `WidgetsBindingObserver`, no `didChangeAppLifecycleState`, no
`AppLifecycleState` anywhere in `lib/` or `packages/watchools_player/lib/`. The single hit is a doc
comment at `lib/resources/views/playback_view.dart:46` recording the absence.

Asserted by the issue and to be checked during the deep read: that `WatchoolsPlayerPlugin.swift:186-191`
stops the core when a platform view is pruned, which is why macOS costs nothing today.

## The three things backgrounding is said to cost

From the issue, each traceable to a measurement this repository already holds:

1. The core keeps running with no surface presenting.
2. The single connection slot stays held. `max_connections` is 1 on the measured account and a second
   concurrent stream killed the first at 5.79 s (`.ac/research/player-layer.md:218-231`).
3. The wakelock stays held, so the display is kept awake for a stream nobody is watching.

## The design question, which is the whole reason this is a plan

`resumed` has two defensible answers and the evidence for each is in this repository. A provider
token can lapse while backgrounded, and `StallDetector` cannot tell a lapsed token from a healthy
wait: both freeze `time-pos` with `underrun: true`, `demuxerIdle: false` and `fw-bytes: 0`, and they
differ only in whether they recover (`.ac/research/player-layer.md:579-600`). So "resume" and "reload"
are not interchangeable, and picking wrong is either a stall the user has to escape by hand or a
reconnection nobody asked for on a 1-connection account.

## Platform reality that bounds the answer

No mobile target is wired yet, which is why this is groundwork rather than a live bug. macOS is the
only target that runs today and it disposes the platform view on a route pop, which already stops the
core. So the observer has to be written for behaviour nobody can exercise here, which raises the bar
on the tests rather than lowering it.

## Provisional research angles

1. What already exists for teardown: the wakelock seam, `stop`, `dispose`, `detach`, and the
   connection gate. Reuse map input.
2. The engine's own surface and lifetime: what `MpvPlaybackEngine` owns, what `PlaybackController`
   owns, and where an observer can attach without inverting that.
3. What the app can know about a lapsed token on resume, from `StallDetector`, `PlaybackHealth` and
   the FFmpeg reconnect ladder already configured.
4. Test patterns: how a lifecycle transition is driven in a Flutter test, and which existing fake
   reaches the engine.
5. Flutter's own lifecycle contract per platform, including which states actually fire on Android,
   iOS and macOS, and whether `AppLifecycleListener` supersedes `WidgetsBindingObserver`.
6. What other media clients do on background, and what the platforms require of them (iOS background
   audio, Android foreground service). This decides whether stopping is even the right default.
