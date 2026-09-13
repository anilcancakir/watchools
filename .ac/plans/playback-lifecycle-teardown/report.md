# Execution report: playback-lifecycle-teardown

**Plan**: `.ac/plans/playback-lifecycle-teardown/plan.md`
**Branch**: `worktree-playback-lifecycle`, off `3e74043`
**Commits**: 7, `d3551d3` through `bf9a3a1`
**Issue**: #27

## What shipped

Backgrounding a Flutter app does not dispose a `State`, so on the Android and iOS targets that are coming,
the libmpv core, the account's single connection slot and the wakelock would all survive the user pressing
Home. Nothing in this repository observed app lifecycle at all.

Now `MpvPlaybackEngine` carries an `AppLifecycleListener` that fires on `paused` and branches on a
per-credential `BackgroundPlayback`:

| Choice | What happens on `paused` |
|---|---|
| `stop` (default) | the core is torn down, the connection slot released, the wakelock dropped |
| `audio` | the core stays, only the wakelock is dropped |
| `pictureInPicture` | the same arm as `audio` today |

`resumed` deliberately does nothing. The user picks the choice on `/saglayici`, and the screen says which
platform can honour which.

## Steps

| # | Step | Tier | Result |
|---|---|---|---|
| 1 | `BackgroundPlayback` enum and the credential field | junior | done, plus one orchestrator remediation |
| 2 | the lifecycle listener and the branch | senior | done, 3 reasoned deviations |
| 3 | the writer, the facade members, the engine wiring | junior-high | done, plus one orchestrator remediation |
| 4 | the picker and the per-platform honesty line | junior-high | done |
| 5 | the record in `CLAUDE.md` and `player-layer.md` | quick, retried at junior | done on the retry |
| 6 | the gates and the dusk walk | verification | done, and the walk ran in full |

## Verification

- `flutter analyze --fatal-infos --fatal-warnings`: no issues
- `dart format --set-exit-if-changed lib test`: 169 files, 0 changed
- `flutter test`: **690 pass, 1 skipped, 0 fail** (659 before this plan)
- Coverage **94.8%** overall, over the 90% floor. Every changed file at 97.6% or above;
  `background_playback.dart` at 100%
- `git diff --name-only -- pubspec.lock`: empty, the committed hosted-only lock is untouched
- `git ls-files --error-unmatch pubspec_overrides.yaml .env .env.local`: fails for all three, none is tracked

### The walk the plan expected to skip

The plan said the vault round trip would likely be recorded NOT RUN, because `.env.local` is absent and
`submit` stores only past a live panel handshake. It ran in full instead, against the repository's own mock
panel (`tool/xtream-mock/`), and **cost the real subscription nothing**: zero requests reached any real
provider, and the mock logged 30 `player_api.php` requests.

The keychain was checked empty BEFORE the app was started, because a stored real credential would have made
the launch fire a catalogue refresh at the user's own panel.

Proven on the running app: the picker renders with the honesty note, all three options are offered, and a
change made **without pressing Kaydet** survived a full process restart (SIGTERM, new pid). Zero exceptions.
Evidence and screenshots under `evidence/`.

## The defect found in review, and it was mine

`ProviderSession.setBackgroundPlayback` read `_credentials`, awaited `save()`, then assigned
unconditionally. Both races are real and both were reproduced:

- a **sign-out** landing inside that await left `hasCredentials` true with the user's password written back
  to the Keychain behind the delete
- an **adopt** landing there left the session on the PREVIOUS account, which is the one the next launch
  would sign the user in as

This file already carried the guard idiom, `if (!identical(_credentials, credentials)) return;`, five times
over. My step 3 briefing never named it. Fixed in `bf9a3a1` with the guard plus a repair, because unlike the
other five this writer has already touched the vault by the time it notices.

`FakeVaultService` cannot reproduce either race: it completes every operation in the caller's microtask, so
two suspended writers always resume in call order, which is the safe ordering. `StallingVaultService`
(`test/support/throwing_vault.dart`) forces the ordering a real Keychain gives, where a write is slower than
a delete.

## Known limits, stated rather than implied

- **The `paused` branch runs on no platform this repository can start.** macOS never delivers it
  (`sky_engine/lib/ui/platform_dispatcher.dart:2444`) and no mobile target is wired. The seven cases in
  `mpv_playback_engine_test.dart` are the entire assurance, which is why step 2 was tiered `senior`.
- **`audio` and `pictureInPicture` do the same thing today.** Shipped on the user's explicit instruction to
  offer all three anyway, with the condition that the screen says so. It does.
- **Signing out forgets the choice**, because the setting lives on the credential record.

## Ecosystem findings

**wind, gap.** `SelectOption` carries `disabled` (`wind/lib/src/widgets/select_option.dart:48-51`) so an
option can be greyed out, but it has no field for the REASON: no `note`, no secondary text, and `==` covers
only `value`, `label` and `disabled`. This plan needed prose beside a LIVE control, since the user asked that
unsupported options stay selectable, so `disabled` was the wrong tool anyway. A `SelectOption.note` rendered
under the label would carry both cases. Not filed yet.

An earlier draft of this claimed `WFormSelect` had no way to mark an option unavailable at all. That was
wrong, caught by reading the sibling source before filing.

**watchools, gap.** The nav rail's "Ayarlar" item (`lib/ui/layouts/support/nav_rail.dart:44`) navigates
nowhere. `/saglayici` is the only settings route and is reachable only through the provider flow, so every
setting this project adds lands on a screen a user cannot reach from the main navigation. Out of scope here
and getting worse.

**watchools, housekeeping.** A macOS run leaves two untracked `Package.resolved` files under
`macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` and `macos/Runner.xcworkspace/...`.
`.gitignore:12` ignores `.swiftpm/` with a leading dot, which does not match these. Removed rather than
committed: whether to pin Swift package versions is a project decision.

## Process notes

- A `quick`/haiku worker stalled for fifteen minutes on step 5, a two-paragraph prose step, and wrote
  nothing. Escalated to `junior`, which finished the same briefing in 43 seconds. The signal was
  `git status --porcelain` staying empty.
- Two waves in a row shipped a member with no test of its own because the step's `Files` list did not name a
  test file for it. Both were caught at the wave barrier and remediated. A `Files` list is a coverage
  decision nobody makes on purpose.
- Both Phase 3 reviewers died with a session interruption, 9 hours "running" with one sentence apiece. The
  critical finding above came from re-reading the writer myself while waiting for them.

## Deferred

1. Android picture-in-picture for real. Needs the Android host. The enum arm is already there.
2. iOS audio continuation for real. Needs the iOS host plus the `audio` background mode.
3. iOS picture-in-picture. Blocked on the engine: `AVPictureInPictureController` needs an `AVPlayerLayer` or
   `AVSampleBufferDisplayLayer` and libmpv produces neither.
4. A resume that knows whether the token lapsed, which would turn `resumed` into an informed decision instead
   of a deliberate absence.
5. An app-preference store, if a second non-credential setting appears.
