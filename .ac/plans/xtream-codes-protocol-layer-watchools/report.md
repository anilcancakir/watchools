# Report: xtream-codes-protocol-layer-watchools

**Branch**: `xtream-protocol-layer`, off `origin/master`. Not pushed, no pull request opened.
**Steps**: 14 of 14, all verified at a wave barrier.
**Gates**: `flutter analyze --fatal-infos --fatal-warnings` 0 issues; 372 tests passing, 1 skipped;
`dart format` clean; coverage 2146/2239 = 95.8% against a 90% floor; `node tool/xtream-mock/verify.mjs`
77 checks, 0 failures.

## What this delivers

A user's Xtream credentials, already in `Vault`, now become a live catalogue on all four screens.
The chain is: `XtreamCredentials` reads the keystore, `XtreamClient` speaks to the panel over a
dedicated interceptor-free driver, `xtream_json.dart` absorbs the wire's type drift,
`XtreamAccount` classifies the subscription's health from the handshake, `Channel.fromXtream` /
`TitleItem.fromXtream` / `Programme.fromXtream` map it onto the value types the screens already
read, `CatalogueStore` caches it in SQLite for cold start, and `ProviderSession` holds all of it and
notifies the two controllers. A provider fault renders as one of four `ProviderFault` values on
every surface.

## Commits

| Hash | Wave | What |
|---|---|---|
| `95d31e9` | 1 | The credential record and the wire coercion helpers |
| `0a92c6d` | 2 | The panel client on its own driver, the account disjunction, the fourth fault |
| `a573318` | 3 | The wire-to-model factories and the cold-start cache |
| `bf3f235` | 4 | The session, the classification and the connection gate |
| `67ee2f6` | 5 | The catalogue on all four screens, and the fault when there is one |
| `0eb944b` | 6 | Four real-panel behaviours taught to the mock |
| `eef8c55` | - | The review remediation: repaint on an arriving catalogue, plus eight defects |

Plus one sibling: `fluttersdk/magic#151`, `preserveHeaderCase: true` on the Dio driver. **CI green,
open, unmerged, unpublished.** Left open deliberately: the standing merge authorisation is scoped to
the watchools repository.

## Steps

| # | Step | Tier | Result |
|---|------|------|--------|
| 1 | Credentials in Vault behind a serialised record | senior | PASS, + remediation |
| 2 | The type-drift coercion helpers | junior | PASS, + remediation |
| 3 | magic's lost header case, in the sibling | junior | PASS, PR open, CI green |
| 4 | A dedicated driver, then the client | senior | PASS |
| 5 | The account and the four faults | junior-high | PASS, + remediation |
| 6 | The wire onto Channel, Programme, TitleItem | junior-high | PASS, + remediation |
| 7 | The catalogue store as a cold-start cache | senior | PASS |
| 8 | The session, the classification, the gate | junior-high | PASS, + 2 remediations |
| 9 | The `evicted` fault rendered | junior | PASS, **run in wave 2, not wave 4** |
| 10 | The controllers off the fixtures | junior-high | PASS, + remediation |
| 11 | The fault on all four surfaces | junior | PASS, after a `[CONTRADICTION]` re-spawn |
| 12 | Four mock gaps closed | junior | PASS |
| 13 | The catalogue write at real scale | verification | PASS, 176 ms against a 2,000 ms trigger |
| 14 | Every gate the project enforces | verification | PASS, + remediation |

No step failed. One step correctly refused to start and one wave was re-grouped; both are below.

## The measurement the plan was gated on

Step 13 was an escalation trigger, not a formality: above roughly two seconds the synchronous write
was not survivable behind a progress state and the design would have had to become a background
isolate, which magic's web arm cannot provide.

**2,976 channels in 34 ms, 38,247 titles in 142 ms, 176 ms combined**, an order of magnitude under.
Read it as a floor rather than a device number: in-memory, debug build, Apple M1 Pro. What it
measures honestly is the statement shape, and a regression to magic's `insertAll` (76,494 statements
instead of 38,247 `execute` calls on one prepared statement) would show as an order of magnitude
rather than as noise. Detail in `evidence/13-catalogue-write-timing.txt`.

## Where the plan was wrong, and what it cost

Fourteen orchestrator remediations, recorded in full in `wisdom.md`. The ones that mattered:

- **Two wave-ordering errors of the same shape.** `ProviderFault.evicted` (step 5) makes
  `provider_notice.dart`'s exhaustive switch a compile error, and its renderer was two waves later,
  so step 9 was pulled forward into wave 2. Then making `channel`/`selected` nullable (step 10) broke
  `now_layout.dart:121`, whose fix lived in step 11. When a step widens or nullables a type, its
  consumers belong in the same wave, or every barrier between them commits a tree that does not build.
- **Two value types carried no provider identifier at all.** Neither `Channel` nor `TitleItem` had
  one, and the store, the EPG pass and `/baslik/:id` all need it. Added in step 6; one step later
  would have been a store migration.
- **The plan's own locked D4 decision was unimplemented.** The series list was in v1 "so
  `/baslik/:id` knows both ID spaces", and nothing fetched it. That one was my briefing gap, which
  the worker reported rather than inventing scope for.
- **`boot()` awaited the network refresh**, which would have held a blank window open for the whole
  41,000-row fetch. Thirteen tests went red on the split, which is the proof the behaviour changed.

## Two things that went right and are worth keeping

**Step 11 refused to start.** Its briefing said the retry callback already existed on the
controllers. It did not, and neither empty component carried a callback at all. The worker read all
four files, reported a `[CONTRADICTION]`, wrote nothing, and named the two options it was not
authorised to take. The alternative was either a Must-NOT violation or a layout reaching past its
controller into the session.

**Step 4 built a real security gate.** The obvious test, asserting no `Authorization` header on a
`FakeNetworkDriver`, cannot fail: the fake records only what the caller passed and runs no
interceptors at all. It used a loopback socket to read the raw wire bytes, and added a **positive
control** proving the same request through a driver that does carry `AuthInterceptor` puts
`authorization: bearer <token>` on the wire. A negative assertion with no positive control beside it
cannot tell "secure" from "rig broken".

## Review

Two reviewers in parallel. Eight findings acted on, every one verified against source first; three
of the oracle's refuted premises were mine. Full table in `review-log.md`. The most consequential:
**nothing repainted after the boot refresh**, so the live catalogue never reached the screen and
objective 1 did not work at runtime. `ProviderSession` notified nobody and the controllers polled
from a getter, which runs during a build while the value arrives between builds.

## Deferred

- **The cross-timezone clock offset.** `Programme.fromXtream` reads the panel-local `start`/`end`
  strings and Dart resolves them in the **device** zone, so a panel in another timezone shifts the
  whole schedule uniformly. The data to fix it is already captured on the account
  (`panelTimestamp`, `panelTime`) and read by nothing, and `tool/xtream-mock/server.mjs:43-44`
  already sets a 180-minute offset to catch it.
- **The sticky guide window.** The user chose a real anchored clock on the provider path, which
  makes `windowStart` teleport thirty minutes at each half-hour boundary: the grid shifts 180 pixels
  and the now line jumps back, possibly under a viewer mid-scroll. `CLAUDE.md` records it as latent
  only because the default clock does not move; it is no longer latent.
- **A refresh policy.** `refresh()` has one caller, the fault panel's retry, so a healthy session
  fetches once per launch and the four-entry now/next window goes stale. Interacts with the
  connection cap.
- **`followRedirects = false` is native-only.** Dio's browser adapter never reads the flag, the same
  shape as `preserveHeaderCase`. A platform limit rather than a defect.
- **A real `copyWith` on `Channel` and `TitleItem`**, retiring three hand-rolled field-by-field
  rebuilds. Each is a place where adding a field and forgetting one line yields a valid object with
  silently dropped state.
- **`WATCHOOLS_TITLE_SCALE` is a no-op** unless `WATCHOOLS_SCALE` is also set.
- **Publish magic and bump the constraint**, which is what unskips step 4's exact-case `User-Agent`
  assertion. It is `skip:`ped rather than red because step 14 demands a green suite.
- **The onboarding screen and `/saglayici`.** No user-facing way to enter a credential exists;
  development seeds `Vault` directly, and `ProviderNotice`'s settings button leads nowhere until
  that plan lands.
- Eight doc corrections, three reuse extractions and four efficiency findings, all in `review-log.md`.

## What is NOT verified

- **No provider-backed run of the app exists.** `tool/dusk/perf.sh` was not run and no dusk walk was
  run, both because an `fsa` call from a worktree can silently drive the main checkout. Three of
  this project's sharpest past findings came from walks no unit test could reach, and the two
  defects the reviewer found by tracing render sites are exactly that class.
- **No real provider request was made**, per the standing constraint. The mock is the executable
  contract.
- **Web.** `Vault` on web is `localStorage` with the AES key written beside the ciphertext, and
  `MagicVaultService` gives no app-side way to set `wrapKey`. Nothing here made that worse, and web
  remains a scaffolded rather than a shipping target. Do not describe web `Vault` as secure storage.

## Ecosystem findings

Four, filed in `.ac/research/ecosystem-defects.md` and reported out loud per `CLAUDE.md`:

1. **Defect, fixed.** magic's Dio driver never set `preserveHeaderCase`, so every header shipped
   lowercased including `User-Agent`, which ExoPlayer reads case-sensitively. `fluttersdk/magic#151`.
2. **Defect, open, the most serious.** `AuthInterceptor` attaches the bearer token to every request
   with no host test, on the one driver `Http` resolves, and reads a 401 from any host as a
   refresh-and-replay signal. Worked around app-side with a dedicated driver; the sibling wants a
   host allowlist.
3. **Gap.** `DB` exposes no `prepare`, and `insertAll` costs two statements per row: 76,494 for
   38,247 titles. Forced a direct `sqlite3` dependency into this app.
4. **Improvement.** `DB.transaction` brackets an async callback with a synchronous BEGIN/COMMIT, so
   any `await` inside leaves the transaction open for another query to join.
