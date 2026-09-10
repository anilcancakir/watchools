# Review round

Two passes over commit `e9e2d4d`: `ac:plan-code-review` on the diff, and `ac:oracle` because
`rule-5-criticality` fired on step 4 (before it, no credential could be entered or stored at all;
after it, a typed password is confirmed against a third-party panel over plaintext HTTP and written
to the Keychain).

The review reported 21 of 22 compliance criteria met, three CRITICALs and nine IMPORTANTs. The
oracle refuted two of the brief's own premises and found the blocker neither the plan nor the review
saw. Both are recorded below with what was done and, where nothing was done, why.

## Verified before acting

Every claim that changed a decision was opened. Three came back different from the report:

- The review's CRITICAL 3 said `expect(session.titles, isEmpty)` was vacuous because the double
  serves no VOD entries. True, and the fix it suggested (serve some) would have pinned the wrong
  guard once the between-halves check landed, so the assertion became
  `expect(panel.requestedVodStreams, isFalse)` instead: four requests never sent is the statement
  with weight.
- The oracle's premise check found `ProviderFault` has **four** members, not three; `evicted` was
  missing from the brief I wrote. Its retry claim held.
- The oracle called the redaction guarantee UNSUPPORTED rather than wrong, and it is right about
  the mechanism: `redactProviderSecrets` is keyed to `_credentials`
  (`provider_session.dart:211`) and the typed credential is not adopted yet, so on the submit path
  the redactor returns its input unchanged. What holds that path is that nothing on it logs, which
  is a narrower guarantee than "everything is redacted" and is now stated as such.

## Fixed

| Finding | Source | What it was |
|---|---|---|
| A correct credential landed on an empty screen with no way to refresh | oracle | `submit` adopted and deliberately did not refresh, on a contract ("`boot()`'s job or the user's") with no caller. `boot()`'s refresh had already returned at the door, `adopt` restores a cache for an account key that never existed, and `GuideController.reload` is reachable only from a fault panel `adopt` has just cleared. The user read "Sonuç yok. Arama terimini değiştirin" having searched for nothing, with no recovery short of relaunching. |
| `_clock!` and `_midnight!` read after two awaits | review CRITICAL 1 | The captures sat immediately after `get_live_streams`, the single longest response in a refresh. A sign-out there crashed the unawaited boot refresh. Two earlier attempts narrowed this window rather than closing it; both are recorded in the source comment. |
| The write-back guard tested null, not identity | review IMPORTANT 1 | `signOut` nulls `_credentials` so the null check caught it; submitting a second credential does not, so `/` showed the previous account's channels under the new one, none playable because `adopt` nulls `_account`. |
| `_anchorClock` ran after the handshake await | review IMPORTANT 3 | A sign-out in that window built a fresh `TickingGuideClock` on a session that had just disposed one, leaving a one-minute timer nothing would dispose. The same early return covers the MINOR about `_fault` and `_account` being assigned unconditionally. |
| `signOut` threw `MagicVaultException` at nobody | both | `XtreamCredentials.clear` is a `Vault.delete`, and the layout's `_run` catches `PlatformException` alone, which `MagicVaultException` is not: the catch could never fire for the exception that actually arrives. |
| The focus-node test could not fail | review CRITICAL 2 | It read the node across typing, which rebuilds the same element and keeps the same node with or without an external one. It reads across a close and reopen now, which is the only thing that destroys `WInput`'s State. |
| `expect(session.titles, isEmpty)` was vacuous | review CRITICAL 3 | See above. |
| Nothing interlocked sign-out with an in-flight submit | review IMPORTANT 2 | Tapping sign-out during a handshake cleared the session, then the submit resumed and adopted the credential back: the sign-out undid itself. Gated in the controller and disabled on the control. |
| `expired`'s panel offered a button contradicting its own copy | both | `ProviderNotice` routes `expired` to `onOpenSettings`, which this screen wired back to `_submit`, so a mistyped password offered "Bilgileri güncelle" over copy saying a retry will not help and then resent the same credential. `expired` renders as a sentence naming both fields now. |
| The back disc was dead on the redirect path | review IMPORTANT 6 | A `redirectTarget` records no history, so `canPop()` is false and `back()` falls through all three branches silently. Hidden when there is no credential, because then there is genuinely nowhere to go. |
| A second submit navigated away mid-handshake | review IMPORTANT 7 | One frame wide, before `isDisabled` repaints. |
| The `fieldError` banner and the navigation guard were unrendered by any test | review IMPORTANT 8 | Deleting the guard and always navigating kept the suite green. |
| `submit`'s `MagicVaultException` arm was untested | review IMPORTANT 9 | The arm whose own doc block calls it "a live path rather than a hypothetical". |
| `on ArgumentError` wrapped the whole method | review MINOR | Anything below the constructor would have been reported as "Panel adresi geçersiz" with the credential possibly already saved. |
| A user agent typed and hidden again kept being sent | review MINOR | And the default fallback never fired. |
| The user-agent field left `autocorrect` on | review MINOR | Not a secrecy question: an IME rewriting `VLC/3.0.20 LibVLC/3.0.20` changes the header a reseller keys access control to. |
| The `'provider'` alias had no test | review MINOR | `Kernel.resolve` drops an unknown alias silently, so a typo opens every guarded route. Filed as a magic defect. |
| Nothing told the user the connection is unencrypted | oracle | One sentence, plus the one about not reusing the password, which is the only real mitigation available. |

Four of the tests written for these could have passed without their fix, and each was caught by
breaking the source on purpose rather than by reading it: the catalogue-fetch test called
`refresh()` itself and so started the pass it meant to observe; the user-agent reset test never
called `save()` while the field was mounted, so the value it asserted about was never written; the
busy-guard test needed two taps with no pump between them to reach a one-frame window; and the
focus-node test is CRITICAL 2 above. That is four out of roughly a dozen, in a plan whose own
wisdom file already records this as its recurring failure.

## Recorded, not fixed

- **A fifth `ProviderFault` for a panel that answers but is not an Xtream panel.**
  `classifyProviderFault` consults `statusCode` only for `== 0` (`xtream_account.dart:211`), so a
  301, 403, 404 or 502 falls through to `_isGenericDenial` and, with no prior account, reports
  `throttled`. Its copy states a rate limit and asks the user to wait a few seconds. Before this
  change the base URL came from a define a developer had verified; after it a user types it, so a
  mistyped port is now a likely first-run outcome that produces a confidently wrong screen, forever.
  The oracle rates it recoverable rather than unsafe, and it touches the fault vocabulary every
  layout switches on, so it is its own change.

- **`_faultPanel`'s `w-full h-72`.** A hard 288px around a panel whose body wraps to an unknown
  number of lines at 414px, and `pumpScreen` ignores overflow by design, so no widget test can see
  a clip. `min-h-72` is the obvious answer and it interacts with `ProviderNotice`'s own `h-full`
  under an unbounded-max parent, which is the trap `CLAUDE.md` records from the other side. Left as
  is rather than guessed at: it needs a real render, which is step 8. Lower stakes now that
  `expired`, the fault a user is most likely to see here, no longer renders through this panel.

- **The fixture fallback is what `EnsureProvider` really guards.** The oracle is right that the
  middleware is a convenience, not a security control: nothing behind it dereferences a credential,
  and deleting it lets a user reach the same screens and see 23 fixture channels with nothing on
  screen marking them as demo data. The durable fix is a controller change (gate the fallback on the
  preview path rather than on `hasCredentials`), which step 6 ruled out of its own scope.

- **No test asserts the SET of guarded routes.** `rg -c "middleware(['provider'])"` printing 4 is
  satisfied by any four routes, so the fifth catalogue route added later is silently unguarded.
  One test enumerating `MagicRouter`'s table would settle it.

- **The redactor can be keyed to the wrong credential.** `adopt` swaps `_credentials` while
  `MpvPlaybackEngine` holds the closure bound at composition, so after adopting B every line naming
  A's stream URL is redacted against B. Unreachable by design rather than by luck, because the one
  route from playback to this form stops the core first, and one new navigation away from
  reachable. It wants a test, not a fix.

- **`submit` now handshakes twice in a row**, once to confirm and once inside the refresh. Accepted:
  the measured `max_connections` of 1 governs concurrent streams, these are sequential API calls,
  and passing the parsed account through `adopt` to skip the second one is a larger change than the
  dead end it would optimise.

## Steps 1 and 8, and what the oracle changed about them

The oracle refuted the premise that signing is a build requirement today: nothing in the tree
carries `keychain-access-groups` or a `DEVELOPMENT_TEAM`, and `project.pbxproj` is back to
`CODE_SIGN_IDENTITY = "-"`, because step 1 reverted the repository to HEAD rather than leave a
half-applied signing change. That is correct and it is what `wisdom.md` records.

It then proposed probing `Vault.put` on this build, on the grounds that `pubspec_overrides.yaml`
resolves magic from a checkout carrying the unconditional legacy-keychain flip. That was true when
it looked, and it is not any more: the review round on `fluttersdk/magic#153` established that the
unconditional flip is data loss for every existing signed consumer, so the default is back to the
data protection keychain and the legacy one is now opt-in through
`security.vault.macos_data_protection_keychain`.

So the route out of steps 1 and 8 is better than "open Xcode once", and it is not available yet:
when magic#153 ships, one config key in a debug build lets an unsigned macOS checkout store a
credential, and signing becomes optional rather than required. Setting that key now would be
reshaping this app around an unreleased API, which `.claude/rules/workflow.md` prohibits, so it
lands with the version bump.
