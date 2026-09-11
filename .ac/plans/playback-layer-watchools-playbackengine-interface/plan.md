# Plan: playback-layer-watchools-playbackengine-interface

**Steps**: 13
**Waves**: 6
**Codebase State**: disciplined
**Auto mode**: false
**Generated**: 2026-09-09

## Research Summary

Ten briefs merged into six files under `research/`: seven `ac:explore` (four in
`explore-app-side.md`, two in `explore-stream-url-and-plugin.md`, one in
`explore-existing-player-research.md`), two `ac:librarian` (both in `librarian-interface-shape.md`)
and one `ac:oracle`, whose verdicts are folded into `verification-log.md` rather than kept as a file
of their own. `00-directory-survey.md` is my own first-pass reading, not a brief.
`verification-log.md` carries what I checked myself against source; prefer it over any other file
where they disagree, **including over this summary**.

Branch `playback-layer`, off `origin/master` at `68b1868`, which is the squash of the Xtream
protocol layer. Both halves this plan connects are on master.

**The delta**: the interface, a stream URL builder, one native control, the plugin dependency, a
controller, a screen, a route, a display-awake hold, and a sibling publish.

Load-bearing verified facts:

- **The plugin has no playback controls at all.** Across all four Swift files, `mpv_command`
  appears once (`MpvEngine.swift:157`, issuing only `loadfile`), `"pause"` appears once and only in
  the tick's read loop (`:363`), and `seek` appears **zero** times. `PlayerTick.paused` reports a
  state nothing can set.
- **The reading half is already complete.** `PlayerTick` carries `session`, `monotonicNs`,
  `timePos`, `paused`, `coreIdle`, `forwardBytes`, `inputRate`, `underrun` and `demuxerIdle`, which
  is exactly what `StallDetector` consumes. No native work is needed for observation.
- **One core at a time**, and it is aligned rather than limiting: `WatchoolsPlayerPlugin.swift:144`
  holds one `MpvEngine`, `MpvEngine.swift:84-85` refuses a second `start()`, and the measured
  account's `max_connections` is **1** with a second concurrent variant killing the first at
  5.79 s (`player-layer.md:218-228`).
- **An mpv log line can carry the provider password into Dart.** The URL carries the credential in
  its **path**, the plugin subscribes at warn level (`MpvEngine.swift:127`) and forwards the text
  **verbatim** (`:465`), and FFmpeg's reconnect warnings name the URL. That log channel is also the
  only signal for a lapsing token, so it cannot be switched off. See `verification-log.md`.
- **Stalled and ended are not distinguishable from below**, and no production player solves it
  structurally: ExoPlayer has one `STATE_BUFFERING`, AVPlayer one
  `waitingToPlayAtSpecifiedRate`, and only hls.js has a transient stall signal with no stalled
  state. **`notPresenting` has no analogue in any of the four.**
- **Starvation and a lapsed token present identically**: both freeze `time-pos` with
  `underrun: true`, `demuxerIdle: false`, `fw-bytes: 0`. They differ only in whether they recover
  (`player-layer.md:588-621`).
- **`AppKitView` disposal is deferred by design** to the next compositor present
  (`FlutterPlatformViewController.mm:64-75`), with no "about to dispose" hook, while a hot restart
  disposes every view **synchronously** via `reset()` (`:182-187`).
- **`SystemChrome.setEnabledSystemUIMode` and `setPreferredOrientations` are dead code on macOS**:
  the embedder has no handler at all. `wakelock_plus` **does** support macOS with a real native
  implementation.
- **The platform-view id is minted synchronously** and creation is async;
  `onPlatformViewCreated` plus `isCreated`/`awaitingCreation` are the sanctioned gate
  (`platform_views.dart:851-943`).
- **The path segment is `movie`, not `vod`** (`server.mjs:897`, `:904`). One research report got
  this wrong and it is logged as refuted.
- **Two of my own figures were refuted** by the oracle and confirmed refuted by me: the 300 s token
  TTL is our mock's constant against a panel measured at about forty minutes
  (`catalogue.mjs:58-68`), and "115 live ticks" has no source in this repository (the recorded
  figure is 106, documenting the **idle-display** freeze).

## Codebase Conventions

- **Naming**: `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` members. Test files
  mirror the source path with a `_test.dart` suffix.
- **Error handling**: no fallback `try/catch` that swallows. Handle deliberately into a value the
  UI already renders, or let it propagate.
- **Comment density**: doc blocks everywhere, carrying what the signature cannot: the contract, the
  failure mode, the unit, the measurement that decided a number. Never restate a parameter name.
  This is the single strongest convention in the repo; match it or the code reads as foreign.
- **Type discipline**: strict. Explicit types on every parameter, return and field. No `dynamic`
  unless a wire boundary forces it.
- **File organisation**: nested by role under `lib/app/`, one concept per file. No barrel exports
  under `lib/app/`; a UI component folder is the exception and carries `index.dart` alongside
  `*.recipe.dart` and `*.preview.dart` with a **dot**, which is what `previews:refresh` discovers.
- **Import convention**: relative within `lib/`, `package:` for external.
- **Path aliases**: none.
- **LSP false-positive whitelist**: `lib/config/wind_theme.g.dart`, `lib/app/_plugins.g.dart` and
  `lib/_previews.g.dart` are generated; never edit, never report their diagnostics.
- **Test mount discipline**: `wrapWithTheme()` (`test/support/wind_test_app.dart:34`) for a leaf,
  `pumpScreen()` (`test/support/screen.dart:44`) for a whole screen, which leaves the surface at
  800x600 unless a size is passed. Every widget test calls `setUp(WindParser.clearCache)` or it can
  pass for the wrong reason. **Overflow assertions are meaningless**: `flutter_test` substitutes a
  font whose every glyph is a square of the font size. `.env` is a real asset, so assert an
  **overridden** value via `Env.reset(); Env.load(mergeWith: {...})`, never a default. A method
  channel is faked with
  `TestDefaultBinaryMessenger.instance.defaultBinaryMessenger.setMockMethodCallHandler`, the
  pattern at `packages/watchools_player/test/watchools_player_test.dart:22-35`.
- **TDD**: yes. Failing test first on every `code` step. The CI denominator excludes only
  `lib/resources/views/`, `lib/app/providers/`, `lib/app/kernel.dart` and `lib/routes/app.dart`, so
  **`lib/app/playback/` counts toward the 90% floor** and a fake engine is a first-class
  deliverable rather than a test helper.
- **Wind and Magic are not optional**: `className` strings and `W`-prefixed widgets for anything
  visual, never `Colors.*`, `Color(0x...)` or a raw `TextStyle`. Import
  `package:flutter/widgets.dart` plus `material.dart show Icons`. Routes through `MagicRoute`,
  never a bare `Navigator`. `Http`, `Vault`, `DB` facades below the widget.
- **One page container**: `lib/ui/layouts/support/page_gutter.dart` is the only place the gutter
  numbers live. Never write one by hand.
- **Numbers off the wire**: decode every numeric as `num`, never `as int` or `as double`.

## Reuse Map

| Need | Reuse | Where |
|---|---|---|
| Telemetry the health model reads | `PlayerTick`, `PlayerEvent`, `PlayerState` | `packages/watchools_player/lib/watchools_player.dart:174`, `:253`, `:122` |
| The health verdict itself | `StallDetector`, `PlaybackHealth` | `packages/watchools_player/lib/src/stall_detector.dart:52` |
| The render surface | `WatchoolsPlayerView`, an `AppKitView` minting its own id | `watchools_player.dart:328` |
| Naming a provider URL safely | `XtreamCredentials.describe(Uri)` | `lib/app/protocol/xtream/xtream_credentials.dart:116` |
| Base URL, username, password, per-provider user agent | `XtreamCredentials` | `xtream_credentials.dart:23` |
| What the account permits | `XtreamAccount.allowedOutputFormats`, `maxConnections`, `active` | `xtream_account.dart:26` |
| The channel's own identity | `Channel.streamId`, persisted | `lib/app/models/channel.dart:67`, `lib/app/provider/catalogue_store.dart:143` |
| The session, its fault and its playback gate | `ProviderSession`, `isPlaying` predicate | `lib/app/provider/provider_session.dart` |
| Controller shape: session listener, cache invalidation, `refreshUI()` | `GuideController` | `lib/app/controllers/guide_controller.dart:91` |
| The overlay pattern: stack, two scrims, positioned controls, bottom progress | `CurtainLayout` | `lib/ui/layouts/curtain_layout.dart:113-157` |
| Progress bar | `PlayProgress` | `lib/ui/components/play_progress/` |
| Scrims, as raw gradients because Wind has no stops | `Scrim.bottom`, `Scrim.left` | `lib/ui/components/scrim/scrim.dart:21` |
| Icon-only affordance, the closest thing to one | `FavouriteButton(shape: 'bare')` | `lib/ui/components/favourite_button/` |
| Fault rendering, all four members | `ProviderNotice` | `lib/ui/components/provider_notice/` |
| Route registration, and the only legal site | `RouteServiceProvider.boot()` | `lib/app/providers/route_service_provider.dart:24` |
| Method-channel fake | the plugin's own test | `packages/watchools_player/test/watchools_player_test.dart:22-35` |

**Not reused, deliberately**: `plugin_platform_interface`, which the plugin declares and never
uses. Its own README says the Flutter team is considering deprecating it in favour of Dart 3's
`base`, with no decision made, so this plan **removes** the dependency rather than adopting a
pattern for one implementation. And `media_kit` is not a model to copy: it has no `isLive`, no live
offset, no buffered range and no structured fault across all 114 of its Dart source files.

## Work Objectives

1. **A channel tapped on `Şimdi` plays.** Today `LiveTile.onTap` reaches
   `GuideController.selectChannel` (`guide_controller.dart:548-551`), which updates the hero and
   navigates nowhere, and the hero's own play affordance is `onTap: () {}`
   (`now_layout.dart:327`). After this plan a tap reaches a playback route, an engine loads a
   derived URL, and libmpv renders into a platform view under a Flutter overlay.
2. **Playback goes behind one `PlaybackEngine` interface from the first screen**, per `CLAUDE.md`,
   never a direct package call from a widget. The interface is **observation-complete and
   command-minimal**: everything the health model reads, plus `load`, `pause`, `resume`, `stop`.
   **No `seek`, no `duration`, no `position`**, because live TV has none of the three and a stub is
   a promise.
3. **No provider credential reaches a log, an event or a diagnostic.** The URL carries the password
   in its path and mpv forwards log text verbatim, so redaction happens at or below the interface
   boundary rather than at a call site.
4. **A refresh cannot evict the stream the user is watching.** The account's `max_connections` is
   1, and `ProviderSession`'s gate is currently a predicate wired to nothing.

**Must NOT Have**: no scope inflation, no premature abstraction (no federated package split for one
implementation; `CLAUDE.md`'s rule is the third concrete caller), no copy-paste with variation, no
comment that restates the code, no documentation bloat, no over-validation on trusted internal
input. No variant ladder: it is deferred and this plan must not design it out.

## Tier Calibration

Three steps carry `rule-5-criticality` and land on `senior`. Step 1 decides how a password-bearing
URL is constructed and where it may appear. Step 2 decides the one filter standing between mpv's
log channel and a debug record. Step 6 decides which strings from the native side reach the app at
all. Each is a before-and-after on a listed surface rather than a step that merely touches one.

Two steps carry `rule-1-cross-layer` and land on `senior` or `junior-high`: step 5 defines the
contract six implementations will conform to, and step 11 threads a tap through a controller, a
route and two layouts.

Three carry `rule-none` at `junior-high`: the native control, the engine implementation and the
screen. Each is heavier than pattern application and each can fail by looking like it works.

The rest are `junior`. **No step is `quick`**: the codebase is `disciplined` with an unusually heavy
doc-block convention, and a mechanical edit that ignores it reads as foreign.

## Execution Strategy

Six waves. Wave 1 is three independent foundations, one of which is in another repository. Wave 2
adds the native control and the contract. Wave 3 implements the contract and wires the dependency.
Wave 4 is the controller and the composition root. Wave 5 is the screen and the route. Wave 6
measures and gates.

| Wave | Steps | Why together |
|---|---|---|
| 1 | 1, 2, 3 | No dependencies between them; step 3 is in the Wind repository |
| 2 | 4, 5 | The native control and the interface are independent of each other |
| 3 | 6, 7 | The implementation needs both, and both need the plugin dependency step 6 adds |
| 4 | 8, 9 | The controller needs the engine; the root wiring needs the controller |
| 5 | 10, 11 | The screen and its route, and 11 needs 10 |
| 6 | 12, 13 | The token measurement, then the gate |

### Dependency Notes

| Step | Needs | Why |
|---|---|---|
| 1 | none | reads `XtreamCredentials` and `Channel`, both shipped |
| 2 | none | extends `XtreamCredentials`, shipped |
| 6 | 1, 2, 4, 5 | builds the URL, redacts the log, calls the native control, conforms to the contract |
| 7 | 6 | the engine is what holds the wakelock |
| 8 | 5, 6 | holds the interface, resolves the implementation |
| 9 | 8 | wires the predicate from the controller's engine |
| 10 | 8 | reads the controller |
| 11 | 10 | routes to the screen |
| 12 | 1 | measures the URL the builder produces |
| 13 | all | the gate |

**Waves 3, 4, 5 and 6 are ordered tracks: their steps must run in sequence, one at a time, in the
order listed, never spawned together.** The executor spawns a wave's steps in parallel by default
and treats a declared ordered track as its one exception, so this paragraph is what makes these four
serial. Only wave 1 and wave 2 run in parallel.

| Wave | Order | Why it cannot be parallel |
|---|---|---|
| 3 | 6, then 7 | Both edit `lib/app/playback/mpv_playback_engine.dart` and `test/app/playback/mpv_playback_engine_test.dart`; step 7 has nothing to hold the wakelock in until step 6 has written the engine |
| 4 | 8, then 9 | Both edit `lib/app/providers/app_service_provider.dart`, and step 9's predicate closure reads the controller step 8 binds there |
| 5 | 10, then 11 | No shared file, but step 11 imports and routes to the `PlaybackView` step 10 creates, so a parallel step 11 would import a file that does not exist yet |
| 6 | 12, then 13 | Step 13 is the gate over everything, step 12's evidence file included |

Waves 1 and 2 are genuinely parallel. Wave 1's three steps share no file and one of them is in
another repository; wave 2's two are the native control and the Dart contract, which touch neither
each other's files nor each other's symbols.

**Step 3 needs a human hand.** Publishing to pub.dev is irreversible and outward-facing, and the
standing authorisation in this project covers merging watchools pull requests on green CI, not
publishing packages. The step opens the release and stops; the publish and the constraint bump are
the user's.

## Steps

Paths are absolute into the worktree this plan executes in,
`/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/`. The plan is a tracked artefact
(`.gitignore:63-65`), so a later reader outside that worktree should read them as repo-relative from
the segment after `player-reconnect/`.

### Wave 1

- [x] **Step 1**: Derive a playable live URL from the credential and the channel
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, no URL in this app carries a credential; after, every playback URL embeds the user's provider password in its **path**, and this step decides how it is built, what picks the extension, and which response fields may influence the host.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_stream_url.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_stream_url_test.dart`
    - **Description**: **The symbol is `XtreamStreamUrl`, in `lib/app/protocol/xtream/xtream_stream_url.dart`, and the live entry point is the static `XtreamStreamUrl.live(...)` returning `Uri?`.** Both names are fixed here rather than left to taste, because step 8 imports them by name from a briefing that cannot see this step. Pure functions that build a live stream URL: `{baseUrl}/live/{username}/{password}/{streamId}.{ext}`. The path segment for live is `live`; for a movie it is **`movie`, never `vod`** (`tool/xtream-mock/server.mjs:897` documents the parameter as "`live`, `movie` or `series`" and `:904` branches on `kind === 'movie'`), and a `vod` segment 404s. This step ships **live only**; expose the movie and series shapes as documented-but-unbuilt only if that costs nothing, otherwise leave them out entirely. The extension is the **intersection** of what the account permits and what the channel actually serves: `XtreamAccount.allowedOutputFormats` is `['m3u8','ts']` on the measured panel, and a per-channel list narrows it further, so channel 07 (AV1) serves `.m3u8` only and answers a `.ts` request with **404 and a reason**, not a fallback (`server.mjs:926-935`). Prefer `ts` when both are available, because the measured RAW TS channels are the clean ones while the four HLS channels cannot play past the first loop wrap (`tool/xtream-mock/README.md:52-92`); make the preference an argument with that default rather than hardcoding it. **`Channel` carries no format field**: its members are `number`, `name`, `group`, `status`, `logoUrl`, `schedule`, `facts`, `favourite`, `streamId` and `catchupDays` (`lib/app/models/channel.dart:34-80`), and adding one would mean a model change, a store column and a migration. So take the channel's permitted formats as a **`List<String>` parameter** on the builder, defaulting to empty meaning "unknown, use the account's list alone", and let the caller supply it from a live entry when it has one. Take the base URL from `XtreamCredentials.baseUrl` only: **ignore `server_info.url` and ignore `direct_source`**, because the credentials ride in the path and a rewritten host field hands them to whichever host the response named. Return a `Uri`, never a `String`, so a caller cannot concatenate onto it.
    - **References**:
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/explore-stream-url-and-plugin.md`, the full route table, the 302 shape and the failure table
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_credentials.dart:23`, the record and its normalised `baseUrl`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_client.dart:189-212`, how the client keeps credentials out of the URL string and in the query map, and why
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_stream_url_test.dart` passes
        - a test asserts the live path is `/live/<user>/<pass>/<id>.ts` against a known credential and channel, matched as a whole `Uri` rather than by substring
        - a test asserts that passing channel formats excluding `ts` yields `.m3u8` rather than `.ts`
        - a test asserts that passing channel formats with **no** overlap with the account's list yields null rather than a guess
        - a test asserts that passing an **empty** channel format list falls back to the account's list alone, which is the "unknown" case a cached channel produces
        - `! grep -qE "'/vod/|\[.server_info.\]|\[.direct_source.\]" lib/app/protocol/xtream/xtream_stream_url.dart`, matched on **code shapes** rather than bare words. The bare-word form collides with the Description, which tells the worker to record "`movie`, never `vod`" in a doc block
        - `grep -qE 'class XtreamStreamUrl' lib/app/protocol/xtream/xtream_stream_url.dart` and `grep -qE '\blive\(' lib/app/protocol/xtream/xtream_stream_url.dart`: step 8 imports both names and cannot see this step to discover them
    - **QA**: `flutter test test/app/protocol/xtream/xtream_stream_url_test.dart`. Assert: the whole `Uri` equals the expected live URL; the extension follows the account-and-channel intersection with `ts` preferred; an empty intersection returns null; a base URL with a trailing slash cannot produce a double slash (the constructor already strips it, so assert the property rather than re-implementing it).
    - **Must NOT**:
        - Emit a `String`; return a `Uri` so nothing can concatenate onto it
        - Read a host from `server_info.url` or from `direct_source`
        - Log, print, or include the password in any exception message
        - Build a movie or series URL with a `vod` segment
        - Fall back to another extension when the requested one is unavailable; a 404 with a reason is the panel's answer and the caller decides

- [x] **Step 2**: Redact provider secrets from any string, not just from a Uri
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, the only redaction is `describe(Uri)`, which needs a parsed `Uri`; after, an arbitrary string from the native side can be made safe, and this is the single filter standing between mpv's log channel and a debug record that could hold a paid subscription's password.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_credentials.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_credentials_test.dart`
    - **Description**: Add `String redact(String text)` beside the existing `describe(Uri)`, replacing every occurrence of the stored username and password with the same `***` the record already uses. This exists because of a verified leak: a stream URL carries the credential in its **path**, the plugin subscribes to mpv's log at warn level (`packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift:127`) and forwards the line **verbatim** (`:465`), and FFmpeg's reconnect warnings name the URL. The plugin's own doc quotes such a line, `http: Will reconnect ... error=End of file`, and describes that log channel as the **only** signal for a lapsing token, so it cannot be switched off. `describe(Uri)` cannot help: a log line is prose containing a URL, not a `Uri`. Redact the **password first**, then the username, so a password that happens to contain the username still goes; skip an empty secret entirely, because replacing the empty string matches everywhere. Percent-encoded forms count: a URL path may carry `%40` for an `@`, so redact both the raw secret and `Uri.encodeComponent` of it. Do **not** try to parse a URL out of the text; a substring replacement is the honest tool for prose of unknown shape.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_credentials.dart:103-127`, `describe(Uri)` and the reasoning it carries about the path versus the query
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/verification-log.md`, the section "An mpv log line can carry the provider password into Dart", with the four-link chain
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, "Provider requests": never log a credential
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_credentials_test.dart` passes
        - a test asserts `redact` on a realistic FFmpeg warning containing a full stream URL returns a string containing neither the username nor the password
        - a test asserts a percent-encoded password is redacted too
        - a test asserts an empty password does not turn every character into a redaction
    - **QA**: `flutter test test/app/protocol/xtream/xtream_credentials_test.dart`. Assert: `redact('http: Will reconnect to http://h:8080/live/bob/s3cret/1.ts, error=End of file')` contains neither `bob` nor `s3cret`; the raw and percent-encoded forms both go; a credential with an empty password leaves unrelated text untouched; `describe(Uri)`'s existing behaviour is unchanged.
    - **Must NOT**:
        - Change what `describe(Uri)` does; this is a sibling, not a replacement
        - Attempt to parse a `Uri` out of the text
        - Skip the percent-encoded form
        - Log or include either secret in an exception message

- [x] **Step 3**: Wire the three dependencies, and prepare the Wind release
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: three `pubspec.yaml` lines plus a version bump and a changelog entry in another repository with its own CLAUDE.md and its own definition of done, which has to be read first.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/pubspec.yaml`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/pubspec.yaml`
        - `/Users/anilcan/Code/fluttersdk/wind/` (the release commit: version, CHANGELOG, whatever that repo's own release procedure requires)
    - **Description**: **The dependency half comes first, because every later wave needs it.** Add `watchools_player` to the app's `pubspec.yaml` as a **path** dependency, `path: packages/watchools_player`, which is the one place a `path:` is correct in this repository: `CLAUDE.md` forbids one for the sibling ecosystem packages because pub admits a single source per package and a relative path fails from a worktree, but this package lives **inside** the repository, so pub records it as `relative: true` and it resolves on any machine. Add `wakelock_plus` as a normal hosted dependency; it supports macOS through a real native implementation rather than a stub. And **remove `plugin_platform_interface` from `packages/watchools_player/pubspec.yaml`**, where it is declared and used nowhere (`grep -rn 'PlatformInterface' packages/watchools_player/lib/` returns nothing): its own README says the Flutter team is considering deprecating it in favour of Dart 3's `base` with no decision made, so carrying an unused dependency whose future is openly uncertain is worse than either using it or dropping it. This step exists in wave 1 rather than beside the code that consumes it precisely so that wave 2 can import `PlaybackHealth` from the plugin at all. Then the Wind half. `WAnchor` binds `ActivateIntent` and `ButtonActivateIntent` to its activation callback (`/Users/anilcan/Code/fluttersdk/wind/lib/src/widgets/w_anchor.dart:132-135`, installed at `:293`), which answers `enter`, `numpadEnter`, `space`, `gameButtonA` and `select`, and `select` is the D-pad centre on Android TV. **That binding exists only in an unreleased commit**: the local checkout is `version: 1.5.2` with `92f20f5 fix(w-anchor): make a control reachable by keyboard and remote` on top, and all eighteen published versions in the pub cache, including 1.5.2, grep `ActivateIntent` at **zero** in that file. This app constrains `fluttersdk_wind: ^1.5.0`, so CI and every release build resolve a Wind without activation. A playback screen developed against `pubspec_overrides.yaml` would show working remote control and ship without it. **Read `/Users/anilcan/Code/fluttersdk/wind/CLAUDE.md` before the first edit**; that project's conventions and gates win inside its tree. **The Wind half stops one step short of done, and the ordering is the whole point.** Do in Wind: the version bump, the CHANGELOG entry, whatever else that repo's release procedure requires, and its own gates green. Do **not** run `pub publish`, because it is irreversible and outward-facing and the standing authorisation in this project covers merging watchools pull requests on green CI, not publishing packages. Then, **because the publish has not happened, leave `fluttersdk_wind: ^1.5.0` in this repository exactly as it is.** A constraint naming a version pub.dev does not serve breaks `pub get` for everyone including CI, so the bump is not deferred out of caution, it is impossible until the publish lands. Report the prepared version, that it is unpublished, and the two commands a human runs to finish it (`pub publish` in Wind, then the one-line constraint bump here).
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/.claude/rules/workflow.md`, the sibling flow and its requirement of a publish plus a constraint bump after a sibling change
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/verification-log.md`, the section on Wind activation with the eighteen-version check
        - `/Users/anilcan/Code/fluttersdk/wind/CLAUDE.md`, that repository's own definition of done
    - **Done when**:
        - `flutter pub get` succeeds and `grep -c 'watchools_player' pubspec.yaml` and `grep -c 'wakelock_plus' pubspec.yaml` are both greater than zero
        - `! grep -q 'plugin_platform_interface' packages/watchools_player/pubspec.yaml`
        - `dart -e "import 'package:watchools_player/watchools_player.dart';"` style reachability: a throwaway test importing `package:watchools_player/watchools_player.dart` from `test/` compiles, which is what wave 2 depends on
        - the report states which Wind version `pubspec.lock` resolves and whether **that** version in `~/.pub-cache` carries the binding, measured rather than assumed: `grep -c 'ActivateIntent' "$HOME/.pub-cache/hosted/pub.dev/fluttersdk_wind-$(grep -A2 'fluttersdk_wind' pubspec.lock | grep 'version:' | tr -d ' "' | cut -d: -f2)/lib/src/widgets/w_anchor.dart"`. **Expect `0`, and `0` is the passing answer here**, because the publish is a human step this run does not take. This criterion asks for the measurement and the honest reading of it, not for a non-zero count: a version bump made to force this to `1` would be the exact failure the step's Must NOT forbids. Reading the local checkout instead proves nothing either way, since the checkout is where the unpublished commit lives
        - Wind's own gates pass in its tree, per its CLAUDE.md
        - `grep -cF 'fluttersdk_wind: ^1.5.0' pubspec.yaml` is `1`: the constraint is untouched. `-F` is load-bearing, because without it grep reads the `^` as a line anchor mid-pattern and the count is `0` however the file reads
        - the report names the prepared Wind version, states plainly that it is unpublished, and gives the two commands that finish it
    - **QA**: run Wind's own test and analyze commands in its tree and report their output. Then, in watchools, run `flutter pub get` and state which Wind version `pubspec.lock` resolves and whether that version in `~/.pub-cache` contains `ActivateIntent`. Do **not** claim remote activation works in this app until a **published** version carrying the binding is the one resolved.
    - **Must NOT**:
        - Run `pub publish`
        - **Bump `fluttersdk_wind` past a version that is not published yet.** If the publish has not happened, leave the constraint alone and say so; a constraint naming an unpublished version breaks `pub get` for everyone including CI
        - Add a `path:` dependency for any of the sibling ecosystem packages; only `watchools_player`, which lives in this repository, may be a path dependency
        - Widen the Wind change; focus traversal order is a separate gap and a separate release
        - Claim the app has remote activation while `pubspec_overrides.yaml` is what supplies it

### Wave 2

- [x] **Step 4**: Give the plugin a pause it can actually perform
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: a small Swift addition beside an existing read, but it crosses the method-channel boundary in both directions and it is the first write this plugin has ever performed against a live core.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/macos/watchools_player/Sources/watchools_player/WatchoolsPlayerPlugin.swift`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/lib/watchools_player.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/test/watchools_player_test.dart`
    - **Description**: Add `setPaused(bool)` to the engine and a `setPaused` method-channel case, then expose it in Dart. The property already exists and is already **read** every tick: `MpvEngine.swift:363` loops `[("paused", "pause"), ("coreIdle", "core-idle")]` through `mpv_get_property`. Nothing writes it, which is why `PlayerTick.paused` currently reports a state the app cannot set. Write it with `mpv_set_property_string(handle, "pause", value ? "yes" : "no")` or the `MPV_FORMAT_FLAG` equivalent, on the same serial queue every other mpv call is confined to: the pump's own comment records that only the `_async` calls and `mpv_get_time_ns` are marked render-thread safe in `client.h`, and a previous round froze playback by ticking on the main queue. Refuse cleanly when no core is running rather than crashing, matching how `MpvEngine.start()` refuses a second call. Keep it to pause: **no seek, no volume, no speed, no track selection**, because the interface this plan defines promises none of them and a native affordance with no interface member is dead code.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift:363`, the existing read of the same property
        - the same file, the pump's queue confinement comment and `:84-85`'s refusal pattern
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/test/watchools_player_test.dart:22-35`, the channel fake to extend
    - **Done when**:
        - `cd packages/watchools_player && flutter test` passes
        - a test asserts the Dart `setPaused(true)` sends a `setPaused` method call carrying `true`, through the mocked channel
        - `grep -c 'mpv_set_property' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift` is greater than zero
        - `! grep -qE 'mpv_(command|set_property)[^)]*"(seek|volume|speed|aid|sid)"' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift`, anchored to a **call shape** rather than to the bare words. The bare-word form an earlier draft used already matches four existing comment lines in that file, including "cache-speed" at `:376`, so it could never pass and would have blocked the step regardless of the code
    - **QA**: `cd packages/watchools_player && flutter test`, and separately confirm the package still analyzes clean. Assert: the channel receives `setPaused` with the boolean; calling it with no core running returns an error rather than throwing across the boundary; the tick's existing `paused` read is unchanged.
    - **Must NOT**:
        - Call any mpv function off the engine's serial queue
        - Add seek, volume, speed or track selection
        - Change what the tick reads or how often it fires
        - Remove or alter `captureSelf`. It is a compositing-proof spike affordance and it stays on the plugin untouched; the app-side engine simply will not reach it

- [x] **Step 5**: Define the PlaybackEngine contract, and a fake that satisfies it
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-1-cross-layer: this is the contract `CLAUDE.md` requires from the first playback screen because six implementations are coming and retrofitting it means rewriting every screen that touches playback; three of the six (hls.js, Tizen AVPlay, tvOS) cannot even be prototyped on this machine, so the shape has to be right from reasoning rather than from iteration.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/playback/playback_engine.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/playback/fake_playback_engine.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/playback/fake_playback_engine_test.dart`
    - **Description**: Define `PlaybackEngine` as an abstract interface, plus the value types it hands out, plus a `FakePlaybackEngine` that satisfies it without a platform. **Observation-complete, command-minimal.** Commands: `load(Uri source, {String? userAgent})`, `pause()`, `resume()`, `stop()`, `dispose()`. Observation: a `Stream<PlaybackTick>`, a `PlaybackHealth` verdict, and the session identity that stamps every tick. **No `seek`, no `duration`, no member named `position`**, and their absence is the design: live TV has no duration, a sliding window cannot honour a scrub, and the progress a screen shows comes from `GuideClock` plus `Programme` rather than from the engine, so a member called `position` would invite a scrubber to bind to something the window cannot satisfy. `timePos` stays a **liveness signal** feeding health, and name it so nobody mistakes it. **Take the render surface at attach rather than in the command**: the existing `play(int viewId, String url)` puts view identity in every command, which is right for a platform view, wrong for FFI with a render callback, and wrong for hls.js. A surface handed over once at attach fits all three, because every one of them draws into something the framework provides. Reuse `PlaybackHealth` and `StallDetector` from the plugin rather than redefining them; the six members are measured and the 12 s grace is measured, and no production player models `notPresenting` at all. The fake is a **first-class deliverable**, not a test helper: `lib/app/playback/` sits inside the CI coverage denominator, so the fake is what lets the interface and every consumer be tested, and it must be able to emit a scripted tick sequence and drive health through all six members.
    - **References**:
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/librarian-interface-shape.md`, what `video_player_platform_interface` puts in the interface versus leaves out, and why neither Dart player models live
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/explore-existing-player-research.md`, the members the research argues for and the three frozen clocks
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/lib/src/stall_detector.dart:52`, `PlaybackHealth` and the grace
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/lib/watchools_player.dart:174`, `PlayerTick`'s fields and the doc explaining why each is or is not a stall predicate
    - **Done when**:
        - `flutter test test/app/playback/` passes
        - `! grep -qE '^\s*(Future<[^>]*>|void|Duration\??|int\??|double\??)\s+(seek|duration|position)\b' lib/app/playback/playback_engine.dart`, matched on a **declaration shape** rather than on the bare words. The bare-word form collides with this step's own Description, which requires a doc block explaining why the three are absent, so it would forbid the explanation along with the members
        - a test drives `FakePlaybackEngine` through a scripted tick sequence and asserts the health verdict reaches each of the six `PlaybackHealth` members
        - a test asserts a tick from a previous session is not read as the current session's, which is what the session stamp exists for
    - **QA**: `flutter test test/app/playback/`. Assert: the fake satisfies the interface with no platform; a scripted sequence reproduces the measured idle-display shape (a frozen `timePos` with `underrun` false) as `notPresenting` rather than as `stalled`; a frozen `timePos` with `underrun` true crosses into `stalled` only after the grace; a session change resets the freeze anchor.
    - **Must NOT**:
        - Declare `seek`, `duration` or `position`, even as unimplemented members
        - Redefine `PlaybackHealth` or reimplement `StallDetector`
        - Put view identity, a channel, a `Uri` shape or any provider concept in the interface; it takes a `Uri` and knows nothing about Xtream
        - Adopt `plugin_platform_interface` or split into packages; one implementation, and `CLAUDE.md`'s rule is the third concrete caller
        - **Declare any member carrying raw log text.** A stream URL holds the provider password in its path and mpv forwards its log lines verbatim, so an unredacted text channel on this interface would make a leak reachable from every consumer. If the interface needs to surface why playback failed, surface a classified reason rather than a string

### Wave 3

- [x] **Step 6**: Implement the contract over libmpv, and redact everything the native side says
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: this is the boundary every string from the native side crosses, and the verified leak is that an mpv log line carries the provider password in a URL; after this step, which strings reach the app and in what form is decided here and nowhere else.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/playback/mpv_playback_engine.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/playback/mpv_playback_engine_test.dart`
    - **Description**: Implement `PlaybackEngine` over `watchools_player`. The dependency is already declared by the wave-1 dependency step, so this step adds no `pubspec.yaml` line. **Every log line is redacted before it leaves this class**, through `XtreamCredentials.redact`, because `MpvEngine.swift:465` forwards mpv's text verbatim and FFmpeg's reconnect warnings name the URL. That means this engine holds a redactor, which is the one provider concept it may know: pass the function in rather than importing `XtreamCredentials`, so the interface stays provider-agnostic. Subscribe to `WatchoolsPlayer.events` **once** and fan out from an owned controller: `receiveBroadcastStream` sets one message handler per channel name, so a second subscription silently steals the stream from the first and a later cancel tears down both, which is documented behaviour rather than a bug (`EventChannel` class docs: "Identically named channels will interfere with each other's communication"). Drive `StallDetector` from the tick stream and expose its verdict as the health member. **Tear down from Dart, never on a native signal**: `AppKitView` disposal is deferred to the next compositor present and there is no "about to dispose" hook, so `dispose()` must stop the core and drop the subscription itself. `captureSelf` stays on the plugin and **must not be reachable through this class**: it is a compositing-proof spike affordance that captures the app's own window, and it has no place in a product surface.
    - **References**:
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/verification-log.md`, the log-leak chain and the deferred-disposal finding
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/lib/watchools_player.dart:46-58`, the doc explaining why `events` is a field and what a second subscription does
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/packages/watchools_player/lib/src/stall_detector.dart`, the detector to drive
    - **Done when**:
        - `flutter test test/app/playback/mpv_playback_engine_test.dart` passes
        - a test pushes a log event whose text contains a full stream URL through the mocked channel and asserts nothing reaching the engine's consumers contains the password
        - a test asserts two consumers of the engine's own stream both receive every tick, which is the property the single upstream subscription exists to preserve
        - a test asserts `dispose()` cancels the upstream subscription, provable by pushing an event afterwards and asserting no consumer receives it. **This replaces a `! grep -q 'captureSelf'` an earlier draft used**, which targeted a file this step creates and therefore could not fail
    - **QA**: `flutter test test/app/playback/mpv_playback_engine_test.dart` with a mocked method channel, using the pattern at `packages/watchools_player/test/watchools_player_test.dart:22-35`. Assert: a redacted log line loses both secrets; two consumers both see every tick; `dispose()` stops the core and cancels the upstream subscription; a `load` before the surface is attached fails loudly rather than sending a call with no native peer.
    - **Must NOT**:
        - Forward an unredacted log line anywhere, including into an exception or a `Log` call
        - Subscribe to `WatchoolsPlayer.events` more than once
        - Expose `captureSelf` through the interface
        - Import `XtreamCredentials` here; take a redactor function instead
        - Rely on any native signal for teardown

- [x] **Step 7**: Hold the display awake while a core is alive
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: a small dependency and two calls, but the reason it exists is a measurement that was once misdiagnosed, so the doc block carries more than the code does.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/playback/mpv_playback_engine.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/playback/mpv_playback_engine_test.dart`
    - **Description**: Enable `wakelock_plus` while a core is alive, releasing it on `stop()` and `dispose()`. The dependency is already declared by the wave-1 dependency step, so this step adds no `pubspec.yaml` line. This is a correctness concern rather than a comfort one: an idle macOS display **stops libmpv presenting and freezes `time-pos` at the first frame**, which reads exactly like a provider fault, and this project once filed that as a code regression and had to retract it. `wakelock_plus` supports macOS through a real native implementation rather than a stub, and it is the maintained successor to the abandoned `wakelock`. Do **not** reach for `SystemChrome.setEnabledSystemUIMode` or `setPreferredOrientations`: the macOS embedder has **no handler at all** for either, verified by the absence of a `FlutterPlatformPlugin.mm` in its framework source and by zero matches for `SystemChrome` in `FlutterViewController.mm`, so both would be dead code on the target this plan ships. Put the hold in the engine rather than the screen, so it follows the core's lifetime instead of a route's.
    - **References**:
        - `.ac/plans/playback-layer-watchools-playbackengine-interface/research/explore-app-side.md`, the absence of any full-screen affordance in the app and the measured idle-display freeze
        - `.ac/research/player-layer.md:588-621`, the three frozen clocks with their distinguishing signals
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/pubspec.yaml`, the dependency block to extend
    - **Done when**:
        - `flutter test test/app/playback/` passes
        - `! grep -rqE 'setEnabledSystemUIMode|setPreferredOrientations' lib/`. The **`-r` is load-bearing**: without it grep exits 2 with "Is a directory", and `!` turns that failure into a pass, so the criterion would report clean whatever the code said. An earlier draft omitted it
        - a test asserts the hold is released on both `stop()` and `dispose()`, behind an injected seam rather than by calling the real plugin
    - **QA**: `flutter test test/app/playback/`. Assert: enabling happens once per `load` and not once per tick; the hold is released on `stop()` and on `dispose()`; a second `load` without an intervening `stop` does not leak a second hold. Then state plainly that the real display behaviour was **not** verified in this step, because a widget test cannot observe it.
    - **Must NOT**:
        - Call `SystemChrome.setEnabledSystemUIMode` or `setPreferredOrientations`
        - Add or change a `pubspec.yaml` line; the wave-1 dependency step owns all three
        - Hold the wakelock from the screen or the route rather than the engine
        - Leave a hold enabled after the core is gone

### Wave 4

- [x] **Step 8**: A controller that owns the engine and the channel being watched
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: it is the object that turns a channel into a URL, a URL into a load, and a tick stream into something a screen rebuilds on, and every wrong answer it gives is a plausible one. **Rule 5 deliberately does not fire here even though a password-bearing `Uri` passes through**, and the distinction is worth stating so a later reader does not read it as an oversight: steps 1, 2 and 6 each *decide* something about that secret (how the URL is built, what the redactor removes, which native strings reach Dart), while this step only carries an opaque `Uri` from one call to the next. Its Must NOT keeps it that way.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/controllers/playback_controller.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/controllers/playback_controller_test.dart`
    - **Description**: **The four symbols this step depends on, with their files, because a briefing cannot see the steps that created them**: `XtreamStreamUrl.live(...)` in `lib/app/protocol/xtream/xtream_stream_url.dart` returns the `Uri?`; `PlaybackEngine` in `lib/app/playback/playback_engine.dart` is the interface, whose commands are `load(Uri source, {String? userAgent})`, `pause()`, `resume()`, `stop()`, `dispose()` plus a tick stream and a `PlaybackHealth` verdict; `FakePlaybackEngine` in `lib/app/playback/fake_playback_engine.dart` is what every test here injects; and `MpvPlaybackEngine` in `lib/app/playback/mpv_playback_engine.dart` is the implementation the binding resolves at the composition root. `PlaybackHealth` and its six members come from `packages/watchools_player/lib/src/stall_detector.dart`. **The engine arrives by constructor injection** so the fake substitutes without a platform, and the controller never constructs `MpvPlaybackEngine` itself. `PlaybackController` is a `SimpleMagicController` holding the engine, the `Channel` being watched, the current `PlaybackHealth` and the `ProviderFault?` the screen may need to render. It derives the URL through `XtreamStreamUrl.live(...)` from `ProviderSession`'s credentials and account, calls `load`, subscribes to the engine's tick stream and calls `refreshUI()` when the health verdict **changes** rather than on every tick, because a tick arrives twice a second and a rebuild per tick would repaint the overlay 120 times a minute for no visible change. Bind it in `AppServiceProvider.register()` alongside the other two controllers, following the comment there explaining why binding happens in `register()` rather than `boot()`. Expose `play(Channel)`, `togglePause()`, `stop()`, and read-only getters for the health, the channel and the fault. **A channel with a null `streamId` cannot be played**: report it rather than throwing, because a fixture-built channel has none by design and the screen must be able to say so. Follow `GuideController`'s shape for the session subscription and the disposal, including detaching in `onClose()`.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/controllers/guide_controller.dart:91-135`, the constructor seams, the session listener and the notify-on-change discipline
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart:15-40`, where a controller is bound and the comment explaining why there
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/provider_session.dart`, the credentials, the account and the fault the controller reads
    - **Done when**:
        - `flutter test test/app/controllers/playback_controller_test.dart` passes
        - a test asserts `play(channel)` loads exactly the `Uri` `XtreamStreamUrl.live(...)` produces for that credential and channel, using `FakePlaybackEngine` and asserting on the whole `Uri` it was asked to load rather than on a substring of it
        - a test asserts a channel with a null `streamId` produces a reported reason rather than a throw and rather than a load
        - a test asserts the controller notifies on a health **change** and not on every tick, by pushing several ticks at one health and counting notifications
    - **QA**: `flutter test test/app/controllers/playback_controller_test.dart` with `FakePlaybackEngine` and a faked session. Assert: the loaded `Uri` is the derived live URL; `togglePause()` reaches the engine; a null `streamId` is refused with a reason; ten ticks at one health produce one notification; `onClose()` detaches from both the engine and the session.
    - **Must NOT**:
        - Call `WatchoolsPlayer` or any plugin API directly; the engine interface is the only route
        - Construct `MpvPlaybackEngine` here; the engine arrives by constructor injection so a test can pass the fake
        - Store, log, interpolate or expose the derived `Uri` as a `String` anywhere, including in an exception message or a `Log` call. It carries the provider password in its path, and this step's whole claim to `rule-none` is that it passes the `Uri` through opaquely. Use `XtreamCredentials.describe(uri)` if a diagnostic needs to name it
        - Rebuild on every tick
        - Perform I/O from a getter
        - Throw on a channel that cannot be played

- [x] **Step 9**: Wire the connection-cap predicate at the composition root
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: two lines, but they are the two lines that stop a catalogue refresh from killing the stream the user is watching, and the direction the dependency points matters more than the code.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/provider_session_test.dart`
    - **Description**: `ProviderSession` already takes `bool Function()? isPlaying` and defaults it to "never playing", and `AppServiceProvider.register()` currently constructs it with nothing. Pass a closure that reads the playback controller's engine health. Do this **at the composition root**, not by having either layer import the other: the protocol layer must not depend on playback, and playback must not ask the protocol layer for permission, because a recovery `loadfile` competing with a refresh for the single connection slot is exactly the deadlock the predicate exists to prevent. The measured account's `max_connections` is **1**, and a second concurrent variant killed the first at 5.79 s, so this is the difference between a refresh being safe and a refresh evicting the viewer. Note the ordering constraint already documented in that file: controllers are bound in `register()` before `ProviderSession`, and a closure defers the read to call time, which is what makes the order irrelevant.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/provider_session.dart`, the `isPlaying` parameter and the doc explaining why it defaults to never
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart:30-40`, the binding site and the ordering comment
        - `.ac/research/player-layer.md:206-228`, the connection budget and the eviction measurement
    - **Done when**:
        - `flutter test test/app/provider/provider_session_test.dart` passes with its existing assertions unchanged
        - a test asserts a session whose predicate reports playing sends **no** request on `refresh()`, provable by `assertSentCount(0)`, which is the existing gate now reached through the real wiring
        - `! grep -qE "^import .*/playback/" lib/app/provider/provider_session.dart`, matched on an **import shape** rather than on the bare word, which is what the criterion actually means: the protocol layer must not depend on the playback layer. The bare-word form was tried and it fails on a doc block that states the independence in prose, which is the same collision this plan corrected four times elsewhere. An import is also the only thing that would create the dependency
    - **QA**: `flutter test test/app/provider/`. Assert: with the predicate true, `refresh()` sends nothing; with it false, the refresh proceeds; the predicate is read at call time rather than captured at construction, provable by flipping it between two calls.
    - **Must NOT**:
        - Import anything from `lib/app/playback/` into `lib/app/provider/`
        - Import `ProviderSession` into the playback layer
        - Make the predicate a stored bool rather than a closure

### Wave 5

- [x] **Step 10**: The playback screen, as an overlay above the platform view
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: it follows an overlay pattern this app has already proven three times, but gestures do not reach Flutter through a macOS platform view, so every control's position and every focus decision is load-bearing in a way a browse screen's is not.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/playback_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/resources/views/playback_view.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/ui/layouts/playback_layout_test.dart`
    - **Description**: Two files, following the split the three existing screens already use: a `MagicStatefulView` in `lib/resources/views/` that the route resolves, and the layout it renders in `lib/ui/layouts/`. `lib/routes/app.dart:19-21` resolves `GuideView()`, `LibraryView()` and `TitleView()`, and `lib/resources/views/` holds exactly those three, so a route with no view there has nothing to resolve. That directory is also **excluded from the CI coverage denominator**, which is the right home for the thin mounting half. The layout itself is a full-bleed `Stack` with `WatchoolsPlayerView` as the base, then **`Scrim.bottom`** and, for the top chrome, `Scrim.flat` or a raw gradient in the same shape: **there is no `Scrim.top`**, the four that exist are `bottom`, `left`, `flat` and `ambient` (`lib/ui/components/scrim/scrim.dart:21`), and adding a fifth would mean editing that component, which is not in this step's scope. Then positioned Flutter controls. **Every control lives in Flutter above the view**, because Flutter's gesture arena does not hand gestures to a macOS platform view at all, which the plugin's own widget documents by setting no hit-test behaviour. Follow `curtain_layout.dart:113-157` exactly: `Positioned` plus `Align` to loosen the tight width a `Positioned` with both `left` and `right` hands down. Controls for this pass: a back affordance, a pause and resume toggle, the channel name and its current programme, and a health indication. `DESIGN.md:441-442` sets the one rule this surface already had: the chrome "is transparent over video and must never use a scrim heavier than 40 percent, which is the ceiling Plex holds". Render a fault through the existing `ProviderNotice` rather than inventing a second fault surface, and render **all four** members: `unreachable`, `expired`, `throttled` and `evicted`. `evicted` is the one this surface needs most, because it is what a `max_connections: 1` account produces when another device takes the slot, and it is the only fault whose retry costs that other device its stream. **Show `notPresenting` differently from `stalled`**: the first is the display having gone idle and recovers on wake, the second may never recover, and they are the same frozen clock from the engine's point of view. Every control is a `WAnchor` carrying `focus:ring-2 focus:ring-focus-ring`, which is universal in this app's eleven other files, and note in a doc block that remote activation depends on step 3's published Wind.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/curtain_layout.dart:113-157`, the exact overlay shape to follow
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/DESIGN.md:441-442`, the 40 percent scrim ceiling
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/scrim/scrim.dart:3-20`, why the scrims are raw gradients and where the workaround lives
        - `.ac/research/design-doctrine.md:250-254`, focus is a ring and a lift and never collapses with selection
    - **Done when**:
        - `flutter test test/ui/layouts/playback_layout_test.dart` passes at both desktop and mobile sizes
        - a test asserts the pause control reaches the controller, through a faked engine
        - a test asserts `notPresenting` and `stalled` render distinguishably
        - a test asserts a fault renders `ProviderNotice` and the back affordance is still present
        - a test per `ProviderFault` member, four in total, asserts the notice renders
        - `! grep -qE 'Colors\.|Color\(0x' lib/ui/layouts/playback_layout.dart`
        - `grep -c 'PlaybackView' lib/resources/views/playback_view.dart` is greater than zero, so step 11 has something to route to
    - **QA**: `flutter test test/ui/layouts/playback_layout_test.dart` via `pumpScreen()` with explicit desktop and mobile sizes and `setUp(WindParser.clearCache)`. Assert: the platform view is the stack base; controls sit above it; tapping pause reaches the controller; a fault shows the notice without hiding the way back; `notPresenting` and `stalled` differ on screen. Do **not** assert overflow; the substituted square font makes it meaningless.
    - **Must NOT**:
        - Put a control inside the platform view or rely on a gesture reaching it
        - Use a raw colour, a raw `TextStyle` or a hand-written gutter number
        - Exceed the 40 percent scrim ceiling
        - Render a scrubber, a seek bar or a duration; the engine exposes none of the three
        - Collapse `notPresenting` into `stalled`

- [x] **Step 11**: Register the route, and make a tap reach it
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-1-cross-layer: it threads one gesture through a component, two layouts, a controller and the router, and the router has a documented failure mode where a route registered in the wrong place is silently absent rather than an error.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/routes/app.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/now_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/time_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/ui/layouts/playback_route_test.dart`
    - **Description**: Register a playback route and wire the two live layouts to reach it. **What the route resolves to is `PlaybackView`, in `lib/resources/views/playback_view.dart`, which step 10 creates**; this step imports it and does not write it, and `lib/resources/views/` is where the other three route targets live (`guide_view.dart`, `library_view.dart`, `title_view.dart`), each a `MagicStatefulView` subclass. **The route must be declared where `registerAppRoutes()` already runs, from `RouteServiceProvider.boot()`**: `MagicRouter` locks its table the first time `MaterialApp` reads `routerConfig`, and `magic_router.dart:122-126` throws `Cannot add routes after the router has been built` afterwards, so a route added anywhere later is silently absent. Give it a Turkish title matching the other three. The tap: `now_layout.dart:398` currently passes `onTap: () => controller.selectChannel(channel)` and the hero's play affordance at `:327` is `onTap: () {}`, an empty callback. Selection must stay selection, because the hero exists to preview; **the play affordance is what navigates**, and the tile's own tap keeps selecting. **`TimeLayout` has no hero and no empty play callback**: it carries `selectChannel` (`time_layout.dart:362`) and `selectProgramme` (`:507`), so decide there what navigates and say so in the doc block. A programme cell already carries a channel, so the honest answer is probably a long press or a dedicated affordance rather than repurposing either existing tap; if neither fits without moving something that owns focus or scroll, leave `TimeLayout` alone and report that `Zaman` reaches playback only through `Şimdi` for now. Pass the channel to the route in whatever way this router supports, and note that `/baslik` is still unparameterised despite `CLAUDE.md` saying it becomes `/baslik/:id` with the Xtream client, so if a path parameter is awkward here that is a known gap rather than a thing to solve twice.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/route_service_provider.dart:24`, `:41-44`, the registration site and the comment recording why it has to be there
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/routes/app.dart:19-21`, the three existing declarations and their titles
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/now_layout.dart:327`, `:398`, the empty play callback and the tile's selecting tap
    - **Done when**:
        - `flutter test test/ui/layouts/` passes
        - a test asserts the playback route resolves rather than falling through to `/`, which is the shape a route registered too late takes
        - a test asserts the hero's play affordance navigates and the tile's tap still only selects
        - `grep -c 'PlaybackView' lib/routes/app.dart` is greater than zero: the route names the view step 10 wrote rather than a placeholder
        - the report states what `Zaman` does, either the affordance it gained or that it was deliberately left reaching playback only through `Şimdi`
    - **QA**: `flutter test test/ui/layouts/`. Assert: the route is registered and resolves; the play affordance navigates; the tile continues to select without navigating; the toolbar and the category strip are untouched in both layouts. Reach the route in a manual check with `dusk:navigate --route` rather than a browser URL, because web deep links land on `/` in this app.
    - **Must NOT**:
        - Register the route anywhere other than where `registerAppRoutes()` runs
        - Change what the tile's tap does
        - Move the toolbar or the category strip
        - Rename or reparameterise `/baslik` in this step

### Wave 6

- [x] **Step 12**: Measure whether the panel re-mints a token per request
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**: The recovery design turns on one unmeasured fact. A lapsed token stalls libmpv with no event, and `player-layer.md:156-180` concludes that **no reconnect option survives it** and recovery therefore belongs to the app layer via a fresh `loadfile`. What is not established is whether a fresh `loadfile` of the **stable** URL is enough: the mock mints a new token on every 302 (`server.mjs:1111-1118`), and if a real panel does the same then recovery needs no `player_api.php` call at all and the protocol layer owes the engine nothing. Measure it against the mock first, which is free and settles the shape. **Do not spend a real-provider request on this**: the standing constraint is few, logged, never repeated, and the real-panel question is recorded in `## Deferred Ideas` with the exact two-request procedure. Also correct the record while here: the 300 s TTL that has been quoted as a provider fact is the mock's own constant, and the panel figure is about forty minutes (`catalogue.mjs:58-68`).
    - **Commands**:
        - `node tool/xtream-mock/server.mjs & sleep 2`
        - `curl -s -o /dev/null -D - 'http://127.0.0.1:3300/live/demo/demo/10001.ts' | grep -i '^location'`
        - `curl -s -o /dev/null -D - 'http://127.0.0.1:3300/live/demo/demo/10001.ts' | grep -i '^location'`
        - `lsof -ti :3300 | xargs -r kill`
    - **Done when**:
        - both `Location` headers are captured in the evidence file
        - the evidence states plainly whether the two tokens differ, and therefore whether a bare `loadfile` of the stable URL is a sufficient recovery against this fixture
        - the evidence records that the real-panel behaviour is **unmeasured** and names the deferred procedure
    - **QA**: read the two `Location` values. If they differ, a `loadfile` of the stable URL re-mints and recovery is engine-local against the mock. If they match, the token is cached and recovery needs the API. Report which, and do not generalise a mock result to the real panel.
    - **Evidence**: `.ac/plans/playback-layer-watchools-playbackengine-interface/evidence/12-token-remint.txt`
    - **Must NOT**:
        - Send any request to a real provider
        - Present a mock result as a provider fact
        - Curl port 3399. That is `verify.mjs`'s own port; `server.mjs:40` defaults to **3300**, and an earlier draft of this step curled 3399 and would have had every request refused
        - Leave the panel bound; a second run fails with `EADDRINUSE`

- [x] **Step 13**: Run every gate the project enforces
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**: The full local gate set before the pull request, in the order CI runs it. The lock check runs **first**, because that is the only moment the committed file is still the committed file: this plan adds two dependencies (`watchools_player` by path, `wakelock_plus` hosted) and, per step 3, leaves `fluttersdk_wind: ^1.5.0` untouched because the Wind release is prepared but unpublished, so `pubspec.lock` legitimately changes and the committed version must be the **hosted-only** one, regenerated with `pubspec_overrides.yaml` moved aside per `.gitignore:73`. Coverage is the gate most likely to fail on this plan: `lib/app/playback/` is inside the denominator and its macOS implementation cannot run under `flutter test`, which is exactly why `FakePlaybackEngine` is a deliverable.
    - **Commands**:
        - `git diff --stat`
        - `paths=$(grep -c 'source: path' pubspec.lock || true); relative=$(grep -c 'relative: true' pubspec.lock || true); echo "$paths $relative"`
        - `flutter analyze --fatal-infos --fatal-warnings`
        - `dart format --output=none --set-exit-if-changed lib test`
        - `flutter test --coverage`
        - `cd packages/watchools_player && flutter test`
        - `node tool/xtream-mock/verify.mjs`
    - **Done when**:
        - `flutter analyze` reports no issues
        - `dart format` reports nothing changed
        - `flutter test --coverage` is green and the printed `hit/found` clears 90% over the CI exclusion list
        - the plugin's own suite is green
        - `node tool/xtream-mock/verify.mjs` prints "All checks passed."
        - the two lock counts are **equal**: `grep -c 'source: path' pubspec.lock` matches `grep -c 'relative: true' pubspec.lock`. **Not zero.** `watchools_player` lives under `packages/` in this repository, so it is a legitimate path dependency and pub records it as `relative: true`; the CI gate (`.github/workflows/ci.yml:47-67`) compares the two counts for exactly that reason, and its own comment says so. A criterion of zero would fail on a correct lock, which is what an earlier draft of this step asserted
    - **QA**: run each command and capture its output. Every one exits 0. Compute coverage with the CI step's own script (`.github/workflows/ci.yml:113-145`) rather than trusting a green test run, because the denominator moves when a test imports something new.
    - **Evidence**: `.ac/plans/playback-layer-watchools-playbackengine-interface/evidence/13-gates.txt`
    - **Must NOT**:
        - Commit a `pubspec.lock` carrying sibling paths
        - Lower the coverage floor to pass; a floor moves in the same pull request as the tests that earned it
        - Skip the plugin's own suite because it is a separate package; step 4 changed it

## Risks Accepted

**All four interview decisions were locked on their recommended option without an answer.** The
questions went out with research-grounded recommendations and no reply arrived within the wait, so
each below is a **default rather than a choice**. Any of them is cheap to revisit before execution;
`interview-log.md` carries the full reasoning for each.

1. **The interface promises no seek, no duration and no position**, and their absence is deliberate
   rather than deferred. If a VOD screen ever needs a scrubber, the interface gains members and
   every implementation gains work; that is the cost of drawing the line at live.
2. **The interface lives in the app, not in a federated package split.** Federation is the right end
   state for six implementations and flutter/packages does practise it, but there is one
   implementation today and `CLAUDE.md`'s rule is the third concrete caller. The accepted cost is
   that `lib/app/playback/` sits inside the CI coverage denominator, so the macOS implementation's
   untestable lines count against the 90% floor.
3. **Remote activation depends on an unpublished Wind commit**, and step 3 prepares the release but
   **stops before publishing**, because pub.dev is irreversible and outward-facing. Until it is
   published and the constraint bumped, the player's overlay is mouse and keyboard only. Developing
   against `pubspec_overrides.yaml` hides this completely.
4. **Live only.** VOD is out because `container_extension` is consumed at parse into an uppercased
   display fact (`title_item.dart:254`), so a VOD URL is not derivable from persisted state without
   a real field, a store column and a migration.

Five more, from the research rather than from the interview:

5. **`notPresenting` and `stalled` are the same frozen clock from below**, and starvation and a
   lapsed token are **identical** on every instantaneous signal, differing only in whether they
   recover. The 12 s grace is what separates them, and it was derived from the **mock's** starvation
   window, which `player-layer.md:606` flags itself: "Whether a real panel starves the same way is
   unmeasured; the mock's window size is a fixture choice."
6. **Flutter 3.47 makes Impeller the default on macOS**, and `flutter/flutter#180831` ("Impeller has
   noticeably worse performance than Skia when using Platform View / Texture") is **open**. Three
   other Impeller-on-macOS regressions from the 3.47 cycle are closed. If the platform view
   underperforms, `--no-enable-impeller` is the named contingency rather than a redesign.
7. **A stale-token 509 maps to none of `ProviderFault`'s four members and gets no fifth.** All four
   describe something the user can act on, and a stale token is fixed automatically. It stays
   engine-internal with a bounded attempt count, surfacing `unreachable` only after the bound is
   spent.
8. **Hot restart is the riskiest development action here.** It disposes every platform view
   **synchronously** through `FlutterPlatformViewController.reset()` while the native process and
   anything the Swift side holds outside `_platformViews` survives untouched, and there is no
   lifecycle hook telling a plugin it is happening (`flutter/flutter#10437`, open since 2017).
9. **The plugin is macOS only** and its manifest still carries the scaffold's description with
   `plugin.platforms` naming one platform. This plan does not widen it; five more targets are five
   more plans.

## Cross-Project Observations

Two findings in siblings. Each is that repository's work, with its own pull request, its own
CLAUDE.md and its own CI, per `.claude/rules/workflow.md`. Only the first is in this plan's scope.

1. **In scope as step 3.** Wind's `WAnchor` gained `ActivateIntent` and `ButtonActivateIntent`
   bindings in `92f20f5`, which answers `enter`, `numpadEnter`, `space`, `gameButtonA` and `select`,
   the last being the D-pad centre on Android TV. **It is unreleased**: eighteen published versions
   including 1.5.2 have zero occurrences. Any consumer constraining `^1.5.0` therefore ships without
   remote activation while a local override shows it working.
2. **Out of scope, and the larger gap.** Wind has **no focus traversal policy** at all: no
   `FocusTraversalPolicy`, `FocusTraversalOrder` or `FocusTraversalGroup` anywhere in its source, so
   traversal follows Flutter's default reading order, which is right for a browser and wrong for a
   D-pad. And `platform_service.dart:41-48` returns `(String, bool)` with no form-factor axis, so
   Android TV reads as `('android', true)` and every `mobile:` variant fires on a 55 inch screen.
   Together these mean a genuinely remote-drivable TV surface needs Wind work beyond step 3, and
   this plan's player is not it.

Both go into `.ac/research/ecosystem-defects.md` and, per `CLAUDE.md`, get reported out loud in the
reply carrying this work rather than only in a file.

## Deferred Ideas

- **The tokenised URL defeats both redaction paths, and step 12 measured it.** The 302's target
  carries a base64 token whose payload is literally `username:password:issuedAt`
  (`evidence/12-token-remint.txt`). `describe(Uri)` replaces a path segment only when the segment
  **equals** a secret, and `redact(String)` looks for the raw secret plus three encodings, none of
  which is the base64 blob. Reachable rather than theoretical: mpv follows the redirect, FFmpeg's
  reconnect warning names the URL it is retrying, and that warning is the only signal a token is
  lapsing so it cannot be switched off. The fix is **not** a fourth hand-written spelling: it is to
  recognise a base64-looking path segment whose decoding contains either secret, which covers a
  token shape this app has not seen yet as well as the one it has. Deferred rather than done because
  step 12 is a measurement step and this is code, and because the real panel's token shape is
  itself unmeasured.

- **The variant ladder.** Already deferred once when the protocol layer was chosen over it, and
  deliberately not designed out here: it reads one `demuxer-cache-state` node, its tier 0 is
  `end-file` reason in {0, 4}, and its tiers 1 and 2 are both marked **unverified** because the
  harness had no playback clock. Four guards are already specified
  (`player-layer.md:623-653`). Note that a buffer retune per variant would need a native setter or
  a core restart, because none of the plugin's mpv options can change after start.
- **The real-panel token measurement.** Step 12 settles the shape against the mock. The real
  question is two logged requests, never repeated, per the standing constraint: request the same
  stable stream URL twice against the real panel and compare the `Location` tokens. If it re-mints
  per request, recovery is engine-local and needs no `player_api.php` call.
- **VOD and series playback**, which needs a real `containerExtension` field on `TitleItem`, a
  column in `CatalogueStore`, and the `movie` and `series` URL shapes. The measured container
  distribution is mp4 54.0% and mkv 45.6%, and the mkv share is why libmpv is primary.
- **Catch-up.** Two of five conventions exist in the mock, both the `xc` spelling, duration in
  minutes, and the start interpreted in **server local time** with the offset coming from
  `server_info.timestamp_now` minus device time (`stack-decisions.md:279-281`). `tv_archive` is set
  on 20 of 2,976 channels, so it buys 0.7% of the line-up, and `Channel.catchupDays` already carries
  the window so no migration follows.
- **The panel clock offset**, which is the same `server_info.timestamp_now` figure. It is already
  captured on `XtreamAccount` as `panelTimestamp` and `panelTime` and read by **nothing**, and
  `Programme.fromXtream` currently resolves panel-local strings in the **device** zone, so a panel in
  another timezone shifts the whole schedule uniformly. The mock is already configured with a
  180-minute offset to catch it.
- **Track selection and subtitles.** The research already designed the type:
  `Track {id, kind, lang, codec, title, isDefault, isForced, isExternal}` plus `select(kind, id?)`
  and a `preferredLanguages` list reapplied after every `loadfile` (`player-layer.md:515-527`).
  Subtitles arrive in five shapes and `dvb_teletext` needs `--enable-libzvbi`.
- **Post-ready video-track verification.** `player-layer.md:69-75` requires it: the real provider
  serves an HEVC channel that reports ready, advances position, plays audio and **has no video
  track**, with no error anywhere. `PlayerState.hasPicture` is the existing partial answer and the
  contract should eventually demand it.
- **Focus traversal for the player overlay**, which needs Wind work (see Cross-Project 2).
- **Federating the plugin** into a platform-interface package plus per-platform implementations,
  which is the right shape at the second or third implementation rather than the first.
- **`/baslik/:id`.** Still unparameterised despite `CLAUDE.md` saying it becomes so with the Xtream
  client, which landed in `68b1868` without it.
- **Writing the 115-tick healthy-playback run into the record.** It was genuinely measured in an
  earlier session and never written down, so it cannot be cited; the recorded figure is 106 and it
  documents the idle-display freeze instead. Either it goes into `player-layer.md` with its numbers
  or it stops being quoted.
- **A project-wide redaction lint.** Step 1 forbids emitting a URL string and step 2 gives
  `redact(String)`, but nothing enforces either outside those two files.
