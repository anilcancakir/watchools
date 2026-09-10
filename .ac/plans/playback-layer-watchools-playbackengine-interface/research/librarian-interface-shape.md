# The idiomatic shape, and what real players actually model (ac:librarian x2)

Two briefs merged. Citations are pinned to a commit SHA where the source is on GitHub; the Apple
pages are live docs with no SHA to pin.

## `plugin_platform_interface`: adopting it is not a clear win

Its job, from its own class doc: "Base class for platform interfaces. Provides a static helper
method for ensuring that platform interfaces are implemented using `extends` instead of
`implements`." The private `Token` is what `verifyToken` checks, and since only the interface's own
file can construct that `Object()`, no external `implements` can forge it. The payoff is that
"platform implementations that `implements` their platform interface will be broken by newly added
methods", while extenders inherit defaults.

**But the package's own README says the Flutter team is considering deprecating it**, in favour of
Dart 3's `base` keyword, "but no decision has been made yet since it removes the ability to do
mocking/faking". So the docs themselves treat this as open, and "plugin authors may want to consider
using `base` instead of this package when creating new plugins".

- https://pub.dev/documentation/plugin_platform_interface/latest/plugin_platform_interface/PlatformInterface-class.html
- https://github.com/flutter/packages/tree/main/packages/plugin_platform_interface

This repository declares `plugin_platform_interface: ^2.0.2` and uses no `PlatformInterface` or
`Token` anywhere, so the plan must either adopt the pattern deliberately or drop the dependency
deliberately. Doing neither is the current state.

## Federation is still the practised structure

"Federated plugins are a way of splitting the API of a plugin into a platform interface,
independent platform implementations of that interface, and an app-facing interface that uses the
registered implementation of the running platform."
(https://docs.flutter.dev/packages-and-plugins/developing-packages)

And the team's own repo: "Plugins in flutter/packages uses the federated plugin model... This
layout reflects the goal of having all multi-platform plugins in flutter/packages being fully
federated."
(https://github.com/flutter/flutter/blob/master/docs/ecosystem/Plugins-and-Packages-repository-structure.md)

A single package listing several platforms under `plugin.platforms` is documented and legitimate,
and the repository-structure doc treats it as the accepted shape for "inherently single-platform"
plugins. **The docs never compare the two.** What federation's own page claims you would forgo:
"this approach allows a domain expert to extend an existing plugin to work for the platform they
know best", without "coordinating with the original plugin author". The librarian explicitly
declined to invent a tradeoff table the docs do not contain.

## One channel per implementation, never a shared name

The platform-channels page's naming rule is per app, not per implementation: "All channel names
used in a single app must be unique; prefix the channel name with a unique 'domain prefix'".
(https://docs.flutter.dev/platform-integration/platform-channels)

The docs say nothing about naming across several implementations of one interface, which is a
genuine gap. Practice in `flutter/packages` answers it: `video_player_android` declares
`@HostApi() abstract class AndroidVideoPlayerApi` in its own Pigeon spec, scoped entirely to that
package, and nothing about it is shared with `video_player_avfoundation`. **The platform interface
is the only shared contract.**
(https://github.com/flutter/packages/blob/20928d58f50700f7bb08e1146e204cded334aabf/packages/video_player/video_player_android/pigeons/messages.dart)

## The platform-view id ordering problem has an official answer

The id is **minted synchronously**, ahead of the native view existing:
`_id = platformViewsRegistry.getNextPlatformViewId();` runs immediately inside `_initialize()`
(`platform_view.dart:792`, and `:1316`). Creation is asynchronous and only flips state after the
round trip:

```dart
_state = _AndroidViewState.creating;
await _sendCreateMessage(size: size, position: position);
_state = _AndroidViewState.created;
for (final PlatformViewCreatedCallback callback in _platformViewCreatedCallbacks) {
  callback(viewId);
}
```

`bool get isCreated` and `bool get awaitingCreation` exist "precisely so callers can query whether
the async creation has completed before sending it further method-channel calls"
(`platform_views.dart:851-943`). And `PlatformViewLink`'s doc states the lifetime contract: "The
platform view's lifetime is the same as the lifetime of the State object for this widget."

So the sanctioned gate is the created-callback plus those two getters, which is what the existing
`WatchoolsPlayerView` already does with `onPlatformViewCreated`.

- https://github.com/flutter/flutter/blob/d2370a79e5605278c9eabcfc5e4221d91c47833b/packages/flutter/lib/src/widgets/platform_view.dart#L792
- https://github.com/flutter/flutter/blob/7266dd5540f0b2b120753c1d8e45266f1eafd203/packages/flutter/lib/src/services/platform_views.dart#L851-L943

## What `video_player_platform_interface` puts in the interface

Lifecycle (`init`, `createWithOptions`, `dispose(playerId)`), an **opaque integer `playerId`**
threaded through every call, playback verbs (`play`, `pause`, `seekTo`, `setPlaybackSpeed`,
`setVolume`, `setLooping`, `getPosition`), **one** `Stream videoEventsFor(int playerId)`, **one**
`Widget buildView(VideoViewOptions)`, and posture knobs: `setMixWithOthers`,
`setAllowBackgroundPlayback`, and **`setPreventsDisplaySleepDuringVideoPlayback`**.

That last one is directly relevant here: the first-party interface treats preventing display sleep
as an interface member rather than as an app-side package. This project measured that an idle
display freezes libmpv's `time-pos` at the first frame, so it is a correctness concern, and there is
precedent for putting it in the engine contract.

What it leaves to implementations: the engine, whether rendering is a texture or a platform view,
and all channel wiring. **The interface carries no protocol, no channel name and no decoding
detail.**
(https://github.com/flutter/packages/blob/main/packages/video_player/video_player_platform_interface/lib/video_player_platform_interface.dart)

## Neither Dart player is a model for live TV

**media_kit**, the closest analogue since it also wraps libmpv:
`PlayerState` carries `playing`, `completed`, `position`, `duration`, `buffering` (bool),
`buffer` (a single `Duration`, "how much of the stream has been decoded & cached by the demuxer"),
`bufferingPercentage`, plus tracks. Errors are `Stream<String> error`, unstructured.

**Absent from all 114 of its Dart source files**: `isLive`, a live offset, a seekable or buffered
**range**, and any structured fault. Its buffer is a scalar depth with no ahead/behind split. It is
a VOD-and-generic-stream abstraction, and live semantics would have to be built entirely above it.
(https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit/lib/src/models/player_state.dart#L20-L52)

**video_player**: `VideoEventType` is `initialized`, `completed`, `bufferingUpdate`,
`bufferingStart`, `bufferingEnd`, `isPlayingStateUpdate`, `unknown`. **No stalled and no error event
type on the platform interface at all.** Buffered segments are a real `List<DurationRange>`. And
`VideoPlayerValue.duration` is **required and non-nullable**, so the whole value model assumes VOD.

## The state models, compared

| System | States | Live edge | Buffered / seekable | Fault |
|---|---|---|---|---|
| media_kit | `playing`/`buffering`/`completed` bools | none | scalar `Duration` | `Stream<String>`, unstructured |
| video_player | 7 `VideoEventType` values | none | `List<DurationRange>` | `errorDescription: String?` |
| ExoPlayer / media3 | `STATE_IDLE(1)`, `BUFFERING(2)`, `READY(3)`, `ENDED(4)`, plus `isPlaying()`, `isLoading()`, `PlaybackSuppressionReason` | **`isCurrentMediaItemLive()` + `getCurrentLiveOffset()`**, ms from now, `TIME_UNSET` when not live | `getTotalBufferedDuration()` | **no error state**: an error returns the player to `STATE_IDLE`, read via `getPlayerError()` |
| AVPlayer | `timeControlStatus`: `paused` / `waitingToPlayAtSpecifiedRate` / `playing`, plus `reasonForWaitingToPlay` with 5 values | `AVPlayerItem.seekableTimeRanges`, a shifting window for live | `loadedTimeRanges` | no enum; `status == .failed` plus `.error` |
| hls.js | event-based: `STALL_RESOLVED`, `BUFFER_*`, `LEVEL_*`, `ERROR` | `BACK_BUFFER_REACHED`; the sliding window is internal to `levelDetails` | events only; ranges off `HTMLMediaElement.buffered` | **`ErrorTypes` x `ErrorDetails`, ~40 members incl. `bufferStalledError`, each with a `fatal` flag** |

- https://github.com/androidx/media/blob/1c51639dfe0180bc9977bd87a030a8744c0a0090/libraries/common/src/main/java/androidx/media3/common/Player.java#L1291-L1314 and `#L3182-L3206`
- https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum
- https://github.com/video-dev/hls.js/blob/aad2186570df897d3e58aaa5200d2d68e2c22cef/src/errors.ts#L1-L108

## Where they disagree with a six-member health model, which validates it

**Every reference player except hls.js collapses "stalled" into "initial buffering".** ExoPlayer has
one `STATE_BUFFERING` for both. AVPlayer has one `waitingToPlayAtSpecifiedRate`, distinguished only
by an advisory `reasonForWaitingToPlay`. hls.js is the outlier with a transient in/out signal, and
even it has no continuous stalled **state**, only events.

That independently validates this project's own measurement that a layer below the engine cannot
distinguish stalled from ended on a lapsed token: **none of the four production players solves that
distinction structurally.** They solve it by convention, timing out a stall in app code.

Two more specific conclusions:

- **`notPresenting` has no analogue in any of the four.** Frames frozen while the clock says playing
  is exactly the gap this project measured, and no reference implementation exposes a state for it.
  Correctly modelled app-side.
- **ExoPlayer folding error into `STATE_IDLE` is a mistake to avoid**, not a precedent to follow:
  "idle" and "error" being one wire value argues for keeping `idle` and the fault genuinely separate,
  which the project's model already does.

**And the live-offset precedent is ExoPlayer's, not Dart's.** `getCurrentLiveOffset()` returning ms
from now with a `TIME_UNSET` sentinel is the shape to borrow, since neither Dart player has one.

## Coverage gaps the librarians declared

`better_player` and `flick_video_player` were not read; both wrap `VideoPlayerValue` for controls
chrome rather than adding state members, so they were deprioritised. Flag if the controls layer
becomes load-bearing. And the built-in `WebSearch` budget was exhausted (200/200) before these
briefs ran, so every citation came from the proxy tools or from pinned `gh api` reads rather than
from the primary search path.
