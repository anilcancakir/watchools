# The app side: reuse, routing, UI and testing (ac:explore x4)

Four briefs merged: what to reuse, how a screen is reached, what the overlay composes, and what can
honestly be tested.

## Reuse directly

| What | Where | For |
|---|---|---|
| `PlayProgress` | `lib/ui/components/play_progress/play_progress.dart:20` | the position bar; two tones, anchors to a bottom edge |
| `Scrim` | `lib/ui/components/scrim/scrim.dart:21` | four prebuilt ramps: `bottom`, `left`, `flat`, `ambient` |
| `FavouriteButton` | `lib/ui/components/favourite_button/favourite_button.dart:17` | star toggle; `shape: 'bare'` is the closest thing to an icon-only button |
| `StatusBadge` | `lib/ui/components/status_badge/` | live / recording / catch-up badges |
| `FactChip` | `lib/ui/components/fact_chip/` | resolution, codec, audio facts |
| `ChannelMark` | `lib/ui/components/channel_mark/` | logo with derived initials when absent |
| `ProviderNotice` | `lib/ui/components/provider_notice/provider_notice.dart:44` | the four faults, already rendering, already tested |
| `StallDetector` / `PlaybackHealth` | `packages/watchools_player/lib/src/stall_detector.dart:52` | the health verdict, already validated against 115 live ticks |
| `PlayerTick` / `PlayerEvent` / `PlayerState` | `packages/watchools_player/lib/watchools_player.dart:253` | the telemetry the detector reads |
| `XtreamCredentials` + `describe(Uri)` | `lib/app/protocol/xtream/xtream_credentials.dart:23` | the base URL, the per-provider user agent, and the only sanctioned way to name a provider URL in a diagnostic |
| `XtreamAccount` | `lib/app/protocol/xtream/xtream_account.dart:26` | `allowedOutputFormats`, `maxConnections`, `active` |
| `ProviderSession` | `lib/app/provider/provider_session.dart` | credentials, catalogue, fault, the clock, and the `isPlaying` gate |
| `GuideController` pattern | `lib/app/controllers/guide_controller.dart:57` | a `SimpleMagicController` that subscribes to the session and invalidates caches; the playback controller follows it |

**No icon-only button exists** and **Wind has no scrims**: all four ramps in `scrim.dart` are raw
`LinearGradient`s with the dark half of `bg-surface` (`#0E0F11`) hand-copied in, because Wind has
no custom gradient stops. `scrim.dart:3-20` records that and points at
`.ac/research/ecosystem-defects.md`. A player's scrims fit the existing workaround unchanged.

## Absent, and each is a step

- **No stream URL builder at all.**
- **No playback screen, no playback controller, no engine interface.**
- **No `Duration` label formatter.** `Programme._hhmm` is private and formats minutes-since-midnight
  rather than an elapsed duration.
- **No full-screen affordances anywhere**: no `SystemChrome`, no `setEnabledSystemUIMode`, no
  `setPreferredOrientations`, no wakelock package. This is not a nicety here: the project measured
  that **an idle display stops libmpv presenting and freezes `time-pos` at the first frame**, and
  misdiagnosed it as a code regression before retracting it.

## Routing, and it has one legal registration site

`RouteServiceProvider.boot()` (`lib/app/providers/route_service_provider.dart:24`) calls
`registerAppRoutes()` before `MagicRouter` locks its table. The lock happens when `MaterialApp`
first reads `routerConfig`, and `magic_router.dart:122-126` throws a `StateError` on `addRoute`
after that:

> `Cannot add routes after the router has been built. Register all routes before accessing routerConfig.`

Existing routes: `/` (`Canlı`), `/kutuphane` (`Kütüphane`), `/baslik` (`Başlık`), `/preview`. No
middleware anywhere; `kernel.dart:33-49` is entirely commented out.

**`/baslik` is still unparameterised** (`lib/routes/app.dart:21`), despite `CLAUDE.md` saying it
becomes `/baslik/:id` "with the Xtream client", which has now landed.

## What a tap does today: nothing

1. `live_tile.dart:76` gives `WAnchor(onTap: onTap)`.
2. `now_layout.dart:398` passes `onTap: () => controller.selectChannel(channel)`.
3. `guide_controller.dart:548-551` sets `_channel`, recomputes `_programme`, calls `refreshUI()`.

No navigation. And the hero's own play affordance at `now_layout.dart:327` is `onTap: () {}`, an
empty callback. So "nothing is playable" is not a missing engine; it is a missing everything
between the tile and the engine.

## Doctrine that applies to a player

`DESIGN.md:441-442`, the only statement touching playback:

> "The player chrome does not exist yet. When it does it is transparent over video and must never
> use a scrim heavier than 40 percent, which is the ceiling Plex holds and the reason their artwork
> stays legible underneath."

`design-doctrine.md:184-187`, rule 11: "Chrome recedes when content arrives." And `:250-254`,
rule 5: "Focus is a lift and a ring, and it never collapses with selection. A TV remote moves focus
without changing selection, so the two must be visually distinct."

## The focus situation, taking CLAUDE.md's four claims in turn

| CLAUDE.md claim | Verdict |
|---|---|
| No D-pad activation in `WAnchor` | **Refuted locally, true as published.** See `verification-log.md`: the local checkout binds `ActivateIntent` at `w_anchor.dart:132-135`, but all 18 published versions including `1.5.2` have zero occurrences, and the app constrains `^1.5.0`. The fix is one unreleased commit, `92f20f5`. |
| No focus traversal policy | **Verified.** No `FocusTraversalPolicy`, `FocusTraversalOrder` or `FocusTraversalGroup` anywhere in Wind. Traversal follows Flutter's default reading order, which is right for a browser and wrong for a D-pad. |
| No TV form-factor axis | **Verified.** `platform_service.dart:41-48` returns `(String, bool)` where the bool is `isMobile`, so Android TV reads `('android', true)` and every `mobile:` variant fires on a 55 inch screen. |
| Every layout writes `focus:ring-2 focus:ring-focus-ring` | **Verified**, in 11 files. |

So the honest position: the visual half is universal, activation is fixed but unpublished, and
traversal order is genuinely missing in both. For a player whose every control is overlay chrome
driven by a remote, that ordering gap is the sharp one.

## The closest existing overlay pattern

`curtain_layout.dart:113-157` stacks `Artwork`, then `Scrim.left`, then `Scrim.bottom`, then
`Positioned` controls and a bottom `PlayProgress`, with `Align` inside a `Positioned` carrying both
`left` and `right` to loosen the tight width. Proven on three detail screens. **A playback screen is
the same shape with the platform view as the stack base instead of `Artwork`.**

## Testing, and what genuinely cannot be tested

**The plugin's own channel fake** (`packages/watchools_player/test/watchools_player_test.dart:22-35`)
is the pattern to copy:

```dart
final TestDefaultBinaryMessenger messenger =
    TestDefaultBinaryMessenger.instance.defaultBinaryMessenger;
messenger.setMockMethodCallHandler(const MethodChannel(channel), (call) async => null);
```

It then pushes events with `messenger.handlePlatformMessage` and `StandardMethodCodec`, and asserts
that **two** independent subscribers both receive every event, which is the property the
`static final` stream exists to guarantee. `stall_detector_test.dart` is pure Dart over hand-built
ticks, no platform calls, seven cases taken from measured shapes.

Nothing else in the repository fakes a method channel or a platform view. magic's testing barrel
offers `FakeAuthManager`, `FakeCacheManager`, `FakeVaultService`, `FakeLogManager` and
`FakeNetworkDriver`, none of which touch channels.

**Testable without an engine**: native-to-Dart serialisation, tick parsing and health transitions,
controller state and disposal, widget composition around an engine, routing and lifecycle.

**Not testable without an engine**: actual playback and decode, real event timing, whether a video
track exists (the measured HEVC-with-no-video case), buffering against real network conditions,
codec support per platform, platform-specific errors including the 509-as-EOF shape, rendering into
a platform view, and present timing.

**The coverage consequence.** The CI floor is 90% over a denominator excluding only
`lib/resources/views/`, `lib/app/providers/`, `lib/app/kernel.dart` and `lib/routes/app.dart`. An
engine implementation that cannot run under `flutter test` will read as uncovered lines in that
denominator, so where the interface and its implementations live is a coverage decision as well as
an architecture one.

**What a dusk walk can do**: assert semantics labels, viewport bounds, overflow markers on
interactive widgets, the exception store, and capture screenshots. **What it cannot**: key-by-key
focus transitions, because `fill_search` writes a whole term in one call. `_lib.sh` records five
ways an earlier version of a gate passed unconditionally, including an uppercase `OVERFLOW` refuted
against dusk's lowercase output.
