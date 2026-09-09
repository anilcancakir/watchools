# Interview log

Plan: `playback-layer-watchools-playbackengine-interface`. Auto mode: false.
Branch `playback-layer`, off `origin/master` at `68b1868`.

## Stage 1-2 synthesis

**Codebase state**: `disciplined`. Consistent style, configs present, a 90% coverage floor enforced
in CI over a denominator excluding only the generated scaffold, and doc blocks that carry rationale
rather than restating signatures. Match patterns strictly.

**Conventions** (ten, for the plan's `## Codebase Conventions`): `snake_case.dart` files with
`UpperCamelCase` types and `lowerCamelCase` members, tests mirroring the source path; no fallback
`try/catch` that swallows; doc blocks everywhere carrying the contract, the failure mode, the unit
and the measurement that decided a number; strict explicit types, no `dynamic` unless a wire
boundary forces it; nested by role under `lib/app/`, no barrel exports there, a UI component folder
being the exception with `index.dart` plus `*.recipe.dart` and `*.preview.dart` **dotted**; relative
imports within `lib/`; no path aliases; `lib/config/wind_theme.g.dart`, `lib/app/_plugins.g.dart`
and `lib/_previews.g.dart` generated and never edited; `wrapWithTheme()` for a leaf and
`pumpScreen()` for a screen, with `setUp(WindParser.clearCache)` mandatory and `.env` overridden
rather than defaulted; **TDD yes**, failing test first, infrastructure present.

**What exists today**

| Need | Status |
|---|---|
| A working libmpv renderer in a Flutter platform view | Exists, macOS only, proven in PR #16 |
| Telemetry the health model needs | Exists. `PlayerTick` carries `monotonicNs`, `timePos`, `paused`, `coreIdle`, `forwardBytes`, `inputRate`, `underrun`, `demuxerIdle` |
| A health verdict | Exists. `StallDetector` plus six-member `PlaybackHealth`, 12 s grace |
| Credentials, base URL, per-provider user agent | Exists. `XtreamCredentials`, plus `describe(Uri)` as the only sanctioned way to name a provider URL |
| `stream_id` on a channel, persisted | Exists, from PR #25, including in the store |
| The overlay pattern | Exists. `curtain_layout.dart:113-157` is the shape |
| Fault vocabulary and its panel | Exists. Four `ProviderFault` members, all four rendering |
| **A `PlaybackEngine` interface** | **Absent** |
| **Any stream URL builder** | **Absent** |
| **Any playback control: pause, seek, volume, tracks, duration, live offset** | **Absent in the native side too** |
| **The app depending on the plugin at all** | **Absent** |
| **Keeping the display awake** | **Absent, and it is a correctness concern here** |
| Focus traversal order for a remote | Absent in Wind |

**The delta**: the interface, the URL builder, the screen, the route, the plugin dependency, one
native control (pause), and the display-awake hold.

**Codebase fit**: High for the app half, and the reuse map is unusually strong. Low for the native
half, because the plugin is explicitly a spike.

**Effort**: Large. Cross-module, plus a native change, plus a sibling publish.

## Risks research produced

1. **The plugin has no controls at all.** Verified: `mpv_command` appears once in four Swift files
   and issues only `loadfile`; `"pause"` appears once and only as a read; `seek` appears zero
   times. So `PlayerTick.paused` reports a state nothing can set, and a screen with a pause button
   cannot pause without new Swift.
2. **One core at a time**, and that is aligned rather than limiting: the measured account's
   `max_connections` is 1, and a second concurrent variant killed the first at 5.79 s.
3. **Stalled and ended are not distinguishable from below.** A lapsed token produces no `endFile`
   at all and freezes `demuxer-cache-duration` at a healthy-looking value. Independently, no
   production player (ExoPlayer, AVPlayer, media_kit, video_player) distinguishes them structurally
   either; only hls.js has a transient stall signal, and even it has no stalled state.
4. **Starvation and a lapsed token present identically**: both freeze `time-pos` with
   `underrun: true`, `demuxerIdle: false` and `fw-bytes: 0`. They differ only in whether they
   recover, so no instantaneous reading separates them.
5. **An idle display freezes `time-pos` at the first frame** and reads exactly like a provider
   fault. This was once misdiagnosed as a code regression and retracted.
6. **Remote activation ships absent.** Wind's `ActivateIntent` binding exists only in an
   unpublished commit; all 18 published versions have none, and the app constrains `^1.5.0`.
7. **Flutter 3.47 makes Impeller the default on macOS**, and `flutter/flutter#180831`
   ("Impeller has noticeably worse performance than Skia when using Platform View / Texture")
   is open. Three other Impeller-on-macOS regressions from the 3.47 cycle are closed.
8. **`AppKitView` disposal is deferred by design** to the next compositor present
   (`FlutterPlatformViewController.mm:64-75`), while a hot restart disposes every view
   **synchronously** through `reset()`. So teardown must be driven from Dart's `State.dispose()`
   and never inferred from a native signal. There is no "about to dispose" hook.
9. **`SystemChrome.setEnabledSystemUIMode` and `setPreferredOrientations` are dead code on
   macOS**: the embedder has no handler at all, not merely a permissive no-op.
10. **VOD cannot be played from persisted state.** `container_extension` is consumed at parse into
    an uppercased display fact in `facts`, so recovering a URL from it means lowercasing display
    data, which is the wrong direction. Live is derivable from cached state today; VOD needs a real
    field and a store column.
11. **`plugin_platform_interface` may be deprecated.** Its own README says the Flutter team is
    considering replacing it with Dart 3's `base`, with no decision made. The plugin declares it
    and uses none of it.

## Corrections to my own premises, before the interview

Both are in `research/verification-log.md` with the checks. Recorded here because they change what
is worth asking:

- **The 300 s token TTL is our mock's constant.** The measured panel figure is about forty minutes
  (`catalogue.mjs:58-68`). Nothing should be sized against 300 s.
- **"115 live ticks" has no source in this repository.** The recorded figure is 106 and it
  documents the idle-display freeze, not a healthy-playback validation. The 115-tick run was real
  but never written down, so it cannot be cited.

## Decisions put to the user

Four, all genuinely preference or scope rather than answerable from code. Recorded as they resolve.

## Stage 3 outcome: four defaults, not four answers

The four questions went out with a recommended option each, grounded in the research above. **No
answer arrived within the wait**, so each is locked on its recommendation and recorded as a
**default rather than a choice**. All four are listed in the plan's `## Risks Accepted` so a later
reader can see which were chosen and which were merely not contradicted. Any of them is cheap to
revisit before execution.

### D1. Interface scope: observation-complete, command-minimal

`attach`, `load`, `pause`, `resume`, `stop`, `dispose`, plus a tick stream, a health verdict and the
session identity. **No `seek`, no `duration`, no member named `position`.**

**Why**: the reading half is implementable today with no native work, because `PlayerTick` already
carries exactly what `StallDetector` consumes. The writing half is `load` and `stop`, and `pause` is
a `mpv_set_property_string` beside the existing read. So the cut lands where the evidence is rather
than where a guess about the second platform would put it.

**Why no seek or duration**: live TV has neither. The sliding window cannot honour a scrub, the
progress bar comes from `GuideClock` plus `Programme` rather than from the engine, and a member
named `position` invites a scrubber to bind to it. `timePos` stays a liveness signal feeding
`health`, not a position. Both are absent rather than stubbed, because a stub is a promise.

### D2. Location: `lib/app/playback/`, and drop `plugin_platform_interface`

The interface in the app, the plugin as one implementation of it.

**Why not federation**: it is the right end state for six implementations and flutter/packages does
practise it, but there is one implementation today and `CLAUDE.md`'s rule is the third concrete
caller. Standing up three packages now breaks that rule to buy an extensibility nobody is using
yet, and moving to federation later is mechanical.

**Why drop the dependency**: it is declared and unused, and its own README says the Flutter team is
considering deprecating it in favour of Dart 3's `base`, with no decision made. Carrying an unused
dependency whose future is openly uncertain is worse than either using it or removing it.

**Accepted cost**: `lib/app/playback/` sits inside the CI coverage denominator, so the macOS
implementation's untestable lines count against the 90% floor. Mitigated by keeping the
implementation thin and the interface plus its fake fully covered, and by noting that a real fake
engine is a first-class deliverable rather than a test helper.

### D3. Wind: publish it, as a step in this plan

Release the sibling and bump to `^1.5.3` here.

**Why**: `.claude/rules/workflow.md` already requires a publish plus a constraint bump after a
sibling change, and `92f20f5` is exactly that change sitting unreleased. It is the same shape as
`magic#151` in the previous plan. Developing against the overrides and testing on macOS with a
mouse would hide the absence completely, which is the failure mode this project has been burned by.

**What it does not fix**: focus **traversal** order, which is absent in Wind published and local
alike. So full remote drivability still waits on a second Wind change, and this plan does not
claim otherwise.

### D4. Scope: live only

**Why**: `stream_id` is already on `Channel` and already persisted in `CatalogueStore`, so a live
URL is derivable from cached state today with no protocol-layer change. Live is also the harder
half of the product, and the half the health model was built for.

**Why VOD is out**: `container_extension` is consumed at parse into an **uppercased display fact**
inside `facts` (`title_item.dart:254`), and `StreamFacts` is deliberately shape-matched display
data. Recovering a URL from it would mean lowercasing display data back into a path, which is the
wrong direction. VOD needs a real `containerExtension` field on `TitleItem` and a column in the
store, which is a protocol-layer change and a migration, so it belongs in its own plan.

## Stage 3.5 trigger evaluation

Trigger 1 (security-critical surface) **fires**: the stream URL carries the provider password in its
path, and the verification log records that an mpv log line forwards it verbatim into Dart.

**No second oracle spawned, deliberately.** The Stage 1 oracle already pressure-tested this exact
architecture with the locked shape available to it, returned seven premise verdicts including two
refutations of my own figures, and its findings are folded into the decisions above. Spawning
another on the same surface would spend an Opus pass to re-read what is already in
`research/verification-log.md`. The security finding it did not raise, the log-line leak, I found
and verified myself, and it becomes a first-class constraint in the plan rather than a finding to
triage.

Triggers 2, 3 and 4 do not fire: no composable framework chain was adopted, the one genuinely
undecided question (`plugin_platform_interface`) was settled against the package's own README
rather than by weighing two contradictory sources, and nothing here migrates or drops data.

## Stage 5.5 outcome: one advisory reviewer pass, 28 findings, 27 applied and 1 refuted

`ac:plan-reviewer` returned 13 CRITICAL and 15 IMPORTANT. I verified the three claims I was least
sure of before acting on any of them, and all three held: routes resolve `MagicStatefulView`
subclasses in `lib/resources/views/`, `server.mjs:40` is
`const PORT = Number(process.env['PORT'] ?? 3300)` so the step 12 curls to 3399 would every one
have been refused, and the CI lock gate at `ci.yml:47-67` compares the two counts rather than
requiring zero, with its own comment saying a package under `packages/` is a legitimate path
dependency that pub records as relative.

**Refuted, one finding.** The reviewer reported `now_layout.dart:327` as an off-by-one that should
read `:326`. `grep -n 'onTap: () {}' lib/ui/layouts/now_layout.dart` returns `327`; `:326` is the
`child: WAnchor(` line above it. The plan's citation was already correct and stands unchanged. This
is the fourth time in two plans that a report's line anchor was the thing that failed, and it is
why the rule is to open the file rather than to trust two reports agreeing.

**The seven fixes that changed what a worker will do**, as opposed to wording:

1. **Step 13's lock criterion was actively wrong.** I carried "zero `source: path`" over from the
   protocol plan into a plan that *adds* a path dependency, so the gate would have failed on
   correct work. Now: the two counts must be **equal**, explicitly not zero.
2. **Step 12 curled port 3399**, which nothing listens on. Now 3300, with the mistake recorded in
   its Must NOT so a worker does not reintroduce it.
3. **Four gates could not fail.** Step 4's grep matched its own explanatory comment (anchored to
   `mpv_(command|set_property)[^)]*"(seek|volume|speed|aid|sid)"`), step 7's lacked `-r` so it
   exited 2 on a directory and `!` read that as a pass, step 5's and step 1's matched bare words the
   Description itself requires. Step 6's `captureSelf` grep was unfalsifiable and became a
   dispose-cancels-subscription test instead.
4. **Step 3 contradicted itself about the bump.** It said "cut the release, then bump the constraint"
   and also "stop before publishing", and its Done-when required the **resolved** Wind to carry the
   binding, which no unpublished version can. Now the step leaves `^1.5.0` alone, the criterion asks
   for the measurement and states that **`0` is the passing answer**, and a new criterion asserts the
   constraint is untouched (with `-F`, because `grep '^1.5.0'` reads the caret as an anchor and
   returns 0 however the file reads).
5. **Waves 3 to 6 are now declared ordered tracks** in the exact vocabulary `ac:execute` recognises
   ("must run in sequence"), because it spawns a wave's steps in parallel by default and treats a
   declared ordered track as its one exception. Wave 5 needed it too and I had missed it: step 11
   imports the `PlaybackView` step 10 creates.
6. **Steps 8 and 11 named no symbols.** A worker sees one step, so "step 1's builder" is unusable.
   `XtreamStreamUrl.live(...)` is now fixed in step 1 with a grep asserting it, and step 8 lists all
   four symbols it imports with their files. Step 11 names `PlaybackView` and its path.
7. **Step 11's `TimeLayout` target did not exist.** That file has no hero and no empty callback,
   only `selectChannel` (`:362`) and `selectProgramme` (`:507`), so the step now says what to decide
   there and explicitly permits leaving `Zaman` reaching playback through `Şimdi` alone, reported
   rather than silently skipped.

Also applied: step 3 rewritten to own all three `pubspec.yaml` lines in wave 1 so wave 2 can import
`PlaybackHealth` at all (and `pubspec.yaml` removed from steps 6 and 7), step 10 given its file and
corrected off `Scrim.top`, which does not exist, plus a test per `ProviderFault` member, the forward
pointers in steps 4 and 5 inlined, step 8 given a note on why rule 5 does not fire on it and a
Must NOT keeping it that way, the Research Summary's brief count corrected against the six files
that exist, and the Reuse Map's `catalogue_store.dart:143` given its full path.

`plan-check` clean after the last edit: 13 steps, 0 errors, 0 warnings.
