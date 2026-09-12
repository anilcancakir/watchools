# Plan: playback-lifecycle-teardown

**Steps**: 6
**Waves**: 6
**Codebase State**: disciplined
**Auto mode**: true
**Generated**: 2026-09-12

## Research Summary

Four `ac:explore` briefs and two `ac:librarian` briefs, archived under `research/`. Every claim that
moved a decision was re-read at source by the main thread and recorded in `research/verification-log.md`.

**Issue #27 in one line**: backgrounding does not dispose a `State`, so on the Android and iOS targets
that are coming, the libmpv core, the account's single connection slot and the wakelock all survive the
user pressing Home. Nothing in this repository observes app lifecycle at all.

**Four findings shape every step.**

1. **macOS never sends `paused`.** Verified in the engine at tag `3.47.4`: the macOS embedder maps
   occlusion to `resumed` / `inactive` / `hidden` only (`FlutterEngine.mm:1644-1701`), and
   `platform_dispatcher.dart:2358-2446` states `paused` "is only entered on iOS and Android". So
   reacting to `paused` IS reacting to mobile backgrounding, with no platform check written anywhere
   and macOS untouched by construction.

2. **The lifecycle chain is asserted in debug**, `detached <-> paused <-> hidden <-> inactive <-> resumed`
   (`app_lifecycle_listener.dart:222-268`). A test that jumps straight from `resumed` to `paused`
   trips that assert. Every test here walks the chain.

3. **A lapsed token is indistinguishable from a healthy wait.** Measured and recorded: both freeze
   `time-pos` with `underrun: true`, `demuxerIdle: false`, `fw-bytes: 0`
   (`.ac/research/player-layer.md:591-613`), which is why `starving` versus `stalled` is a time cutoff.
   No mpv reconnect option survives one either: "Recovery belongs to us" (`player-layer.md:156-178`).
   So "carry on where it left off" is not an available behaviour, only "stop" or "open again".

4. **Both reference players default to stopping on background.** Media3 releases in `onStop()` and
   background continuation requires a separate `MediaSessionService`; AVPlayer needs the audio
   background mode plus an `AVAudioSession` category. OTT Navigator, the closest comparable, ties
   background and PiP streams to the provider's connection pool and recommends disabling them.

**What the user asked for, and what is actually available.** The user asked for a small video on
Android and iPhone, audio on macOS, and a user setting. Android PiP is possible with no engine change
and is blocked only because no Android target is wired. iOS PiP is **not possible with libmpv**: it
needs `AVPictureInPictureController`, which takes an `AVPlayerLayer` or `AVSampleBufferDisplayLayer`,
and media_kit attempted the `CMSampleBuffer` bridge twice without landing it
(`.ac/research/player-layer.md:415-437`). macOS audio already continues, because a macOS process is not
suspended when its window is occluded. The user then asked for all three options anyway, configurable
even where unsupported, which this plan delivers with the degradation stated on screen.

## Codebase Conventions

1. `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` members. Tests mirror the source
   path exactly.
2. **No fallback catch that swallows.** Catch the specific exception, map it into a vocabulary the UI
   renders, and say in the doc block that the handling is deliberate.
3. **Doc blocks carry the contract, the failure mode, the unit, and the measurement that decided a
   number.** A doc block restating the parameter list is a defect here.
4. Strict explicit types. `dynamic` only where a wire boundary forces it.
5. Nested by role under `lib/app/`, no barrel exports there. A UI component folder is the exception,
   with `index.dart` plus dotted `*.recipe.dart` and `*.preview.dart`.
6. Relative imports within `lib/`. No path aliases.
7. Generated and never edited: `lib/config/wind_theme.g.dart`, `lib/app/_plugins.g.dart`,
   `lib/_previews.g.dart`, and every platform plugin registrant.
8. **Wind owns styling.** `className` strings and `W`-prefixed widgets only. Never `Colors.*`, a raw
   `Color(0x...)`, or a bare `TextStyle`. Colours come from the semantic aliases in the generated theme.
9. Test mount discipline: `pumpScreen` (`test/support/screen.dart:44`) for a screen, `wrapWithTheme`
   (`test/support/wind_test_app.dart:34`) for a leaf, `setUp(WindParser.clearCache)` mandatory on any
   widget test, `MagicApp.reset(); Magic.flush();` for container tests, plus `MagicTest.init()` and an
   in-memory `sqlite3` connection where the database is touched
   (`test/app/controllers/playback_controller_test.dart:100-117` is the worked example).
10. **TDD, and one rule beyond it.** Failing test first, and a test is not written until it has been
    proved to fail with the fix removed: break the source on purpose, watch it go red, put it back.

No linter or type-checker suppression, anywhere, for any reason.

## Reuse Map

| Need | Reuse | Anchor |
|---|---|---|
| Releasing the connection | `PlaybackEngine.stop`, which exists for exactly this | `lib/app/playback/playback_engine.dart:204-209` |
| A teardown that keeps the surface | `MpvPlaybackEngine.stop` | `lib/app/playback/mpv_playback_engine.dart:333-344` |
| The wakelock, and its idempotence guard | `_toggleWakelock` and `_awake` | `mpv_playback_engine.dart:151`, `:162`, `:272-287` |
| A durable table, created idempotently | `CatalogueStore.migrate`'s `CREATE TABLE IF NOT EXISTS` over `DB.statement` | `lib/app/provider/catalogue_store.dart:139-165` |
| A settings field, end to end | the resolver picker added in #32 | model, facade, form, all on `/saglayici` |
| The three-option picker widget | `WFormSelect<T>` plus `SelectOption<T>` | `provider_settings_layout.dart`'s resolver field |
| Stating a platform limit on screen | the resolver's own scope sentence | `provider_settings_layout.dart`'s `_resolverScope` |
| Driving a lifecycle transition in a test | `handleAppLifecycleStateChanged` on the binding | `flutter/lib/src/widgets/binding.dart:1329-1334`, public, fans out to every observer |
| A platform-free engine double | `FakePlaybackEngine` | `lib/app/playback/fake_playback_engine.dart:48` |
| Mounting the settings screen in a test | `pumpScreen`, which every case in that file already uses | `test/support/screen.dart:44`, used at `provider_settings_layout_test.dart:98` onward |
| A shared enum every layer reads | `ProviderFault` | `lib/app/models/provider_fault.dart` |

**Built fresh, because nothing exists**: any app-preference storage at all. `Storage` is a file
facade (`put(path, contents)`), `Session` is request-scoped flash, and `Cache` is flushable by
`Cache.flush()`, which would silently reset a user's setting. A tiny key-value table over
`DB.statement`, following `CatalogueStore`'s shape, is the durable option that matches what this app
already does.

## Work Objectives

1. **Stop holding what nobody is watching.** On mobile backgrounding, release the core, the account's
   single connection slot and the wakelock, according to a setting.
2. **Give the user the choice, including the one no platform can honour yet**, and say on screen which
   platform can honour which.
3. **Do not surprise the user on return.** Coming back does not silently retake a connection slot
   another device may have picked up.
4. **Change nothing on macOS.**

## Tier Calibration

`quick` for a single-file mechanical edit. `junior` for one to three files of ordinary logic.
`junior-high` where the coupling or the context depth is borderline. `senior` for new infrastructure
or an edge case that has already bitten somebody.

One step is `senior`: the lifecycle listener itself, because a never-removed observer is a strong
reference the binding holds forever (`binding.dart:861-892`) and `MpvPlaybackEngine.dispose()` has no
call site in `lib/` at all, so the removal path this step writes is one nothing exercises in
production and everything exercises in tests.

## Execution Strategy

Six waves, one step each, **in sequence**. Each imports what the one before it created: the enum and
the store before the listener that reads them, the listener before the wiring, the wiring before the
screen that drives it.

Every step that touches Dart runs `flutter analyze --fatal-infos --fatal-warnings` and the tests it
names before it reports done.

### Dependency Notes

**Step 1 produces `BackgroundPlayback` and `AppSettingsStore`; step 2 consumes both.** The listener
branches on the enum and reads it through the store, so a run that stops after step 1 has a setting
nothing acts on.

**Step 2 produces the listener; step 3 is what makes it read a real setting.** Step 2 takes the
current choice as an injected callback so it is testable with no database; step 3 closes that callback
over the store at the composition root. Neither is useful alone.

**Step 4 is the only step a user can see.** Steps 1 to 3 are complete and invisible without it.

## Steps

### Wave 1: the value type

- [x] **Step 1**: Add the `BackgroundPlayback` enum and carry it on the credential
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-4-detail: two files of ordinary value-type work, but the round trip has an exact
      precedent to copy field for field, and the precedent already handles the case that breaks it.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/models/background_playback.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/protocol/xtream/xtream_credentials.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/app/protocol/xtream/xtream_credentials_test.dart
    - **Description**:
      Create `lib/app/models/background_playback.dart` holding one enum with three members and a parser.

      ```dart
      enum BackgroundPlayback { stop, audio, pictureInPicture }
      ```

      **`lib/app/models/` rather than `lib/app/playback/`, and the choice is load-bearing.** Four layers read
      this enum: the engine branches on it, `ProviderSession` stores it, the setup facade exposes it and the
      screen renders it. `lib/app/playback/` cannot be its home, because
      `app_service_provider.dart:114-115` states the rule in the codebase's own words, that
      `ProviderSetupController` "must not import the playback layer". `lib/app/models/` is where
      `ProviderFault` already lives as exactly this thing, an enum every layer reads.

      The cost, and state it in the file's doc block rather than letting a reader find it: `lib/app/playback/`
      currently imports nothing outside itself (`fake_playback_engine.dart` and `mpv_playback_engine.dart` each
      import only `playback_engine.dart`), and step 2 gives it one internal import. That is a deliberate
      relaxation of a real isolation, bounded to a dependency-free enum carrying no provider concept.

      `stop` is the default and the first member. Give it a `static BackgroundPlayback parse(String? stored)`
      returning `stop` for null, for an unknown name, and for a wrong type. The "an unreadable value means the
      safe default, never a throw" contract is `ResolverSetting.parse`'s, at
      `lib/app/network/resolver_setting.dart:52-75`, and the reason is the same: this is a setting nobody is
      forced to touch, so a value written by a newer build must not make an older one throw on startup.

      **`String? get storedValue`, returning null for `stop`.** Not a non-nullable `String`. `ResolverSetting.
      storedValue` is `String?` and returns null for its own default (`resolver_setting.dart:76-90`), and that
      is what makes the `'key': ?value` omission below reachable at all: a non-nullable getter would write
      `"background_playback": "stop"` into every credential blob a user ever saves, including every user who
      never touches this feature.

      Then add `final String? backgroundPlayback;` to `XtreamCredentials`, beside `resolver` at
      `xtream_credentials.dart:88`. A raw `String?` rather than the enum, and that is the same layering rule
      from the other side: `lib/app/protocol/xtream/` holds no app concept, and `resolver` is already a raw
      string for exactly this reason (`xtream_credentials.dart:80-88` plus `provider_settings_layout.dart:656`,
      which passes `resolverSetting.storedValue`).

      **Six places in that file change with it**, all visible by grepping `resolver` there:

      1. the field (`:80-88`)
      2. the constructor parameter (`:103`)
      3. `load()` (`:174-192`), the static that reads the vault blob back. There is no `fromJson`; the
         deserialiser is `load()` and it MUST use the existing `_optionalString` helper rather than a cast, the
         way `resolver` does at `:190`, because a bare cast throws `TypeError` past both catches at
         `provider_session.dart:494`/`:498`
      4. `==` (`:380`)
      5. `hashCode` (`:383`)
      6. `_toJson()` (`:418-424`), which is **private** and reached through `save()` at `:107`. Use the
         `'key': ?value` null-aware entry at `:423` so an unset setting is omitted from the blob rather than
         written as null.

      **`toString()` at `:411` is the one that differs from `resolver`.** The resolver is redacted there because
      a user-typed DoH URL can carry anything; a `BackgroundPlayback` name is a closed set of three constants
      and carries nothing about the user, so it is written literally. Say that in the field's doc block, because
      the line above it redacts and a later reader will otherwise read the difference as an oversight.

      Tests go in the existing `xtream_credentials_test.dart`, following the vault round trip already at
      `:156-162`: `Vault.fake()`, save a record carrying `'audio'`, `load()` it back and assert the field
      survived. Plus a `load()` given an `int` where the string should be (the `_optionalString` path), equality,
      a `toString()` assertion that the value IS present in the output, and the key-absent test the resolver
      already has at `:164-171`, asserting the payload carries no `background_playback` key for `stop`.
    - **References**:
        - lib/app/network/resolver_setting.dart:52-75, the parse contract: an unreadable value is the default, never a throw
        - lib/app/network/resolver_setting.dart:76-90, `String? get storedValue` returning null for the default
        - lib/app/models/provider_fault.dart, the shared-enum precedent and where this file goes
        - lib/app/protocol/xtream/xtream_credentials.dart:80-88, the field to sit beside, and its doc-block depth
        - lib/app/protocol/xtream/xtream_credentials.dart:174-192, `load()`, and `_optionalString` rather than a cast
        - lib/app/protocol/xtream/xtream_credentials.dart:418-424, the private `_toJson()` and the `'key': ?value` omission shape
        - test/app/protocol/xtream/xtream_credentials_test.dart:156-171, the vault round trip and the key-absent assertion to copy
    - **Done when**:
        - `rg -c 'backgroundPlayback' lib/app/protocol/xtream/xtream_credentials.dart` returns at least 6
        - `flutter test test/app/protocol/xtream/xtream_credentials_test.dart` is green
        - `flutter analyze --fatal-infos --fatal-warnings lib/app/models/background_playback.dart lib/app/protocol/xtream/xtream_credentials.dart` is clean
    - **QA**: `flutter test test/app/protocol/xtream/xtream_credentials_test.dart`. Then prove each new test fails
      with its fix removed: delete `backgroundPlayback` from `load()` and watch the round-trip test go red,
      restore it; make `storedValue` non-nullable and watch the key-absent test go red, restore it. A test not
      proved to fail is not written (CLAUDE.md).
    - **Must NOT**:
        - Put the enum in `lib/app/playback/`
        - Give `storedValue` a non-nullable return type
        - Write a `fromJson` or a public `toJson`; the round trip is `load()` and the private `_toJson()`
        - Redact `backgroundPlayback` in `toString()`
        - Touch `HostResolver`, `ResolverSetting` or any resolver behaviour

### Wave 2: the observer

- [x] **Step 2**: Observe the lifecycle on the engine and branch on the choice
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-3-codebase-state: a never-removed observer is a strong reference the binding holds
      for the process's life (`binding.dart:861-892`), `MpvPlaybackEngine.dispose()` has no call site in `lib/`
      at all, and the target platform does not exist yet, so every assurance this step gives comes from tests
      rather than from running it, in a file whose own harness has three traps in it.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/playback/mpv_playback_engine.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/app/playback/mpv_playback_engine_test.dart
    - **Description**:
      Give `MpvPlaybackEngine` an `AppLifecycleListener` that fires on `paused` and branches on the current
      `BackgroundPlayback`.

      **Take the choice as an injected callback, not a stored value**: add
      `final BackgroundPlayback Function() _backgroundPlayback;` as a constructor parameter defaulting to
      `() => BackgroundPlayback.stop`, alongside the two seams the constructor already takes at
      `mpv_playback_engine.dart:167`. This is the shape the composition root already uses three times over for
      exactly this reason (the redactor at `mpv_playback_engine.dart:73`, the connection gate and the sign-out
      stop at `app_service_provider.dart:81`/`:123`): a closure read at the moment it matters, so the engine
      holds no provider concept and the user changing the setting mid-session needs no push. Step 3 closes it
      over the real credential; this step ships it testable with no database and no vault.

      The enum comes from `lib/app/models/background_playback.dart`, which gives this file its first import from
      outside `lib/app/playback/`. Deliberate, bounded to a dependency-free enum, and step 1's doc block records
      why the enum cannot live in this directory.

      The branch, on `AppLifecycleState.paused` only:

      | Choice | Action |
      |---|---|
      | `stop` | `await stop()` |
      | `audio`, `pictureInPicture` | `await _release()` only |

      `audio` and `pictureInPicture` are deliberately one arm today, and say so in the doc block: the Dart half
      of both is "do not stop the core", and everything that separates them is platform work that exists on no
      target yet (Android `PictureInPictureParams`, iOS an AVFoundation engine libmpv cannot feed,
      `.ac/research/player-layer.md:415-437`). Writing them as one arm with a comment beats writing two
      identical arms that look like they do different things.

      Do nothing at all on `resumed`, and give that its own doc paragraph rather than leaving it as an absence.
      An automatic reload retakes the account's single connection slot (measured `max_connections: 1`, a second
      stream evicted the first at 5.79 s, `.ac/research/player-layer.md:218-231`) and evicts whichever device
      picked it up while the user was away, which is the exact harm stopping on background exists to prevent.
      It is also the only honest option: `load` is a full fresh open by design (`playback_engine.dart:169-174`)
      and a lapsed token is indistinguishable from a healthy wait (`player-layer.md:591-613`).

      **Three hazards, all of them found in research and all of them yours to handle.**

      First, **no platform check is written anywhere and that is correct**. `paused` "is only entered on iOS
      and Android" (`platform_dispatcher.dart:2358-2446`), and the macOS embedder maps occlusion to
      `resumed`/`inactive`/`hidden` only. Reacting to `paused` IS reacting to mobile backgrounding. A
      `Platform.isAndroid` test here would be noise that goes stale. Put the citation in the doc block, because
      the absence of a platform check is the thing a later reader will try to "fix".

      Second, **the listener must be disposed**, in `dispose()` at `mpv_playback_engine.dart:373-382`, whose
      order paragraph at `:366-372` is the rule to follow: the listener disposal belongs with the local
      bookkeeping ahead of `_upstream.cancel()` at `:379`, since it depends on neither the subscription nor the
      controller. `engine.dispose()` has no call site in `lib/` (verified by grep), so in production this engine
      is process-lived and the removal never runs; in tests, where a fresh engine is built per case against a
      shared binding, a leaked listener outlives its own test and the next one's `paused` hits a dead engine.

      Third, and this is the one that will waste a worker's afternoon: **`AppLifecycleListener` asserts the chain
      `detached <-> paused <-> hidden <-> inactive <-> resumed`, and it seeds its idea of the current state from
      the binding at construction**, `_lifecycleState = (binding ?? WidgetsBinding.instance).lifecycleState`
      (`app_lifecycle_listener.dart:78`, verified in the pinned SDK).

      `test/app/playback/mpv_playback_engine_test.dart` has **no `testWidgets` in it**: every case is a plain
      `test()` under a single `TestWidgetsFlutterBinding.ensureInitialized()` at `:75`. `postTest()`, which calls
      `resetInternalState()` and returns the binding's lifecycle to its default, is registered only inside
      `testWidgets` (`flutter_test/lib/src/widget_tester.dart:183`). So in this file the binding's lifecycle
      state **persists across cases**: the first case that drives the binding to `paused` leaves it there, and
      the second case constructs a listener seeded `paused`, whose first `resumed` throws
      `Invalid state transition from AppLifecycleState.paused to AppLifecycleState.resumed`.

      Handle it in the harness rather than in each case. Capture the binding once
      (`final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();`), write a
      helper that walks down (`inactive`, `hidden`, `paused`) through `binding.handleAppLifecycleStateChanged`,
      which is public and fans out to every observer (`binding.dart:1329-1334`), and register an `addTearDown`
      that walks back up (`hidden`, `inactive`, `resumed`) so every case starts where the last one began.

      **Do not convert any case in this file to `testWidgets` to get a `tester`.** Its ticks arrive over a real
      `await Future<void>.delayed(Duration.zero)` (`:116`), which `testWidgets`'s fake clock stalls, so the
      conversion trades this trap for a hang.

      Tests, in that same file, which already carries the platform-channel harness: `paused` under `stop` calls
      the plugin's `stop` and releases the wakelock; `paused` under `audio` releases the wakelock and does NOT
      call the plugin's `stop`; same for `pictureInPicture`; `resumed` after any of them issues no platform call
      at all; a disposed engine ignores a later `paused`; and the macOS case, which is the only mechanical proof
      objective 4 can have: the sequence `resumed -> inactive -> hidden` **alone**, which is exactly what the
      macOS embedder delivers on occlusion, issues no platform call and leaves the wakelock untouched.
    - **References**:
        - lib/app/playback/mpv_playback_engine.dart:333-344, `stop()`, what the `stop` arm calls
        - lib/app/playback/mpv_playback_engine.dart:272-287, `_release()` and the `_awake` guard, what the other arm calls
        - lib/app/playback/mpv_playback_engine.dart:366-382, `dispose()` and its order paragraph, where the listener disposal joins
        - lib/app/playback/mpv_playback_engine.dart:69-73 and :167, the injected-seam shape and the constructor to extend
        - /Users/anilcan/flutter/packages/flutter/lib/src/widgets/app_lifecycle_listener.dart:78, the construction-time seeding that decides the test harness
        - test/app/playback/mpv_playback_engine_test.dart:75, the binding; :116, the real `Future.delayed` that forbids `testWidgets`
    - **Done when**:
        - `rg -n 'AppLifecycleListener' lib/app/playback/mpv_playback_engine.dart` matches at least twice, once for the field and once for its disposal
        - `rg -c 'testWidgets' test/app/playback/mpv_playback_engine_test.dart` returns 0
        - `flutter test test/app/playback/mpv_playback_engine_test.dart` is green
        - `flutter analyze --fatal-infos --fatal-warnings lib/app/playback/mpv_playback_engine.dart` is clean
    - **QA**: `flutter test test/app/playback/mpv_playback_engine_test.dart`, then `flutter test` whole-suite once,
      because a leaked binding observer fails a LATER test rather than its own and running the one file cannot
      see it. Prove each test fails with its fix removed: change the `audio` arm to call `stop()` and watch the
      `audio` test go red; drop the `addTearDown` that walks the binding back up and watch a later case throw
      `Invalid state transition`; restore both.
    - **Must NOT**:
        - Reload, re-`load` or otherwise act on `resumed`
        - Write any `Platform.isX` or `defaultTargetPlatform` check
        - Convert any case in `mpv_playback_engine_test.dart` to `testWidgets`
        - Read the setting from a store, a vault or a database inside the engine
        - Touch `PlaybackController.detach()` or `stop()`, which clear `_channel` (`playback_controller.dart:279-314`)

### Wave 3: the wiring

- [x] **Step 3**: Thread the real setting from the vault to the engine
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-1-cross-layer: five source files across the credential, the composition root, the
      session, the setup facade and its controller, and `app_service_provider.dart` sits outside the CI coverage
      denominator, so a mistake there is asserted only by what a test file transcribes.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/protocol/xtream/xtream_credentials.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/providers/app_service_provider.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/provider/provider_session.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/app/controllers/provider_setup_controller.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/app/providers/app_service_provider_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/app/provider/provider_session_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/app/controllers/provider_setup_controller_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/ui/layouts/provider_settings_layout_test.dart
    - **Description**:
      Close step 2's callback over the stored credential, and give the setting a writer of its own.

      **The writer is the whole point of this step, so read this paragraph before writing anything.** The only
      code in the app that ever persists a credential is `ProviderSession.adopt`'s `await credentials.save()`
      (`provider_session.dart:384`), and the only caller of `adopt` is `ProviderSetupController.submit`, which
      reaches it only after a live panel handshake succeeds (`provider_setup_controller.dart:346-350`,
      `if (_fault != null) return;`). The three credential fields also start empty on every open of the screen
      (`provider_settings_layout.dart:170-176`). So routing this setting through `submit`, which is what the
      resolver does, would mean a user can only change what happens when they background the app by retyping
      their base URL, username and password AND having a reachable, unexpired panel at that moment, re-sending
      their password over what is usually plaintext HTTP. That defeats objective 2 outright.

      So add a second writer on `ProviderSession`:

      ```dart
      Future<void> setBackgroundPlayback(BackgroundPlayback choice) async { ... }
      ```

      It reads `_credentials`, returns immediately when it is null, rebuilds the record with the new value,
      `await`s `save()`, assigns `_credentials`, and calls `notifyListeners()`. No handshake, no `adopt`, no
      `refresh`, no resolver push: none of those depends on this field, and `adopt`'s doc block
      (`provider_session.dart:360-383`) lists five things it does that this write has no business repeating.

      Rebuilding the record needs a narrow member on `XtreamCredentials`, beside `save()` at `:107`:

      ```dart
      XtreamCredentials withBackgroundPlayback(String? value)
      ```

      Purpose-named rather than a general `copyWith`, for two reasons. `stop` stores as null (step 1), and a
      `copyWith` taking a nullable parameter cannot tell "leave it alone" from "set it to null". And CLAUDE.md
      forbids speculative abstraction before the third caller; this has one. It may pass `baseUrl` straight back
      through the public constructor: `_normaliseBaseUrl` (`:441-455`) only trims, strips trailing slashes and
      validates, so it is idempotent on a value it already produced.

      On `ProviderSession`, also add `BackgroundPlayback get backgroundPlayback`, reading the loaded credential's
      raw string through `BackgroundPlayback.parse` and returning `stop` when no credential is loaded. Derive it
      on every read rather than caching, and say so in its doc block: that is what makes a sign-out
      (`:444`, which nulls `_credentials`) return it to `stop` with no push at all, unlike the resolver, which
      needs `_pushResolverSetting()` at `:460` because a `HostResolver` holds state this getter does not.

      In `app_service_provider.dart:108`, extend the engine factory:

      ```dart
      Magic.put(
        PlaybackController(
          engine: () => MpvPlaybackEngine(
            redact: session.redactProviderSecrets,
            backgroundPlayback: () => session.backgroundPlayback,
          ),
        ),
      );
      ```

      A closure over the session, for the reason the two lines above it are closures: the read happens when the
      app is backgrounded rather than when the provider is registered, so a user changing the setting mid-session
      needs no push and the binding order stays irrelevant.

      **`ProviderSetupFacade` is an `abstract interface class` (`provider_setup_controller.dart:24`) and it is
      the only thing the settings screen may read, so both members have to be declared there and implemented
      twice.** Declare `BackgroundPlayback get backgroundPlayback` beside `ResolverSetting get resolver` at
      `:52`, and `Future<void> setBackgroundPlayback(BackgroundPlayback choice)` beside `submit` at `:67-73`.
      Implement both on `ProviderSetupController` beside the `resolver` getter at `:247`, each delegating to the
      session. Then update `_FakeProvider` at `test/ui/layouts/provider_settings_layout_test.dart:21`, the only
      other implementer: a Dart class must answer every interface member, so leaving it alone turns this step's
      own `flutter analyze` red. Give the fake a settable field and a method that records what it was called
      with, which is the shape the rest of that double already uses.

      **`submit` does not change at all.** Its signature, its callers and `_FakeProvider`'s record of it stay
      exactly as they are.
    - **References**:
        - lib/app/provider/provider_session.dart:383-399, `adopt`, the only existing writer, and the five things this write must not repeat
        - lib/app/provider/provider_session.dart:249-255, `providerResolution`, the derive-on-read getter shape
        - lib/app/provider/provider_session.dart:444-469, `signOut`, why this getter needs no push
        - lib/app/protocol/xtream/xtream_credentials.dart:98-107, the constructor and `save()`, where `withBackgroundPlayback` goes
        - lib/app/protocol/xtream/xtream_credentials.dart:441-455, `_normaliseBaseUrl`, idempotent, so the public constructor is safe to reuse
        - lib/app/controllers/provider_setup_controller.dart:24, `abstract interface class ProviderSetupFacade`
        - lib/app/controllers/provider_setup_controller.dart:52 and :67-73, where the two new members are declared
        - lib/app/controllers/provider_setup_controller.dart:247, the `resolver` getter to implement beside
        - lib/app/controllers/provider_setup_controller.dart:346-350, the handshake gate that makes `submit` the wrong writer
        - test/ui/layouts/provider_settings_layout_test.dart:21, `_FakeProvider`, the only other implementer
        - test/app/providers/app_service_provider_test.dart, the regression gate added in #33; it must stay a plain `test()` with `TestWidgetsFlutterBinding.ensureInitialized()`, never `testWidgets`, whose fake clock hangs on real I/O
    - **Done when**:
        - `rg -n 'backgroundPlayback' lib/app/providers/app_service_provider.dart lib/app/provider/provider_session.dart lib/app/controllers/provider_setup_controller.dart lib/app/protocol/xtream/xtream_credentials.dart` matches in all four
        - `rg -n 'backgroundPlayback' lib/app/controllers/provider_setup_controller.dart` shows it declared in the facade AND implemented on the controller
        - `flutter test test/app/providers/ test/app/provider/ test/app/controllers/ test/ui/layouts/provider_settings_layout_test.dart` is green
        - `flutter analyze --fatal-infos --fatal-warnings` is clean
    - **QA**: `flutter test test/app/provider/provider_session_test.dart test/app/controllers/provider_setup_controller_test.dart`.
      Assert the composed value, not the wiring, and cover the case this step exists for: with `Vault.fake()`,
      adopt a credential, call `setBackgroundPlayback(BackgroundPlayback.audio)` with **no handshake of any
      kind**, then `XtreamCredentials.load()` and assert the stored blob carries `audio`. Plus: the getter reads
      `stop` before any credential is loaded, and reads `stop` again after `signOut()`. Prove each fails with its
      fix removed.
    - **Must NOT**:
        - Change `submit`'s signature, or route this setting through `submit`
        - Call `adopt`, `refresh` or `handshake` from `setBackgroundPlayback`
        - Cache the choice in a field on `ProviderSession` or on the engine
        - Add a general `copyWith` to `XtreamCredentials`
        - Add a second `HostResolver`, `ProviderSession` or `PlaybackController` binding
        - Change the binding order in `register()`

### Wave 4: the screen

- [x] **Step 4**: Put the three options on the settings screen, with the platform truth beside them
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-4-detail: the picker is mechanical, and the form-state trap it has to avoid is one
      a reviewer found in the running app on this very screen two PRs ago.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/lib/ui/layouts/provider_settings_layout.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/test/ui/layouts/provider_settings_layout_test.dart
    - **Description**:
      Add a `WFormSelect<BackgroundPlayback>` under the advanced disclosure, beside the resolver picker at
      `provider_settings_layout.dart:325-346`, with three options in this order: `stop` (default), `audio`,
      `pictureInPicture`. Seed `_backgroundPlayback` in `initState` from `widget.provider.backgroundPlayback`
      the way `_resolverChoice` is seeded at `:178-179`.

      **This picker writes on change, not on submit**, which is where it parts company with the resolver beside
      it. `onChange` sets the local state AND calls
      `widget.provider.setBackgroundPlayback(value)` (step 3's facade member). It never touches `submit`, and
      `_handleSubmit` at `:631-656` gains nothing.

      The reason is not tidiness. `submit` stores only after a live panel handshake
      (`provider_setup_controller.dart:346-350`) and the three credential fields start empty on every open of
      this screen (`:170-176`), so a setting that rides `submit` can only be changed by a user who retypes their
      whole credential against a reachable panel. Write it in the field's doc block, because the field above it
      does the opposite and the difference has to read as a decision.

      `onChange` rather than `onSaved` for the second reason too: `Form.save()` skips a field that is not
      mounted, which is the user-visible data loss a reviewer found on the resolver field in PR #33. The rule
      lives at `:315-320` and its consequence at `:156-164`.

      **Hide the picker when `widget.provider.hasCredential` is false.** There is nothing to write to before a
      credential exists (step 3's setter returns early on a null credential), and a control that accepts a
      choice and discards it is the failure this whole step is written to avoid.

      **The honesty line is the condition this whole option set ships under**, not decoration. Add a note beside
      the picker in the shape of `_resolverScopeNote()` at `:414-421` (`text-xs text-fg-muted`), stating in
      Turkish which platform can honour which choice. It must say, in substance: stopping works everywhere
      today; audio and picture-in-picture keep the connection open but the platform half is not built on any
      target yet, so on macOS the app keeps playing anyway and on mobile these currently behave as "keep the
      connection". Write it as a sentence a user understands, not as a compatibility matrix. Without this line
      `pictureInPicture` reads as a feature and behaves as `audio`, which is the failure the resolver's own
      https limitation taught this project to write down.

      Copy is Turkish because the app's UI is (`_resolverScope` at `:134` is the neighbouring example); the doc
      blocks around it stay English.

      Tests go in the existing `provider_settings_layout_test.dart`, through `pumpScreen` like every other case
      in that file: the picker renders three options with `stop` selected by default; a fake reporting `audio`
      seeds the picker to `audio`; changing the picker calls `setBackgroundPlayback` with the new value and does
      NOT call `submit`; the picker is absent when `hasCredential` is false; and the honesty note is on screen
      whenever the picker is.
    - **References**:
        - lib/ui/layouts/provider_settings_layout.dart:325-346, the `WFormSelect` picker to copy
        - lib/ui/layouts/provider_settings_layout.dart:315-320, the `onChange`-not-`onSaved` rule in the codebase's own words
        - lib/ui/layouts/provider_settings_layout.dart:156-164, what an unmounted field costs
        - lib/ui/layouts/provider_settings_layout.dart:170-179, the fields that start empty, and the seeding shape
        - lib/ui/layouts/provider_settings_layout.dart:414-421, the scope-note shape and its className
        - test/support/screen.dart:44, `pumpScreen`, which every case in the target test file already uses
        - test/ui/layouts/provider_settings_layout_test.dart:85, the mandatory `setUp(WindParser.clearCache)`
    - **Done when**:
        - `rg -n 'BackgroundPlayback' lib/ui/layouts/provider_settings_layout.dart` matches
        - `rg -n -A8 'WFormSelect<BackgroundPlayback>' lib/ui/layouts/provider_settings_layout.dart | rg -c 'onSaved'` returns 0
        - `flutter test test/ui/layouts/provider_settings_layout_test.dart` is green
        - `flutter analyze --fatal-infos --fatal-warnings` is clean
    - **QA**: `flutter test test/ui/layouts/provider_settings_layout_test.dart`, then the whole `test/ui/` directory,
      because a late change to this screen has broken an unrelated file before (`search_focus_test.dart` was the
      only gate that caught the `ShowcaseLayout._featured` crash). Prove the seeding test and the
      "does not call submit" test each fail with their fix removed.
    - **Must NOT**:
        - Use `Colors.*`, a raw `Color(0x...)` or a bare `TextStyle`; Wind classes only
        - Use `onSaved` for this field, or route it through `_handleSubmit`
        - Render the picker when no credential is configured
        - Claim on screen that picture-in-picture works on any platform today
        - Add a second settings route; `/saglayici` is the only one (`lib/routes/app.dart:44`)

### Wave 5: the record

- [x] **Step 5**: Record what shipped and what it is still waiting on
    - **Type**: code
    - **Tier**: quick
    - **Why this tier**: rule-none: prose in two files that already have the section it belongs in.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/CLAUDE.md
        - /Users/anilcan/Code/watchools/.claude/worktrees/playback-lifecycle/.ac/research/player-layer.md
    - **Description**:
      Add a short paragraph to `CLAUDE.md`'s "The player abstraction" section stating: the engine observes
      `paused` and branches on a per-credential `BackgroundPlayback`; `paused` is delivered on iOS and Android
      only, which is why no platform check is written; `audio` and `pictureInPicture` share one Dart arm because
      the difference between them is platform work no target has yet; and `resumed` deliberately does nothing,
      because an automatic reload retakes an account's single connection slot.

      Add the matching note to `.ac/research/player-layer.md` beside the existing background and PiP material
      around `:415-437`, recording that iOS PiP is blocked on `AVPictureInPictureController` needing an
      `AVPlayerLayer` or `AVSampleBufferDisplayLayer` that libmpv does not produce, and that the enum is the
      storage so each platform becomes an arm rather than a migration off a boolean.

      No em dash and no en dash in either file.
    - **References**:
        - CLAUDE.md, "The player abstraction" section, where the paragraph goes
        - .ac/research/player-layer.md:415-437, the existing PiP material this extends
    - **Done when**:
        - `rg -n 'BackgroundPlayback' CLAUDE.md .ac/research/player-layer.md` matches in both
        - `rg -n '[—–]' CLAUDE.md .ac/research/player-layer.md` matches nothing
    - **QA**: Read both paragraphs back and check each claim against the file it cites. Every sentence here
      names something verified in `research/verification-log.md` or in this plan's Research Summary; anything
      that does not, drop.
    - **Must NOT**:
        - Claim any mobile target is wired
        - Restate the plan; these are two paragraphs, not a summary

### Wave 6: the gates

- [x] **Step 6**: Run every gate and prove the branch on a real app
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**:
      Two halves. The gates prove the code is clean; the walk proves the picker renders and seeds on a real
      engine, which is where a CanvasKit crash or an absorbed semantics label shows up and a widget test cannot.

      For the walk: start the app from THIS worktree with its own `--cdp-port`. The `fluttersdk` MCP server runs
      `./bin/fsa` from the session's original root, so a `dusk` call from a worktree can drive the main
      checkout's app and report success either way. Navigate with `dusk:navigate --route /saglayici` rather than
      a browser URL: web deep links land on `/` in this app. Open the advanced disclosure and capture a
      screenshot of the picker with its honesty note visible.

      **Two limits, and state both in the evidence file rather than implying coverage.**

      The vault round trip cannot be walked unattended here. Reaching the picker needs a configured credential,
      `submit` stores only after a live panel handshake (`provider_setup_controller.dart:346-350`), and this
      worktree has no `.env.local`, so `tool/dev/run_with_provider.sh` has nothing to pass as `--dart-define`.
      If `.env.local` is present per `.worktreeinclude` and a panel answers, do the full walk: set the picker to
      `Ses`, reload the app, reopen the screen, assert it comes back on `Ses`. If not, record the walk as
      NOT RUN with this reason, and note that step 3's `setBackgroundPlayback` test covers the persistence claim
      under `Vault.fake()`.

      The `paused` branch cannot be exercised on any platform this repository can start: macOS never delivers
      `paused` and no mobile target is wired. Steps 2 and 3's tests are the whole of that assurance, which is
      what put step 2 at `senior`.
    - **Commands**:
        - flutter analyze --fatal-infos --fatal-warnings
        - dart format --set-exit-if-changed lib test
        - flutter test --coverage
        - git diff --name-only -- pubspec.lock
        - git ls-files --error-unmatch pubspec_overrides.yaml .env .env.local
    - **Done when**:
        - `flutter analyze --fatal-infos --fatal-warnings` exits 0 with no infos and no warnings
        - `dart format --set-exit-if-changed lib test` exits 0
        - `flutter test --coverage` is green and `coverage/lcov.info` carries a `background_playback.dart` record whose hit count is above 0
        - `git diff --name-only -- pubspec.lock` prints nothing, so the committed hosted-only lock is untouched
        - `git ls-files --error-unmatch pubspec_overrides.yaml .env .env.local` FAILS for all three, proving none is tracked. `git status --short` is the WRONG instrument here and must not be used: it never prints ignored paths, so it cannot fail for these three
        - the picker and its honesty note appear in the screenshot
    - **Evidence**:
        - .ac/plans/playback-lifecycle-teardown/evidence/06-analyze.txt
        - .ac/plans/playback-lifecycle-teardown/evidence/06-test-coverage.txt
        - .ac/plans/playback-lifecycle-teardown/evidence/06-tracked-files.txt
        - .ac/plans/playback-lifecycle-teardown/evidence/06-settings-walk.txt
        - .ac/plans/playback-lifecycle-teardown/evidence/06-picker.png
    - **Must NOT**:
        - Edit source to make a gate pass; a red gate goes back to the step that owns it
        - Use `git status --short` as the tracked-file gate
        - Stage `pubspec.lock`, `pubspec_overrides.yaml`, `.env` or `.env.local`
        - Report the vault round trip as walked if `.env.local` was absent
        - Report the `paused` branch as verified on a device

## Risks Accepted

1. **The `paused` branch runs on no platform this repository can start.** macOS never delivers it and no mobile
   target is wired, so steps 2 and 3's tests are the entire assurance. Accepted because the alternative is
   shipping the Android and iOS hosts first (roadmap stage 3) and carrying issue #27 open behind them, and
   because the observer is what those hosts will need on day one. Mitigated by putting step 2 at `senior` and
   by step 6 stating plainly what it could not exercise.

2. **`audio` and `pictureInPicture` currently do the same thing.** Both mean "do not stop the core" and neither
   has its platform half. Accepted on the user's explicit instruction to ship all three anyway
   ("pipi de dahil et bu plana, desteklemiyorsa bile kullanıcı ayarlayabilsin"), with one condition attached and
   enforced by step 4: the screen says so. An option that silently does something else is the failure this
   project has already written down once, on the resolver's https limitation.

3. **The setting lives on the credential, in the vault, rather than in an app-preference store.** It is not a
   secret and the vault is not a preferences store. Accepted because the alternative is a whole new storage
   layer for one enum: `Storage` is a file facade, `Session` is request-scoped flash, and `Cache` is flushable
   by `Cache.flush()`, which would silently reset it. The credential path exists, is durable, is already read
   into memory before playback can start, and carries one precedent (`resolver`) to follow field for field.

   **The review round found the cost was larger than first written, and step 3 is the answer rather than the
   acceptance.** The first draft of this plan had the picker ride `submit`, exactly as the resolver does. That
   would have made the setting unchangeable without a live panel handshake and a fully retyped base URL,
   username and password, re-sent over what is usually plaintext HTTP, because `adopt` is the only writer
   (`provider_session.dart:384`) and `submit` reaches it only past
   `if (_fault != null) return;` (`provider_setup_controller.dart:346-350`). A user whose panel is down,
   throttled or expired could not have changed what happens when they background the app. That defeats
   objective 2, so step 3 adds `ProviderSession.setBackgroundPlayback`, a second writer that saves with no
   handshake, and step 4's picker calls it on change.

   What remains accepted is the small part: signing out forgets the choice, which is defensible since there is
   no playback without a credential and it is the same trade the resolver already makes.

   Two corrections to the reasoning that stood behind this, both worth keeping written down. This reverses the
   direction Stage 3 was leaning, a DB-backed key-value table. And the argument that first justified the
   reversal, that the engine needs the value synchronously when `paused` fires, is weak on its own terms: the
   `paused` arm is already `async` and awaits `stop()`. The argument that actually holds is the precedent and
   the absence of any preference store to put it in.

4. **A user who changes the setting while backgrounded on a future mobile build gets the old behaviour once.**
   The closure reads at `paused` time, so this cannot actually happen; the risk is the inverse, that the closure
   is read so late that a mid-flight sign-out yields `stop`. `stop` is the safe direction, so it is accepted
   without a guard.

## Cross-Project Observations

**wind, gap**: `SelectOption` carries `disabled` (`wind/lib/src/widgets/select_option.dart:48-51`, read at
source), so marking an option unavailable IS supported. What it has no field for is the REASON: no `note`, no
`description`, no secondary text, and `==`/`hashCode` cover only `value`, `label` and `disabled`. So an option
can be greyed out and cannot say why, and the caller's only route is prose somewhere else on the screen.

That is the gap this plan hits, and `disabled` would be the wrong tool here anyway: the user asked explicitly
that an unsupported option still be selectable ("desteklemiyorsa bile kullanıcı ayarlayabilsin"), so the note
has to sit beside a live control rather than explain a dead one. A `SelectOption.note` rendered under the label
would carry both cases in the component. Worth filing; not filed yet.

An earlier version of this paragraph said `WFormSelect` had no way to mark an option unavailable at all. That
was wrong, caught by reading the sibling source before filing, which is the rule CLAUDE.md states for exactly
this reason.

**watchools, gap**: the nav rail's "Ayarlar" item at `lib/ui/layouts/support/nav_rail.dart:44` navigates
nowhere. `/saglayici` (`lib/routes/app.dart:44`) is the only settings route in the app, and it is reachable only
through the provider flow. Every setting this project has added, the resolver and now this one, lands on a
screen a user cannot reach from the main navigation. Out of scope here and increasingly load-bearing.

## Deferred Ideas

1. **Android picture-in-picture for real.** `PictureInPictureParams` on the Activity plus the aspect ratio from
   the current track. Needs the Android host, roadmap stage 3. The enum arm is already there for it.
2. **iOS audio continuation for real.** The `audio` background mode in `Info.plist` plus an `AVAudioSession`
   category, under App Store Guideline 2.5.4. Needs the iOS host, roadmap stage 3.
3. **iOS picture-in-picture.** Blocked on the engine rather than on the host: it needs
   `AVPictureInPictureController`, which takes an `AVPlayerLayer` or `AVSampleBufferDisplayLayer`, and libmpv
   produces neither. This is the AVFoundation second engine, roadmap stage 6.
4. **A resume that knows whether the token lapsed.** Today `resumed` does nothing because the app cannot tell a
   lapsed token from a healthy wait. A provider-side probe (a cheap `player_api.php` call on return) could
   answer it, and would turn `resumed` into an informed decision instead of a deliberate absence.
5. **An app-preference store.** If a second non-credential setting appears, revisit risk 3 and build the
   key-value table over `DB.statement` that this plan chose not to build for one enum.
