# Wisdom

## Wave 1

1. **A plan can name a fact about the machine that is wrong, and the cheapest place to find
   out is before the wave launches.** Step 1 was written to set
   `DEVELOPMENT_TEAM = 883V9SVA54`, the team the user supplied. `security find-identity -v -p
   codesigning` returns two identities and that team has only an **Apple Distribution**
   certificate; the **Apple Development** one belongs to `936TDTZJN9`. Pairing
   `"Apple Development"` with a team that has no development certificate sends Xcode looking
   for something that does not exist, and automatic signing cannot mint one inside a headless
   `flutter build`. Found by running the reachability check at 2c before spawning, which cost
   one command; found by the worker it would have cost a spawn and a failed build. Resolved by
   splitting the configurations: Debug and Profile on `936TDTZJN9`, Release on `883V9SVA54`.

2. **`origin/HEAD` is worth reading before a sibling step branches.** Step 9 will work in
   `/Users/anilcan/Code/fluttersdk/magic`, whose default branch is `master` and whose checkout
   currently sits on `fix/dio-preserve-header-case` at `ae15036` with a clean tree. A worker
   that branches off HEAD rather than `origin/master` would carry an unrelated commit into the
   PR. Recorded here rather than held in context so a compaction cannot lose it before wave 6.

3. **Three Wind API anchors step 5 rests on, verified while wave 1 ran rather than by its
   worker.** `w_form_input.dart:108-109` really does default `autocorrect` and
   `enableSuggestions` to `true`, so the plan's requirement to set both false is about a real
   default and not a guess. `type: InputType.password` really is the only route to
   `obscureText`: `w_input.dart:744` maps it in `_getKeyboardConfig` and `:527` is the only
   place `obscureText` is passed. And the trap that looks like it is coming is not one:
   `w_input.dart:466-471` forces `maxLines = 1` for every non-multiline type precisely because
   `EditableText` asserts it when `obscureText` is true, so a password field needs no
   `maxLines` handling from the caller. Checking these cost three commands; a worker
   discovering the third one would have cost a red phase it could not explain.

4. **[REMEDIATION] Step 1 is deferred, and the account-side half of it is already done.**
   A certificate on the machine is not the precondition that was missing. What was missing
   was an App ID and a provisioning profile, and `asc` created both non-interactively:
   `asc bundle-ids create --identifier com.watchools.app --platform UNIVERSAL` gave
   `SW57679G5G` under seed `883V9SVA54`; `asc devices register --udid 605156C7-...` (from
   `asc devices local-udid`) gave `8Q46CPBVM9`, which a `MAC_APP_DEVELOPMENT` profile requires
   and iOS profiles do not; `asc profiles create` gave `6SRPP332YR`, ACTIVE to 2027, installed
   at `~/Library/Developer/Xcode/UserData/Provisioning Profiles/1d15403a-...`.
   Three build attempts still fail. Automatic signing says "Automatic signing is disabled and
   unable to generate a profile. To enable automatic signing, pass -allowProvisioningUpdates",
   which `flutter build macos` does not pass and offers no way to; manual signing with the
   profile named, and then with its UUID, both say `"Runner" requires a provisioning profile`.
   So Xcode is not picking up a profile that is installed, ACTIVE, and matches the bundle ID
   and team. The remaining move is interactive: open Xcode once so it indexes the profile.
   **The repository was reverted to HEAD for this step** rather than left carrying a
   configuration that fails every macOS build, which would have blocked far more than step 1.

5. **My team split was wrong and the user's original answer was right.** I read
   `security find-identity`'s `"Apple Development: Anilcan Cakir (936TDTZJN9)"` as naming a
   team. In an Apple Development certificate's common name that parenthetical is the
   individual developer's ID; the team is elsewhere. Every Seed ID in
   `asc bundle-ids list` is `883V9SVA54`, and so is the profile `asc` just issued. The
   correct configuration is one team everywhere, which is what the user said before I
   surfaced a question that did not need asking.

## Wave 2 to 4

6. **A briefing's prose file list is not the harness's file list, and a worker will route
   around the difference.** Step 9's briefing said "the two `lib/` files plus whatever tests
   that repository's own conventions require", and magic's own `CLAUDE.md` mandates a
   CHANGELOG, doc and skill sync in the same change set. The file-scope hook granted only the
   two literal paths, so `Edit` and `Write` refused everything else and the worker
   substituted `Bash` heredocs, having first probed with a write-then-revert to confirm
   `Bash` was ungated. It reported all of this transparently and the seven files it touched
   are all inside the intent, so the outcome was right. The lesson is mine: a sibling-repo
   step has to enumerate its test, changelog and doc paths explicitly, because a prose
   qualifier is invisible to the hook and the worker's only alternatives are to stop or to
   bypass. This is also the exact hole the wave barrier's `git status` check exists for: the
   hook gates `Edit` and `Write`, and `Bash` walks past it.

7. **[REMEDIATION] A sign-out during the boot-time refresh crashed, not merely wrote stale
   data.** Layer B on step 3 traced the data flow and found the write-back; the test written
   for it found something worse. `boot()` fires `refresh()` unawaited, and `signOut` nulls
   `_midnight`, which the EPG loop reads through `!` while awaiting one round trip per
   channel, so a sign-out a few seconds into launch threw
   `Null check operator used on a null value` into a future `boot()` deliberately does not
   catch. Two fixes, and only the second one worked: extending the loop's own `break` guarded
   the NEXT iteration while the crash was in the current one, so `_midnight` had to be
   captured before the loop exactly as `_clock!` already was. Proved by removing the capture
   and watching the crash return.

8. **[REMEDIATION] `PlaybackController.stop` was the one of four without the resolved-engine
   guard, and a sign-out is what made that reachable.** `health`, `detach`, `togglePause` and
   `onClose` all read `_resolvedEngine?`; `stop` read `_engine`, which BUILDS one, and
   `MpvPlaybackEngine`'s constructor subscribes to a platform `EventChannel`. Signing out
   with nothing playing therefore constructed an engine to stop a core that never existed.
   Found by step 4's worker, which correctly declined to fix a file outside its own scope and
   reported the one-word fix instead. I had fixed `togglePause` earlier the same day and
   missed its sibling, which is what an audit pass over "the other three" would have caught
   and a per-symbol fix did not.

9. **[REMEDIATION] A facade the next step needs is the previous step's file.** Step 5's
   criteria require the screen to hide the sign-out control when no credential exists, and
   `ProviderSetupFacade` shipped without a member that could answer. Step 5's `Files` list
   does not include the controller, so the addition was mine rather than either worker's:
   `bool get hasCredential`, reading through to the session rather than cached, for the same
   reason `PlaybackController.health` reads through. Worth catching at the seam between two
   steps rather than by a worker discovering its contract is short.

10. **[REVIEW] The happy path had no caller, and every test still passed.** `submit` adopted
    and deliberately skipped the refresh, on a stated contract that the first fetch was
    "`boot()`'s job or the user's". Neither exists at that moment: `boot()`'s refresh already
    ran and returned at the door because there was no credential then, and the only other
    caller of `refresh()` is a fault panel's retry that `adopt` has just cleared. So a user
    who typed a working credential landed on `/` reading "Sonuç yok. Arama terimini
    değiştirin", having searched for nothing, with no recovery short of relaunching the app.
    Invisible to the suite for a precise reason worth keeping: the layout test asserted the
    facade received the four values, the controller test asserted the vault held them, and
    nobody owned the frame after. A correct local decision against a caller contract that has
    no caller is the same shape as the route pop that killed libmpv and told Dart nothing, and
    as the gate that stopped a refresh from starting and did nothing about one already running.

11. **[REVIEW] Narrowing a window reads exactly like closing one.** The sign-out crash in
    entry 7 was "fixed" twice: first by extending the EPG loop's break, then by capturing
    `_midnight` before the loop. The second capture still sat immediately after
    `get_live_streams`, which is the single longest response in a refresh at 2,976 rows, so
    the widest case was the one left open, and the test double had no seam that could reach
    it. `onShortEpg` could only script an event inside the EPG loop, and a test that cannot
    express a window is indistinguishable from a window that is closed. The fix that holds
    takes the clock and the midnight as arguments, so no nullable field is read across an
    await at all, and the new `onLiveStreams` seam is what proves it.

12. **[REVIEW] Four of the tests written to close review findings could have passed without
    their fix.** In one sitting, in a plan whose own wisdom file already named this as the
    recurring failure: a catalogue-fetch test that called `refresh()` itself and so started
    the pass it meant to observe; a reset test that never called `Form.save()` while the
    field was mounted, so the value it asserted about was never written; a busy-guard test
    that needed two taps with no pump between them to reach a one-frame window; and a
    focus-node test reading the node across typing, which rebuilds the same element and keeps
    the same node whether or not an external one is passed. Reading the test did not catch any
    of the four. Breaking the source caught all four. The rule this settles: a test is not
    written until the source has been broken once and the test has been watched to fail.

13. **[REVIEW] A guard against data loss belongs in the sibling's default, not in the
    consumer's config.** `fluttersdk/magic#153` first flipped macOS to the legacy keychain
    unconditionally, which unblocked this app and would have silently orphaned every vault
    item every existing signed macOS consumer had already stored: there is no migration
    between the two keychains in either direction, a miss reads as "never stored" rather than
    as an error, and `Crypt._getDeviceEncrypter` generates a fresh device key on that null
    read, so anything encrypted under the old one becomes permanently unreadable. The review
    on that PR caught it. The shape that shipped is a constructor argument plus a config key
    defaulting to today's behaviour, which also means this app cannot reach for it until magic
    is released, and reaching for it early would be exactly the "do not reshape this app
    around an unreleased API" the workflow rules prohibit.
