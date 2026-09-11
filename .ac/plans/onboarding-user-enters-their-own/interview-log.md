# Interview log

Plan: onboarding-user-enters-their-own
Topic: onboarding, a user enters their own Xtream credentials and the app stores them.
Includes fixing Vault on macOS. Apple Developer team ID 883V9SVA54.
AUTO_MODE: false

## Stage 0

Slug derived mechanically: no path prefix, no tech-stack token in the topic, stopwords
dropped (`a`, `and`, `the`), first five survivors taken. `onboarding-user-enters-their-own`.

Gitignore guard **deliberately skipped**. `.ac/` is not ignored in this repo and that is
the convention rather than an oversight: `CLAUDE.md` cites `.ac/research/stack-decisions.md`
as a repository document, and the two prior plans under `.ac/plans/` are committed. Applying
the guard would make every future plan commit need `git add -f`.

## Stage 1

Survey written by the main agent to `research/00-directory-survey.md`. This planner carries
a deep read of the codebase from the session that built the playback layer and the
development-credential path, so the cohort was aimed at the genuine unknowns rather than at
re-deriving what is already known.

Cohort: 4 `ac:explore` (reuse, form and input patterns, sign-out impact map, first-run and
routing) plus 2 `ac:librarian` (macOS Keychain entitlement and signing, magic's Vault
contract). Explore floor is 4, librarian floor is 2.

One brief went to `ac:explore` rather than `ac:librarian` for the Vault contract, because
magic is an in-house sibling on disk: it is a codebase read, not a docs question.

## Stage 3 interview

### 3a Proceed
Synthesis rendered. User picked `Devam et`.

### 3b.1 TDD
`TEST_INFRA_PRESENT = true` (flutter_test, `flutter test`, 90% CI floor, currently 96.1%),
so the non-branching `TDD?` variant was asked and batched with three independent nodes
rather than sent alone.

**Locked: `tdd`.** Failing test first on every step. Grounded in this session's own record:
three consecutive versions of one teardown test could not fail, and only breaking the
source on purpose revealed it. Onboarding's wrong-password and vault-failure branches are
the same class.

### D1 Keychain route
Options: sign here and report the magic gap / no signing plus a magic PR / both.

**Locked: both.** Sign here, which is the correct end state and reaches the modern
data-protection keychain, AND open a magic PR adding macOS options so other consumers and
unsigned development are unblocked. Onboarding waits only on the first.

Evidence that shaped the options: `-34018` is `errSecMissingEntitlement`, an access-group
check rather than a sandbox one (Apple's own page, plus the forums thread quoting an Apple
engineer). `keychain-access-groups` is a **restricted** entitlement per TN3125, so its mere
presence demands a provisioning profile, which is exactly the build error measured here. A
free Apple ID plus `DEVELOPMENT_TEAM` is enough for a machine-scoped local build
(flutter_secure_storage issue #1176); a paid membership only matters for running the signed
build on another Mac. CI is unaffected because it never invokes `xcodebuild`.

**Not in this plan, deliberately:** publishing magic and bumping the constraint here. That
is outward-facing and `.claude/rules/workflow.md` puts it after the sibling's own CI is
green. The magic step stops at an open PR.

### D2 Verify before store
**Locked: handshake first, store only when `classifyProviderFault` returns null.** A wrong
password comes back HTTP 200 with `{"auth": 0}`, which is valid JSON, so it takes step 2 at
`xtream_account.dart:219` and classifies as `expired`: the user sees the real reason
immediately. A credential stored while wrong produces that same `expired` later, detached
from the act that caused it.

### D3 First run
**Locked: a redirect guard to `/saglayici`.** `MagicMiddleware.redirectTarget`
(`magic_middleware.dart:71`) is purpose-built, resolves synchronously before the router
builds, and mounts the destination exactly once. `lib/app/kernel.dart` is empty today, so
this is the app's first middleware. The ordering works because
`ProviderSession.start()` is awaited inside `Magic.init()` before `runApp()`.

**Carried into the plan as a named trap:** the same doc block warns the redirect loops
unless it returns null when the location already equals the target.

### D4 Sign-out scope
**Locked: everything.** The Vault record, the session's credential / client / account /
fault / clock, the account's catalogue rows, and any playing core. Driven by a verified
finding rather than a preference: `catalogue_store.dart` has two DELETEs, both
`WHERE account = ?` inside a replace that only runs with a credential, so today a sign-out
leaves the previous subscriber's catalogue on disk. On a shared machine that is a privacy
defect, not a stale cache.

### D5 Form shape
**Locked: Wind's `WFormInput` family**, with `Form` plus `GlobalKey<FormState>`. The app's
first use of any `FormField`; the only text field today is `search_field.dart:73`, a raw
`WInput` bound with value plus onChanged.

Chosen against the reuse bias deliberately, on CLAUDE.md's direct instruction: "This
project exists partly to exercise both. Use them as the ecosystem intends rather than
reaching past them." A defect found in `WFormInput` is then our backlog, which is the
point of the mandate.

Verified before locking: `WFormInput extends FormField<String>`
(`wind/lib/src/widgets/w_form_input.dart:74`) and takes `validator`, `onSaved`,
`autovalidateMode`, an optional `controller`, a `focusNode`, `type` (so
`InputType.password`), `placeholder`, `className` and `onSubmitted`. `Form` and `FormField`
live in `flutter/widgets.dart`, so no Material import is needed.

### D6 User agent
**Locked: an optional field behind an "advanced" disclosure.** The reason it cannot be
omitted: `XtreamCredentials`'s constructor requires `userAgent` with no default (the reuse
report claimed a default and was refuted, see `verification-log.md`), CLAUDE.md records that
resellers key access control to the header, and a user whose panel rejects the default sees
`throttled`, which tells them nothing.

**Cost accepted:** Wind ships no disclosure or accordion widget (checked
`wind/lib/src/widgets/`, 30 files, none), so it is a `WAnchor` toggling a bool with the
field conditionally rendered. The plan must pin that the revealed field keeps its focus,
because CLAUDE.md's own trap is a field inside a branch that swaps, and
`test/ui/layouts/search_focus_test.dart` exists because of it.

## Stage 3 decision tree pruning

Nothing pruned. All six nodes were independent; no lock made a downstream option set moot.
One node was resolved by reading rather than asked, per the routing rule: `ProviderSession`
has no runtime credential setter, and whether to add a narrow one or re-run `start()` is a
code question. `start()` also migrates the schema and restores the cache, so re-running it
to adopt a credential does work the caller did not ask for. The plan adds a narrow
`adopt(XtreamCredentials)`.

## Stage 3.5 Oracle Sanity Check

Triggers fired: 1 (credential and password surface), 2 (two literal config snippets taken
from sources rather than from this codebase), 4 (a destructive purge with no rollback).
Trigger 3 did not fire, because "both routes" left nothing to tie-break.

Returned five findings, three CRITICAL, and refuted two of my own line anchors
(`XtreamCredentials.load` is `:159` not `:102`, `clear` is `:179` not `:122`). One premise
came back UNSUPPORTED rather than confirmed: Apple's `errSecMissingEntitlement` page was
unreachable through all three fetch layers, so finding 1's authority is an indexed TN3137
snippet plus corroborating evidence rather than the page itself.

### CRITICAL 1, revised into the plan: the locked entitlement route does not work as written

`macos/Runner.xcodeproj/project.pbxproj` sets `CODE_SIGN_IDENTITY = "-"` at project level in
all three configurations (`:460`, `:536`, `:592`) and the Runner target overrides it nowhere,
so a `DEVELOPMENT_TEAM` line alone leaves the build ad-hoc signed. An ad-hoc signature
carries no `application-identifier`, so the data-protection keychain still has no group to
place the item in and `-34018` stays. **Verified by reading the pbxproj myself.**

Fix in the plan: `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development"` on the Runner
target's Debug, Release and Profile, and a verification step that greps
`codesign -d --entitlements -` for `com.apple.application-identifier` before any step
asserts a successful `Vault.put`.

Also carried in: `usesDataProtectionKeychain: false` **omits** the flag rather than setting
it false (`FlutterSecureStorage.swift:227-231`), so items land in the legacy login keychain
and become invisible to a later read that sets the flag true. The magic PR body has to say
that flipping it later orphans stored items.

### CRITICAL 2, revised into the plan: `MagicVaultException` aborts the boot

Independently found by this planner before the oracle ran (see `verification-log.md`), and
the oracle sharpened it: the darwin plugin turns every non-success OSStatus into a
`FlutterError`, so any keychain read failure propagates out of `start()`, which is awaited
inside `Magic.init()` before `runApp()`, and the app boots to nothing.

Fix in the plan: catch `MagicVaultException` beside `FormatException` and map it to
`ProviderFault.unreachable` rather than `expired`, because `expired` is the one fault that
withholds the retry. `FakeVaultService` never throws, so a throwing fake is written first.

Ordering consequence for sign-out: `Vault.delete` throws the same way, so the vault delete
goes first and nothing destructive follows a failure.

### CRITICAL 3, put back to the user, who reversed the earlier lock

The oracle argued the purge destroys exactly what `accountKey` was designed to preserve.
**Verified both halves myself:** `catalogue_store.dart:118-121` records that the password is
excluded "on purpose rather than by omission", so a user who signs out to enter a rotated
password returns with the same key; and `replaceChannels` reads `_starredChannels(account)`
at `:182` **before** the `DELETE` at `:184` and re-applies it, so favourites and progress
come back on the next refresh for free.

**Locked, reversing D4:** sign-out clears the Vault record, the session's credential, client,
account, fault and clock, and stops any playing core. Catalogue rows are left alone. The
privacy argument that drove the first answer is weaker than it looked: every read is
account-scoped, and the rows carry no secret by construction.

### IMPORTANT 4, carried in with a pinned test

`_loadCredentials` falls through to the `--dart-define` development credential after a vault
miss, so an app launched by `tool/dev/run_with_provider.sh` is signed straight back in on
the next `start()`. Both the sign-out test and the guard test would pass in whichever
direction the tester happened to look. The seam already exists: tests inject
`developmentCredential: () => null`, one test asserts the redirect still fires with a define
present, and the walk script gets a line saying it must not run under the launcher.

### IMPORTANT 5, carried in

Containment holds today but nothing pins what is holding it. `WFormInput` defaults
`autocorrect` and `enableSuggestions` to true (`w_form_input.dart:108-109`), so the IME
learns the username, which is half `accountKey`. The password is safe in the semantics tree
only because `type: InputType.password` is the sole route to `obscureText` in Wind, and the
tree still discloses the exact length. And the provider driver installs no interceptors,
which is load-bearing and asserted nowhere.

Fix in the plan: `autocorrect: false, enableSuggestions: false` on all three visible fields,
and a test that resolves `XtreamClient.driverKey` and asserts the interceptor list is empty.

### Signing consequence, put back to the user

Making the identity explicit makes a signing certificate a build requirement on macOS: a
fresh checkout without one fails to build rather than failing to store. **Locked:** accept
that, keep the magic `mOptions` PR as the no-signing route, and say in `CLAUDE.md` which
route a given checkout is on.

## Confirmed Understanding: onboarding

### Goal
Today a user cannot enter a provider credential at all, and on macOS the app cannot store
one even if it could (`Vault.put` fails with OSStatus -34018). Target: a user types their
panel URL, user name and password on `/saglayici`, the app confirms them with a handshake
before storing, stores them in the Keychain, and a user with no credential is sent there
rather than shown a 23-channel fixture they cannot play. Acceptance: on a signed macOS debug
build, entering the local mock panel's `demo:demo` stores the credential, a restart lands on
`/` with the mock's 8 channels, one of them plays, and signing out lands back on
`/saglayici` with the Vault record gone.

### Scope
- IN: the credential form on the existing `/saglayici` screen with `WFormInput` validation;
  a confirming handshake before storing; `ProviderSession.adopt` and `signOut`;
  a redirect guard for a credential-less user; macOS signing plus the Keychain entitlement;
  catching `MagicVaultException` on the load path; a magic PR adding macOS storage options.
- OUT: publishing magic and bumping its constraint here; M3U playlist providers; a second
  provider or provider switching; the `/baslik/:id` identifier; loading skeletons; anything
  about the four screens' own layouts beyond the guard.

### Codebase Conventions (embedded in the plan)
- Naming: `lower_snake_case.dart`, `UpperCamelCase` types, `_leadingUnderscore` privates.
  User-facing strings Turkish; code, comments and commit messages English only.
- Error handling: handle deliberately or let it propagate, never a silent catch.
  `ArgumentError` for a programmer or config error, `FormatException` for an untrusted
  payload, `ProviderFault` as the vocabulary for provider failure.
- Comment density: heavy doc blocks carrying the why, the measurement and the failure mode,
  citing `file:line`. The most distinctive convention in the repo.
- Type discipline: strict. Explicit types on locals, `--fatal-infos --fatal-warnings`,
  `unawaited_futures: error`.
- File organization: `lib/app/{controllers,models,protocol,provider,providers,support}`,
  `lib/ui/{components,layouts}`, `lib/resources/views`. Atomic component folders.
- Import convention: relative within `lib/`, `package:` for external. `flutter/widgets.dart`
  plus `material.dart show Icons` only; never a Material widget for anything Wind expresses.
- Path aliases: n/a (Dart). Hard rule instead: never edit `**/*.g.dart`.
- TDD: `tdd`. Failing test first on every step, and prove the test discriminates by breaking
  the source once on purpose.
- LSP false positives: n/a.
- Test mount discipline: `pumpScreen` (`test/support/screen.dart:44`) for a whole screen,
  which wraps in `MaterialApp > WindTheme > Scaffold`, so an `Overlay` and a `Navigator`
  exist but `MagicRouter` is never built, so every navigation is a seam.
  `setUp(WindParser.clearCache)` is mandatory. `MagicTest.init()`, `Vault.fake()`/`unfake()`,
  `DatabaseManager().setConnection(sqlite3.openInMemory())`. Banned: overflow assertions
  (square test font). No test in the suite calls `enterText` today, so the form's tests are
  the first.

### Reuse Map
- `lib/ui/layouts/provider_settings_layout.dart` + its test: the placeholder the form replaces
- `lib/routes/app.dart:41`: `/saglayici`, already registered and titled
- `lib/app/protocol/xtream/xtream_credentials.dart:88`: base URL validation, all four fields required
- `:159` `load`, `:179` `clear`, `:92` `save`: the persistence surface, `clear` has no caller yet
- `lib/app/protocol/xtream/xtream_client.dart:84`: `handshake()` on any constructed client
- `lib/app/protocol/xtream/xtream_account.dart:205`: `classifyProviderFault`
- `lib/ui/components/provider_notice/provider_notice.dart:44`: renders all four faults
- `magic_middleware.dart:71`: `redirectTarget`, the guard hook
- `tool/xtream-mock/`: a local panel with real video and `demo:demo`

### Locked Decisions
- TDD: `tdd`
- Keychain: sign here AND open a magic PR; onboarding waits only on the signing
- Signing identity: `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"` explicitly on the
  Runner target, because the project-level `"-"` is what leaves it ad-hoc
- Validation: handshake first, store only when `classifyProviderFault` returns null
- First run: a `MagicMiddleware` redirect to `/saglayici`
- Sign-out: Vault record, session state and any playing core; catalogue rows stay
- Form: Wind's `WFormInput` family with `Form` plus `GlobalKey<FormState>`
- User agent: optional, behind a hand-built disclosure, because Wind ships none
- `ProviderSession` gains a narrow `adopt`, decided by reading rather than asked

### Deferred Ideas
- Publishing magic and bumping the constraint here: outward-facing, the user's call
- A separately confirmed "delete this provider's data" control: the shape the purge would
  have taken if it were not a sign-out side effect
- Extending `redactProviderSecrets` to the HTTP path: a second door with no traffic, which
  its own doc block argues against
- `MacOsOptions`'s legacy-keychain migration: flipping `usesDataProtectionKeychain` later
  orphans stored items, and nothing migrates them

### Risks Accepted
- A signing certificate becomes a macOS build requirement; a fresh checkout without one
  fails to build. Mitigated by the magic PR as the no-signing route and a `CLAUDE.md` note.
- Finding 1 rests on an indexed TN3137 snippet rather than the page, which was unreachable.
  The plan's first step verifies the outcome with `codesign` rather than trusting the source.
- The semantics tree discloses the password's exact character count even when obscured, so a
  committed dusk snapshot of the form leaks the length.

### Canonical References
- `macos/Runner.xcodeproj/project.pbxproj:460,536,592`: `CODE_SIGN_IDENTITY = "-"`
- `catalogue_store.dart:118-121`: why the password is excluded from `accountKey`
- `catalogue_store.dart:182-184`: the favourite carry-over that runs before the DELETE
- `magic_vault_service.dart:24`: no `mOptions`; `:39-62`: every operation throws
- `fake_vault_service.dart:37-59`: the fake never simulates a platform failure
- `macos_options.dart:24`: `usesDataProtectionKeychain` defaults to true
- `w_form_input.dart:74`: `extends FormField<String>`; `:108-109`: autocorrect defaults
- `test/support/screen.dart:69`: the harness wrapper, hence the navigation seam

## Stage 5.5 Review

One advisory pass by `ac:plan-reviewer`, fresh context, path only. Coverage 5/5 objectives.
Four CRITICAL, nine IMPORTANT, five notes. Every CRITICAL was verified against the source
before it was acted on, and all four held.

### CRITICAL, all fixed

**A dangling research reference.** Step 1 cited `research/librarian-keychain.md`, which did
not exist: Stage 1e is supposed to archive every subagent's output to `RESEARCH_DIR` and this
planner archived the survey and the verification log but not the six reports. Fixed by
writing the file, condensed to the claims the plan rests on with the agent's own
confidence separation preserved (documented / user-reported / inferred, and the TN3137
snippet marked as an indexed quote whose page was unreachable).

**Three CRITICALs that collapse into one deletion.** Step 7 asked for a test asserting the
provider driver carries no interceptor. That test **already exists**, at
`test/app/protocol/xtream/xtream_client_test.dart:182-198`, and it is better than the one
planned: it resolves `DioNetworkDriver` rather than the `NetworkDriver` interface (which
declares only `addInterceptor` and exposes no list at all), reads `dio.interceptors.length`
inside `configureDriver`, asserts it is **1** because dio seeds its own
`ImplyContentTypeInterceptor` so one is the empty state, and carries a non-vacuity control at
`:165-181` that ships a driver with `AuthInterceptor` to prove the capture is live. The
planned step would have asserted 0 through an interface with no list: unsatisfiable twice
over. Verified by reading the test. Step 7 is now the comment-only change at `quick`, and its
`Must NOT` records why no interceptor test belongs there.

### IMPORTANT, all fixed

**Six criteria that could never be satisfied**, and this is the sharpest one because Stage 5
has an audit specifically for it. `rg -c` prints **nothing** and exits 1 on no match, so
`rg -c <pattern> <file>` "prints 0" is unsatisfiable. Measured both tools rather than
reasoned: `rg -c` gave empty output and exit 1, `grep -c` gave `0` and exit 1. Rewritten as
`! rg -q <pattern> <file>` exits 0, which is the only form that is true when the pattern is
absent. The Stage 5 negative-test audit names exactly this class ("a flag the tool does not
support, where the shell exits non-zero with empty stdout and 'returns nothing' reads as
clean") and this planner applied it to the plan's commands and not to its own criteria.

Also fixed: step 4's `rg -c 'playback'` contradicted its own Description and the repo's
comment convention, so it is scoped to import lines; the user agent's default was never
specified anywhere although `XtreamCredentials` requires the field, so step 5 now supplies
`'Watchools/1.0'` and step 4 takes it as required; step 6's define criterion proved the
opposite of its claim (`() => null` is a define's absence) and is now two tests, one per
direction; step 8's `Commands` listed no fill, tap or sign-out and wrote none of its own
evidence files, and its `password=demo` criterion could not fail because the mock logs the
password as a path segment in a stream URL and legitimately as a query parameter in the
handshake, so the assertion moved to the app's own log; wave 3 carried a declared in-wave
dependency and is split, so step 5 has its own barrier; and step 5 now states that the
`FocusNode` is owned by the `State` rather than minted by `WFormInput`, without which the
focus-identity criterion could not be met.

### Notes applied

`xtream_account.dart`'s stale clause is at `:227` not `:230`; the placeholder layout has five
tests not four; `PlaybackFacade` ends at `:52` and `56-88` is the controller's doc block, so
both are cited separately now; and `--timeout 300` documents as applying to the `--cdp-port`
branch only, so it is dropped from step 8 (kept in step 1, where the concern is a cold build
rather than a dusk session, and where it is harmless).

`plan-check` re-run after the last edit: 0 errors, 0 warnings, 9 steps, 6 waves. Every
`research/*.md` path the plan cites resolves.
