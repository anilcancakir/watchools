# Directory survey

Stage 1a, main agent. Branch `playback-layer`, off `origin/master` at `68b1868`, which is the
squash of the Xtream protocol layer (PR #25). So both halves this plan connects are now on master.

## Top-level structure

One repository, two halves plus a plugin.

```
lib/                     Flutter app
  app/
    controllers/         GuideController, LibraryController
    models/              channel, programme, title_item, provider_fault
    protocol/xtream/     credentials, json, client, account   (new, from #25)
    provider/            catalogue_store, provider_session    (new, from #25)
    providers/           magic service providers
    support/             guide_clock, fixtures, fixture_scale
  ui/
    components/          atomic components, each a folder with index/recipe/preview
    layouts/             now, time, showcase, curtain + support/
  config/                app.dart, network.dart, wind_theme.g.dart
  routes/app.dart
packages/watchools_player/   the libmpv plugin, macOS only
backend/                     Laravel 13
tool/xtream-mock/            the executable wire contract, 77 verify checks
tool/dusk/                   e2e walks and the perf harness
.ac/research/                player-layer.md (708 lines), stack-decisions.md (412)
```

## Language / stack markers

- `pubspec.yaml`: Flutter 3.47 / Dart 3.13, six platforms scaffolded. `magic: ^0.0.9`,
  `fluttersdk_wind: ^1.5.0`, `magic_devtools: ^0.0.4`, and `sqlite3: ^3.2.0` added by #25.
- `pubspec_overrides.yaml` (gitignored): resolves the ecosystem from `/Users/anilcan/Code/fluttersdk/`.
- `packages/watchools_player/pubspec.yaml`: **still the scaffold's manifest.** Description reads
  "A new Flutter plugin project.", `homepage:` is empty, and `plugin.platforms` declares **macos
  only**. `plugin_platform_interface: ^2.0.2` is a declared dependency.
- `backend/composer.json`: Laravel 13, PHP 8.5.
- `.github/workflows/ci.yml`: the lock check runs before `pub get`; coverage floor 90 on both halves.

## Project conventions

From `CLAUDE.md` and `.claude/rules/workflow.md`, the ones this topic activates:

- **"Playback goes behind one `PlaybackEngine` interface from the first playback screen, never a
  direct package call from a widget. Six implementations are coming (Media3, AVPlayer, media_kit,
  hls.js, Tizen AVPlay, tvOS) and retrofitting the interface later means rewriting every screen
  that touches playback."** This plan is that first playback screen, so the rule fires now.
- Wind owns styling: `className` strings and `W`-prefixed widgets only, never `Colors.*` or a raw
  `TextStyle`. Import `package:flutter/widgets.dart` plus `material.dart show Icons`.
- Magic owns everything below the widget: controllers through `Magic.findOrPut`, routes registered
  in a provider's `boot()` **before** `MaterialApp` first reads the router config, because
  `addRoute` throws afterwards and the route silently never appears.
- Wind has **no D-pad activation** (`WAnchor` is `Focus` plus `GestureDetector`, no key handling)
  and **no focus traversal policy**. Every layout already writes `focus:ring-2`, so the visual half
  is settled and activation is not. A playback screen is the surface where that gap bites hardest.
- `PageGutter` is the only place the gutter numbers live.
- Never log a provider credential, never commit one.
- Each task takes its own worktree, branch and PR; `master` is never written directly.

## Sub-projects

`packages/watchools_player` is a Flutter plugin package with its own `pubspec.yaml`,
`analysis_options.yaml` and `test/`. It is **not** referenced by the app's `pubspec.yaml` or by
`pubspec_overrides.yaml`, so nothing in `lib/` imports it today.

## What the plugin actually exposes, read in full

`packages/watchools_player/lib/watchools_player.dart`, 366 lines, plus
`lib/src/stall_detector.dart`, 139.

Its own class doc is the most important input to this plan:

> **"A spike, not the player."** ... "The `PlaybackEngine` the research calls for, with buffer, live
> offset, position, telemetry and fault as first-class members, gets written once that is settled,
> **and it will not look like this**."

So the interface is a redesign rather than a thin wrapper, and the members it should carry were
already named by the research: buffer, live offset, position, telemetry, fault.

Surface today, every member `static`:

- `WatchoolsPlayer.play(int viewId, String url, {String? userAgent})`
- `WatchoolsPlayer.state()` returning `PlayerState` (running, videoOutput, width, height,
  cacheSeconds, plus `hasPicture`)
- `WatchoolsPlayer.stop()`, `WatchoolsPlayer.dispose(int viewId)`
- `WatchoolsPlayer.events`, a `static final Stream<PlayerEvent>`
- `WatchoolsPlayer.captureSelf(path, {viewId})`, a spike affordance for the compositing proof
- `PlayerEvent` (name, session, tick, reason, error, text, level; `isEnd`, `isGap`)
- `PlayerTick` (session, monotonicNs, timePos, paused, coreIdle, forwardBytes, inputRate,
  underrun, demuxerIdle)
- `WatchoolsPlayerView`, a `StatefulWidget` wrapping `AppKitView` with
  `viewType: 'watchools_player/view'`, minting the `viewId` and calling `dispose` on teardown
- `StallDetector` / `PlaybackHealth` (idle, playing, paused, notPresenting, starving, stalled)

Three properties of that surface that constrain the interface:

1. **Everything is static and there is one global core.** `events` is a single `static final`
   stream and its doc explains at length why it cannot be a getter: a binary messenger holds one
   handler per channel name, so a second `receiveBroadcastStream()` steals the stream. A
   per-instance `PlaybackEngine` over a globally static implementation is therefore a real design
   tension, and the doc itself anticipates two consumers (the variant ladder and a mini player).
2. **Gestures do not reach Flutter's arena through a macOS platform view**, so every control lives
   in Flutter above the view. The widget sets no hit-test behaviour on purpose.
3. **`captureSelf` should not survive into the interface**; it exists to prove compositing.

## Provisional research angles

1. What already exists that a playback layer reuses, beyond the plugin: `ProviderSession`,
   `XtreamCredentials.describe(Uri)`, `PlayProgress`, the scrims, `WAnchor`.
2. What the native side actually implements versus what the Dart surface exposes, so the interface
   knows what it can demand today and what needs Swift work.
3. How a new full-screen route is registered and reached, and what today navigates from a channel
   tile (nothing does: `LiveTile.onTap` is wired to selection, not playback).
4. What `.ac/research/player-layer.md` (708 lines) and `stack-decisions.md` (412) already decided
   about the engine, the variant ladder, the thresholds, and which of those they marked unverified.
5. Which existing UI pieces a playback screen would compose, and how the D-pad and focus gap
   affects a surface whose controls are all overlay.
6. How to test an interface whose only implementation is a platform view and a method channel, and
   what the plugin's own two test files already do.
7. The stream-URL surface: what the mock serves for live, VOD and timeshift, the five catch-up
   conventions, `allowed_output_formats`, and the per-title `container_extension`.
8. How real Flutter players shape an engine abstraction across many platforms, and whether
   `plugin_platform_interface` (declared and unused here) is the idiom to adopt or to drop.
