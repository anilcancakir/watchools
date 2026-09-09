
## Run 2026-09-09T13:33:02Z

Two reviewers ran in parallel: `ac:plan-code-review` on the code, and `ac:oracle` on the three
criticality surfaces (the plan carries three `rule-5-criticality` steps, which is the trigger).

**Compliance**: 14/14 steps met. Two `Done when` criteria did not hold as written and were already
recorded rather than concealed: `./tool/dusk/perf.sh` was not run (wisdom 23), and step 12's
"README no longer lists these four as absent" was unsatisfiable because the README never listed
them (wisdom 25).

**Findings acted on: 8, every one verified against source before it changed anything.**

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | CRITICAL | Nothing repainted after the boot refresh. `boot()` fires `refresh()` unawaited, `ProviderSession` notified nobody, and the controllers only polled from a getter, which runs during a build while the value arrives between builds. The live catalogue, the anchored clock and the fault all sat invisible until an unrelated gesture. Objective 1 did not work at runtime. | `ProviderSession extends ChangeNotifier`, notifies after a refresh, a fault and each user-state write; both controllers subscribe and `refreshUI()`. Two tests with a double whose catalogue arrives AFTER construction, which is the only shape that distinguishes a subscription from a poll. Mutation-checked. |
| 2 | CRITICAL | `TitleItem.fromXtream`'s series branch read the movie field names. A `get_series` entry carries `cover`, `plot`, `genre` and `releaseDate`, so every provider series had a null poster and no genres, and `Vitrin` rendered the no-artwork fallback with a note blaming the provider for our mapping. | Series branch reads its own fields, with `genre` split and `releaseDate`'s year parsed. Verified independently against `pbergman/xtream-codes-go` `series.go` and `ektotv/xtream-api`, beyond the reviewer's own citation. The mock answers `get_series` with `[]`, which is why nothing caught it. |
| 3 | CRITICAL | Every provider poster caption, hero and title screen read `0 · 0 dk`. `get_vod_streams` carries neither a year nor a runtime (`server.mjs:254-269`), and `lengthLabel` coerced a null to `0 dk`. Seven render sites. | `lengthLabel` is nullable, new `metaLabel` omits an absent part, and all seven sites compose rather than interpolate. The fixtures always supplied both, which is why no widget test saw it. |
| 4 | IMPORTANT | `XtreamCredentials.load()` throws `FormatException` on an unreadable payload, `start()` did not catch it, and `boot()` awaits `start()` inside `Magic.init()` before `runApp()`: a bad stored value aborted the boot with no UI and, with no onboarding screen, no way out. | Caught deliberately into `ProviderFault.expired`, which is the fault whose button goes to provider settings. |
| 5 | IMPORTANT | `refresh()` had no re-entrancy guard. `DB.transaction` issues a literal `BEGIN` on the one shared connection, so two overlapping refreshes nest it and the inner `rollback()` discards the outer's rows. Reachable by double-tapping the retry. | The in-flight future is held and returned; the guard does not latch, so the button still works twice. |
| 6 | IMPORTANT | `classifyProviderFault` returned `expired` for a generic denial with no account, i.e. the first-launch case. A blocked address or a proxy's HTML page reported a lapsed subscription and withheld the retry, which is the one fault the UI cannot recover from. | Reordered: a decoded body decides on the account, an undecodable one with no account is `throttled`. Every prior case preserved. |
| 7 | IMPORTANT | `_anchorClock` replaced a `TickingGuideClock` without disposing it, and `_scheduleNext` re-arms unconditionally: one leaked live timer per calendar day the app stays open. | Disposed before reassignment. |
| 8 | IMPORTANT | `_hhmm` mis-rendered a negative minute. `-30 ~/ 60` truncates to 0 while `-30 % 60` is 30, so half past eleven the previous night printed as `00:30`. Reachable nightly: a post-midnight re-anchor legitimately gives the on-air programme a negative start. Placement was always right, only the label lied. | Hour floored and both operands normalised, with tests at -30 and 1470. |

Also fixed during the gate run, from the coverage denominator rather than from either reviewer:
`xtream_account.dart` measured 27/51 with all 24 missing lines being `==`/`hashCode`/`toString`,
which left the password-stripping guarantee unasserted. Now 51/51 with the strip asserted directly.

**Deferred, recorded in `report.md` rather than fixed**

- `followRedirects = false` is native-only; dio's browser adapter never reads the flag. Same shape
  as `preserveHeaderCase`. A platform limit rather than a code defect.
- The cross-timezone offset. `Programme.fromXtream` reads the panel-local strings and resolves them
  in the device zone, so a panel in another timezone shifts the whole schedule uniformly. The data
  to fix it (`panelTimestamp`, `panelTime`) is already captured on the account and read by nothing;
  the mock is already configured with a 180-minute offset to catch it. In `## Deferred Ideas`.
- `refresh()` has one caller, the fault panel's retry, so a healthy session fetches once per launch
  and the now/next window goes stale. Needs a refresh policy, which interacts with the connection
  cap.
- Three reuse and four efficiency findings, including a real `copyWith` on `Channel` and `TitleItem`
  to retire three hand-rolled field-by-field rebuilds, and the 38,247-row read-back after the write.
- `WATCHOOLS_TITLE_SCALE` is a no-op unless `WATCHOOLS_SCALE` is also set.
- Eight doc corrections, including four "three faults" blocks that should now say four.

**Gates after the remediation**: analyze 0 issues, 372 passing and 1 deliberately skipped, format
clean, coverage 2146/2239 = 95.8% against a 90% floor, mock verifier 77 checks 0 failures.
