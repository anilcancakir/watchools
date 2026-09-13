# Interview log

Plan: `playback-lifecycle-teardown`. Auto mode: true.
Worktree `playback-lifecycle`, branch `worktree-playback-lifecycle`, off `origin/master` at `3e74043`.
Source: issue #27.

## Stage 1-2 synthesis

**Codebase state**: `disciplined`. Same as the two plans before it: a 90 percent CI coverage floor, doc
blocks that carry the contract and the measurement, no linter suppression, and the house rule that a
test is not written until it has been proved to fail with the fix removed.

**What exists today**

| Need | Status |
|---|---|
| A wakelock seam | Exists, `mpv_playback_engine.dart:151`, guarded by `_awake` at `:162` |
| A "release the connection" command | Exists, `PlaybackEngine.stop` (`playback_engine.dart:204-209`) |
| A teardown that keeps the surface | Exists, `mpv_playback_engine.dart:333-344` |
| A connection gate the app already trusts | Exists, `holdsConnection` (`playback_controller.dart:255`) |
| A recovery designed for a lapsed token | Exists, `load` replaces by design (`playback_engine.dart:169-174`) |
| **Any lifecycle observer** | **Absent.** One doc comment records the absence and nothing else |
| **Any test that drives a lifecycle transition** | **Absent anywhere in the suite** |
| **Anything reacting to `PlaybackHealth.stalled`** | **Absent.** One UI label, no recovery |

**Effort**: Small to medium. One new observer, one wiring point, and the tests that carry it.

## The four findings that shape every decision below

1. **macOS never sends `paused` or `detached`.** Verified in the engine source at tag `3.47.4`:
   the macOS embedder maps occlusion to `resumed` / `inactive` / `hidden` only
   (`FlutterEngine.mm:1644-1701`), and `platform_dispatcher.dart:2358-2446` states `paused` "is only
   entered on iOS and Android". So reacting to `paused` is, by construction, reacting to mobile
   backgrounding with no platform check written anywhere.

2. **`StallDetector` cannot tell a lapsed token from a healthy wait.** Measured and already recorded:
   both freeze `time-pos` with `underrun: true`, `demuxerIdle: false` and `fw-bytes: 0`, and differ
   only in whether they recover (`.ac/research/player-layer.md:591-613`). The enum's `starving` versus
   `stalled` split is a time cutoff for exactly that reason.

3. **No mpv reconnect option survives a lapsed token**, and the repo says so in its own words:
   "Recovery belongs to us" (`player-layer.md:156-178`). `PlaybackEngine.load`'s doc block was written
   for this: "the app's recovery from a lapsed provider token is a fresh open".

4. **Both reference players default to stopping on background**, and continuing is opt-in engineering
   with a platform toll: Android needs a `MediaSessionService` plus a notification plus a Play Console
   declaration with a demo video, and iOS needs the audio background mode under Guideline 2.5.4.
   OTT Navigator, the closest comparable, ties background and PiP streams directly to the provider's
   connection pool and recommends disabling them to avoid being blocked.

## Risks research produced

1. **`engine.dispose()` has no call site in `lib/`.** Verified by grep. So an observer registered in
   the engine and removed in `dispose` is never removed in production. Harmless for a process-lived
   singleton and a real hazard in tests, where a leaked observer on the shared binding outlives its
   own test. `WidgetsBinding._observers` holds a strong reference (`binding.dart:861-892`).
2. **The engine is built lazily and is one per process.** `PlaybackController` holds a FACTORY
   (`playback_controller.dart:96-108`) and the doc block explains why: constructing the engine during
   `AppServiceProvider.register()` makes every test that boots the providers throw "Binding has not
   yet been initialized", measured. So the observer registers on first play, not at boot.
3. **`detach()` and `stop()` both clear `_channel`**, which is half the playback gate
   (`playback_controller.dart:279-314`). Neither was written for a resumable cycle, so a background
   teardown that reuses one of them throws away the state a resume would need.
4. **The re-mint measurement is mock-only.** `evidence/12-token-remint.txt` shows a stable URL
   yielding a fresh token on every `302`, which would make a bare reload sufficient recovery, and it
   is explicitly flagged as fixture-only with the real panel unmeasured.
5. **A macOS occlusion regression was fixed only in 3.47.0** (flutter#155977, PR #188772). The pinned
   SDK carries the fix; an older engine can fail to re-send `resumed` after Mission Control.

## Decisions put to the user

Three, all product or preference rather than answerable from code. TDD is not asked: `CLAUDE.md`
settles it.

## Stage 3 outcome: two questions asked, both declined, decisions taken with the assumption stated

The user twice asked to clarify rather than answering, and the substance of both replies was the same
request: keep playing as a small video on Android and iPhone, keep playing as audio on macOS, and make
it configurable. That is a product answer to a question I had framed as stop-versus-continue, and it
deserves a straight answer rather than a third round of options, so the decisions below are mine with
the reasoning written down and each one cheap to reverse.

**What the user asked for, against what is actually available.**

| Asked | Reality |
|---|---|
| Small video on Android | Possible, and needs no engine change: Android PiP shrinks the whole Activity and libmpv keeps drawing. Blocked only because no Android target is wired yet |
| Small video on iPhone | **Not possible with this engine.** iOS PiP needs `AVPictureInPictureController`, which takes an `AVPlayerLayer` or an `AVSampleBufferDisplayLayer`; libmpv produces neither, and media_kit attempted the `CMSampleBuffer` bridge twice without landing it (`.ac/research/player-layer.md:415-437`) |
| Audio continues on macOS | **Already true.** A macOS app is not backgrounded the way a mobile app is; the process keeps running when the window is occluded, so audio continues today with no code at all |
| User-configurable | Buildable now, and the right shape |

### D1. Three options ship now, including the one no platform can do yet

**Revised after a third user message, which is the one that settled it**: "pipi de dahil et bu plana
desteklemiyorsa bile kullanıcı ayarlayabilsin, arka plana atınca ses olarak çalmaya devam et ve durdur
destekleri olsun, yani her platform için mümkün olduğunca."

So the setting carries all three from the start:

| Choice | What the Dart side does on `paused` | What it still needs from a platform |
|---|---|---|
| `stop` | stops the core, releases the connection and the wakelock | nothing, complete today |
| `audio` | leaves the core running, releases the wakelock only | iOS audio background mode, Android media foreground service |
| `pictureInPicture` | leaves the core running, releases the wakelock only | Android `PictureInPictureParams`; on iOS an AVFoundation engine, which libmpv cannot feed |

**The degradation is stated on screen rather than hidden**, which is the one condition attached to
this. An option the user can pick that silently does something else is the failure the resolver's
own https limitation taught this project to write down: the settings screen says which platform can
honour which choice, and the doc block carries why. Without that line, `pictureInPicture` on iOS
would read as a feature and behave as `audio`.

Two things make this shape cheap rather than speculative. The enum is the storage, so Android PiP
(roadmap stage 3) and iOS PiP (stage 6) each become an arm rather than a migration off a boolean. And
the Dart half of `audio` and `pictureInPicture` is identical today, one branch, because both mean
"do not stop the core" and the difference between them is entirely platform work that does not exist
yet on any target.

### D2. The trigger is `paused`, which the user did answer

Chosen by the user. It also happens to be the technically clean answer: `platform_dispatcher.dart:2358-2446`
states `paused` "is only entered on iOS and Android", so reacting to it IS reacting to mobile
backgrounding, with no platform check written anywhere and macOS untouched by construction.

### D3. Resume does not reload automatically

Not answered; taken on the evidence. Stopping on background exists to free the account's single
connection. Reloading automatically on return takes that slot back and evicts whichever device picked
it up in the meantime, which is the exact harm the feature was built to avoid. So the screen comes back
stopped and the user starts it, which is also the only honest option given that a lapsed token is
indistinguishable from a healthy wait (`.ac/research/player-layer.md:591-613`) and `load` is a full
fresh open by design (`playback_engine.dart:169-174`).

### D4. macOS is out of scope, deliberately

No behaviour change there at all. It already stops the core on a route pop
(`WatchoolsPlayerPlugin.swift:186-191`), it never delivers `paused`, and its process keeps running when
occluded, which is what the user wants there anyway.

## Stage 5.5: the reviewer round, and the one finding that changed the design

One `ac:plan-reviewer` pass, thorough, briefed to open every anchor rather than sample. It returned 11
findings it called critical and 8 important. I opened the load-bearing ones myself before accepting any of
them; every one I checked held.

**The finding that changed the design, and it was mine to miss.** The plan had the picker ride
`ProviderSetupFacade.submit`, copying the resolver. But `adopt`'s `credentials.save()`
(`provider_session.dart:384`) is the only writer in the app, `submit` reaches it only past
`if (_fault != null) return;` (`provider_setup_controller.dart:346-350`), and the three credential fields
start empty on every open of the screen (`provider_settings_layout.dart:170-176`). So a user could only have
changed this setting by retyping their whole credential against a live, unexpired panel, re-sending their
password over plaintext HTTP. A user whose subscription had lapsed could not have turned off the thing that
keeps their connection held. Step 3 now adds `ProviderSession.setBackgroundPlayback`, a handshake-free writer,
and step 4's picker calls it on change.

**Five more that would have failed the run outright.**

1. `XtreamCredentials` has no `fromJson` and no public `toJson`. The round trip is `load()` (`:174-192`) and
   the private `_toJson()` (`:418-424`). The plan named both wrong in step 1's Description and QA.
2. `_FakeProvider` (`test/ui/layouts/provider_settings_layout_test.dart:21`) implements `ProviderSetupFacade`,
   so any new interface member turns step 3's own `flutter analyze` red until that double answers it. The test
   file was in no step's Files.
3. `AppLifecycleListener` seeds `_lifecycleState` from the binding at construction
   (`app_lifecycle_listener.dart:78`), and `postTest()` runs only inside `testWidgets`
   (`flutter_test/lib/src/widget_tester.dart:183`). `mpv_playback_engine_test.dart` has no `testWidgets` in it
   at all, so the binding's lifecycle persists across cases and the SECOND lifecycle test would have thrown
   `Invalid state transition`. The harness now walks the binding back up in an `addTearDown`.
4. `ResolverSetting.storedValue` returns `String?`, null for the default (`resolver_setting.dart:76-90`). The
   plan had asked for a non-nullable `String`, which would have written `"background_playback": "stop"` into
   every credential blob ever saved, including for users who never touch the feature, and made the
   `'key': ?value` omission the same step asked for unreachable.
5. `git status --short` never prints ignored paths, so step 6's gate on `pubspec_overrides.yaml`, `.env` and
   `.env.local` could not fail. Replaced with `git ls-files --error-unmatch`.

**The layering correction.** `BackgroundPlayback` was going into `lib/app/playback/`, which
`app_service_provider.dart:114-115` forbids the setup controller from importing. It goes in `lib/app/models/`
beside `ProviderFault`, the existing shared-enum precedent. The cost is recorded in step 1: `lib/app/playback/`
imports nothing outside itself today, and step 2 gives it one dependency-free enum import.

**One finding not taken.** The reviewer asked for `Tier` and `Why this tier` on step 6. The template omits both
for a `verification` step and `plan-check` passes without them, so they stay omitted.

Also corrected without argument: eight anchors that were off by a few lines or pointed at the wrong doc block
(`mpv_playback_engine.dart:154` was the `_awake` flag, not the redactor; the facade's `submit` is declared at
`:67-73`, not `:298`; `wrapWithTheme` is the wrong harness for a screen, `pumpScreen` is what that file uses).
