# watchools_player

A spike, not the player. It answers one question, and the answer is yes:

**libmpv renders into a `CAMetalLayer` inside a Flutter `AppKitView`, and
Flutter composites its own widgets above it.**

```sh
node ../../tool/xtream-mock/server.mjs        # from the repo root
cd example && flutter run -d macos
```

The example autoplays the mock panel's H.264 channel and writes what it sees to
its sandbox container.

## What was measured

From inside the running Flutter app, reported over the channel:

```json
{"running":true,"videoOutput":"gpu-next","width":640,"height":360,"hasPicture":true}
```

`videoOutput` is empty until mpv's video output configures, so `gpu-next` there
is the renderer coming up inside the platform view rather than merely a demuxer
opening a URL. The mock's own log shows segments being fetched continuously
alongside it.

And from the app capturing its own window twice, 0.6 s apart: **21,648 of
155,570 sampled bytes changed**. The written PNG shows the Flutter chrome, the
video inside the platform view with a correct 16:9 letterbox, and a Flutter
overlay drawn on top of the video. That overlay is the compositing proof: an
externally drawn `CALayer` with Flutter's own layers above it, which is exactly
what the base-layer-black bug used to break.

The capture also shows the Flutter UI frozen on a stale frame while the video's
own timecode advances, because `SelfCapture` spins the run loop on the platform
thread. That is a wart in the affordance rather than in the architecture, and it
happens to demonstrate the point: mpv drives its layer independently of
Flutter's paint loop.

## What this taught, beyond the answer

- **`gpu-context=moltenvk`, not upstream's `macvk`.** Upstream mpv reads `WinID`
  in four files and no macOS file is among them, so `--wid` is a no-op there.
  This works only because MPVKit carries a patch whose context casts `WinID` to
  a `CAMetalLayer`.
- **A sandboxed macOS app needs `com.apple.security.network.client`.** The
  Flutter scaffold ships `network.server` and not the client, so libmpv reached
  nothing at all and the failure looked like a rendering problem for a while.
  The main app already has it; a freshly generated example does not.
- **A sandboxed app cannot write to `/tmp`.** The first attempt at the state
  file produced nothing and said nothing. It goes in the container.
- **An app may capture its own window without Screen Recording permission, and
  cannot capture another app's.** A helper binary outside the process found the
  window, printed its size, and then got nil from the capture with no error, so
  the capture had to move inside the plugin.
- **MPVKit resolves through SPM into a Flutter plugin with no Podfile.** Flutter
  3.47 has Swift Package Manager on by default and this repository is already
  migrated, so the dependency is three lines in `Package.swift`.

## What is deliberately absent

No `PlaybackEngine`. That interface belongs in Dart with buffer, live offset,
position, telemetry and fault as first-class members, and it gets written now
that this question is settled. `play`, `state`, `stop` and `captureSelf` are the
smallest surface that could answer it.

No resize handling beyond keeping `drawableSize` honest. The patched `moltenvk`
context answers every VOCTRL with `VO_NOTIMPL`, so mpv is never told the layer
resized and only a video reconfig re-reads the drawable. Measured: growing the
layer leaves the swapchain at the old size, and forcing a reconfig through the
client API does not fix it. The fix is a patch to `moltenvk_control` that we
write and offer upstream; this view is already shaped so that lands without
further change here.

No gestures. Flutter's arena does not hand gestures to a macOS platform view, so
every control belongs in Flutter above the view, which is where they want to be
anyway for one design across touch, mouse and D-pad.

The buffer options in `MpvEngine` are the ones the measurements chose: zap on the
real provider's channel was 3040 ms on mpv's defaults and 1658 ms on this shape,
with an 18 s mean buffer and zero stalls across 135 s. See
`.ac/research/player-layer.md`.
