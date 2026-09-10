# Review log

## Run 2026-09-09T19:45:11Z

Plan review (`ac:plan-reviewer`), before execution. Findings applied to
`plan.md` in the same sitting. One was refuted rather than applied: step 1's
`ts`-first rationale cited a README defect that is recorded as fixed at
`README.md:53-66` (commit `04356f8`, #22), and the worker refused to write the
stale claim. Verified and re-cited.

## Run 2026-09-10, code review (`ac:plan-code-review`), after step 13

Twelve findings acted on, three refuted or narrowed, one referred out as a
design decision. Every claim was checked against the file it cited before it
changed anything; the two that mattered most were confirmed by reading the
Swift and the component rather than by trusting the report.

### Confirmed and fixed

| Severity | Finding | Fix |
|---|---|---|
| CRITICAL | `_attached` never cleared, but `forget(viewId)` stops the core on every route pop (`WatchoolsPlayerPlugin.swift:186-191`) | `PlaybackController.detach`, called from `_PlaybackViewState.dispose` |
| CRITICAL | `Scrim.flat` (85%) under `Scrim.bottom` (opaque) washes the lower third of the picture, against `DESIGN.md:441-442` | both removed; the chrome carries a bounded panel |
| CRITICAL | the wakelock survives a failed re-load and a native `forget` | released in `load`'s failure branch; `detach` stops the engine |
| IMPORTANT | the connection gate latches closed, because `_channel` is cleared only by `stop()`/`onClose()` and `onClose()` is unreachable in production | `detach` clears it |
| IMPORTANT | base64 guard misses a percent-encoded `/` | `%2B`/`%2F`/`%3D` admitted, unescaped before decoding |
| IMPORTANT | three fire-and-forget futures turn a `PlatformException` into an unhandled async error | `PlaybackLayout._run` |
| IMPORTANT | `onOpenSettings` goes to `/` where four siblings use `/saglayici`, and does not stop first | both corrected |
| IMPORTANT | the pause control renders when `unplayable` and no core exists | branch removed, asserted |
| IMPORTANT | the two route tests added for the ordering fix are vacuous | ordering moved to `playback_controller_test.dart` against a handshaken session |
| IMPORTANT | `stop()` clears `_channel` but not `_pending` | cleared |
| MINOR | `playback_view.dart` said "structurally" of a declared `implements` | corrected |
| MINOR | `play()` nulls `_channel` on the unplayable path, so the screen cannot name the channel | channel kept |
| MINOR | `emit` after `dispose()` throws the stream's own opaque message | named `StateError` |
| MINOR | the `base64` codec iteration is unreachable | single decode |
| MINOR | `describe(Uri)` has no production caller | deleted, guarantee re-asserted through `redact` |

### Found while fixing, beyond the report

Two, both in the redaction path and both reproduced before they were patched.

`utf8.decode` is strict, so **any** token carrying a binary signature threw
and was left alone with the credential in plain ASCII at its front. That is a
larger hole than the escaping the report named, and it is closed with
`allowMalformed: true`; the guard that stops innocent text being rewritten is
the containment check, not the decode's strictness.

And the first version of the escape fix still leaked, because `=` was in the
run's character class: the match reached backwards through a query parameter's
`token=` and the joined run has invalid mid-string padding, so it decoded to
nothing and was returned verbatim. Padding is now its own trailing group,
which is what base64 means by it.

### Referred out, then decided

Two went to the user rather than being guessed, and both came back.

**The scrim ceiling.** The chrome's panel is `bg-scrim-strong`, 72 percent,
against `DESIGN.md`'s 40. Decision: **fix the rule, not the tokens.** What
keeps Plex's artwork legible is that nothing covers it, and 40 percent was the
document's guess at how to say so; the theme has no token that satisfies the
cap and its own comment records 72 as the minimum for legible text. `DESIGN.md`
now states the half that matters, no scrim spans the frame, and cites
`playback_layout.dart` as the example. No code changed.

**`/saglayici`, registered nowhere.** Decision: **ship a minimal placeholder.**
`lib/ui/layouts/provider_settings_layout.dart` plus a thin view and the route.
No form, deliberately: onboarding is undesigned, and a field writing to `Vault`
from there would be it shipped by accident on the one flow where a mistake
costs the user their subscription details. A route-table test now fails if any
path a layout navigates to is registered nowhere.

**Wind publishing** was the third question and the answer was not now, so the
`ActivateIntent` binding stays unreleased and the doc block that says so stands.

## Oracle round (`ac:oracle`), before merge

Six premises tested. Three refuted, all three above the interface, which is the
part that would have been expensive to get wrong.

| Premise | Verdict |
|---|---|
| No seek, duration or position is right for the interface | confirmed, but the caller that will demand one is already on screen |
| `detach` from the view's `dispose` is the right shape | confirmed for the route pop, refuted as stated |
| `PlaybackFacade` is not speculative | refuted in the branch's favour: two implementations, two consumers |
| The redaction guarantee is structural | confirmed for the interface, two uncovered doors |
| The connection gate is safe | **refuted outright** |
| The branch ships as one PR | confirmed |

Acted on, each verified against the file it cited first:

- **The gate only guarded its own door.** `refresh` tested the predicate once
  and then ran a handshake, four list fetches and up to `epgFetchLimit`
  sequential EPG calls unguarded, while `boot()` fires that batch unawaited at
  every cold start. Now checked between the halves and between EPG round trips,
  never inside a `DB.transaction`. The test for it was proved to discriminate:
  without the loop guard it reads `[301, 302, 303]`, with it `[301]`.
- **`onReady` was a discarded future**, and the worst one on the screen, since
  `attach` is what triggers the `load`. Through `_run` now.
- **Promise 7 added to the interface**: `stop` and `dispose` are idempotent and
  safe after the surface is gone. `detach` relies on it and it currently holds
  only because `MpvEngine.swift:195-196` opens with a nil guard.
- **The refused members gained their arriving caller**: `showcase_layout.dart:98`
  renders an `İzlemeye devam et` rail off `TitleItem.progress`, and
  `setTitleProgress` has no caller in `lib/`, so resume is unwired rather than
  deferred. The shape to give it is written down (a separate capability
  interface, not nullable members here).
- **A doc overclaim of mine corrected**: `dispose` is not the only signal Dart
  gets that playback ended, because backgrounding does not dispose a `State`.
  Issue #27 opened for the lifecycle observer, which belongs with the engine.
- **The redaction guarantee is now enforced**: `test/app/playback/redaction_boundary_test.dart`
  asserts exactly one file reads `WatchoolsPlayer.events`, no screen references
  it or `PlayerEvent`, and no `String` crosses `PlaybackEngine` outside the user
  agent.

Not acted on: the oracle's note that `pubspec.yaml:59` claims telescope sees
every provider HTTP call while `xtream_client.dart:208` resolves its own
`provider_network` driver. It flagged this as unsettled and it errs in the safe
direction (fewer places a credential is inspectable), so it stays a note.

### Found by looking at the running app, twice

Neither was reachable by any test that existed.

The placeholder shipped with its back affordance stretched into a pill across
the whole window: a column stretches its children across the cross axis, and
`findsOneWidget` on a semantics label passes at either width. Fixed with
`items-start`, now asserted as a 40 by 40 size, and that assertion was proved
to discriminate (1392 by 40 without the fix).

And the earlier `_channel`-through-a-refusal fix had bought nothing visible,
because the layout's `unplayable` branch replaced the channel name instead of
adding to it.

## Code review round 2 (`ac:plan-code-review`)

Read against `6a1f582`, so it did not see the oracle-round commits and found
the `onReady` discarded future independently. Eleven findings, ten acted on,
one rejected after trying it.

| Severity | Finding | Outcome |
|---|---|---|
| IMPORTANT | the `onClose` teardown test cannot fail on either thing it claims | rewritten against `hasTickListener`, after two failed attempts |
| IMPORTANT | `load`'s failure branch writes state a newer load owns | generation guard on both the tail and the catch |
| IMPORTANT | the wakelock enable can land after the core it was taken for is gone | enable moved out of the try, behind the same guard |
| IMPORTANT | the gate reports "playing" for a channel that opened no core | third clause, `!unplayable` |
| IMPORTANT | the gate closure is asserted only by two hand copies that disagree | hoisted to `PlaybackController.holdsConnection` |
| IMPORTANT | the fault getter's only test asserts `null == null` | drives a refused handshake, asserts arrival and clearing |
| MINOR | `stop`/`togglePause` build an engine through the getter | `togglePause` reads `_resolvedEngine` |
| MINOR | `_notified` is not reset by `play` | reset, with why nothing had broken yet |
| MINOR | `detach` leaves the engine holding a pruned view id | documented as a single-consumer limit; see below |
| MINOR | `MpvPlaybackEngine.dispose()` has no production caller | true, and the doc block already reads as a contract rather than a live path |
| MINOR | a run-character prefix defeats the base64 match | unreachable against the measured token shape; noted |

**Rejected after trying it.** Clearing `_surface` in `stop()` looks like it
closes the dead-id hole finding 9 names. It does not: a stop is the stream
ending rather than the view going away, the platform view is still mounted,
and the next `load` would throw `StateError` with a live surface sitting right
there. The field is documented instead, with the single-consumer assumption
that makes it safe written down.

**The test that took three attempts is the finding worth remembering.** Emit a
tick after teardown and expect no repaint: version one was dropped by the fake
(`_isStale` reads `tick.session <= session` once `stop` clears `_reading`),
version two landed but a disposed `ChangeNotifier` cannot notify either way.
Both stayed green with `_ticks?.cancel()` deleted. Only the third, reading
`FakePlaybackEngine.hasTickListener`, fails when the cancel goes. Every fix in
this round that could be proved was proved the same way, by breaking the code
once on purpose.

### Gates after everything

`flutter analyze --fatal-infos --fatal-warnings` clean. 489 tests pass, 1
deliberate skip. `dart format` clean. Coverage 2439/2538 = 96.1% against the
90% floor, computed with CI's own script. Plugin 16/16. Mock verifier all
checks passed. Committed lock carries 1 `source: path` entry, equal to HEAD's.
Both CI jobs green on PR #26.
