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
