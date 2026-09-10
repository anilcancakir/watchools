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

### Referred out rather than decided

The chrome's panel is `bg-scrim-strong`, 72 percent
(`watchools_status_tokens.dart:109`). `DESIGN.md:441-442` says never heavier
than 40. The theme ships exactly two scrim weights, 45 and 72, and its own
comment records 72 as what a line of text needs to clear AA over a frame whose
brightness we do not control. One of the two numbers is wrong and only a
design call settles which. What this plan could honour is the part that keeps
the picture: nothing washes the frame, and the contrast is bounded to where
the text is.

### Noted, not this plan's to fix

`/saglayici` is registered nowhere. All six references in `lib/` are call
sites and `lib/routes/app.dart` has no such page, so the fault panel's
settings button on all five layouts currently falls through to `/`. It is the
onboarding screen `CLAUDE.md` records as not existing yet; being consistent
with the four siblings is still the right call for this layout.

### Gates after the fixes

`flutter analyze --fatal-infos --fatal-warnings` clean. 477 tests pass, 1
deliberate skip. `dart format` clean. Coverage 2425/2524 = 96.1% against the
90% floor, computed with CI's own script. Plugin 16/16. Mock verifier all
checks passed. Committed lock carries 1 `source: path` entry, equal to HEAD's.
