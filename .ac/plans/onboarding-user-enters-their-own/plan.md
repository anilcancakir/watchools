# Plan: onboarding-user-enters-their-own

**Steps**: 9
**Waves**: 6
**Codebase State**: disciplined
**Auto mode**: true
**Generated**: 2026-09-10

## Research Summary

Six subagents plus one oracle. Raw reports in `research/`; every claim that moved a decision
was re-checked against the source first, and `research/verification-log.md` records the
three that were refuted or sharpened.

**The blocker is not what it looked like.** `-34018` is `errSecMissingEntitlement`, an
access-group check rather than a sandbox one, and `keychain-access-groups` is a *restricted*
entitlement, so its mere presence demands a provisioning profile. That is why adding it
failed the build. But the fix is not the entitlement alone:
`macos/Runner.xcodeproj/project.pbxproj` sets `CODE_SIGN_IDENTITY = "-"` at project level in
all three configurations (`:460`, `:536`, `:592`) and the Runner target overrides it
nowhere, so a `DEVELOPMENT_TEAM` line leaves the build ad-hoc signed, an ad-hoc signature
carries no `application-identifier`, and the data-protection keychain still has no group to
put the item in. The identity has to be set explicitly on the target, and the step verifies
its own outcome with `codesign` rather than trusting the research.

**Reads work, writes fail.** Measured first-hand in the running app rather than inferred:
`Vault.get('xtream_credentials')` returned null with no exception while `Vault.put` threw.
That is why the app boots and silently shows a 23-channel fixture.

**Every `Vault` operation can throw, and one path cannot survive it.**
`magic_vault_service.dart:39-62` wraps any `PlatformException` as `MagicVaultException`, on
reads as well as writes. `ProviderSession._loadCredentials` catches only `FormatException`,
and `start()` is awaited inside `Magic.init()` before `runApp()`, so a keychain read failure
boots the app to nothing at all with no way for the user to clear it.

**The purge was wrong and the oracle refuted it.** `catalogue_store.dart:118-121` records
that the password is excluded from `accountKey` "on purpose rather than by omission", so a
user who signs out to enter a rotated password comes back with the same key; and
`replaceChannels` reads `_starredChannels(account)` at `:182` **before** the `DELETE` at
`:184` and re-applies it. Deleting on sign-out throws away exactly what that design
preserves, in the most likely reason anyone signs out. Reads are already account-scoped and
the rows carry no secret, so the privacy argument that drove the first answer is weak.

**A redirect guard exists and is purpose-built.** `magic_middleware.dart:71`
`redirectTarget(String location)` resolves synchronously inside the router's `redirect`
callback, so the destination mounts exactly once, and `magic_router.dart:469` already skips
a self-redirect. `lib/app/kernel.dart` carries two non-comment lines, so this is the app's
first middleware.

**Nothing in this app has a form.** The only text field is `search_field.dart:73`, a raw
`WInput`. No `Form`, no `FormField`, no validator, and no test in the suite calls
`enterText`. `WFormInput extends FormField<String>` (`w_form_input.dart:74`) and defaults
`autocorrect` and `enableSuggestions` to true (`:108-109`), which would teach the IME the
user name, and that is half of `accountKey`. Wind ships no disclosure or accordion widget.

**The development define undoes a sign-out.** `_loadCredentials` falls through to
`XtreamCredentials.fromEnvironment` after a vault miss, so an app launched by
`tool/dev/run_with_provider.sh` is signed back in on the next `start()`, and both the
sign-out test and the guard test would pass in whichever direction the tester happened to
look.

## Codebase Conventions

- **Naming**: `lower_snake_case.dart` files, `UpperCamelCase` types, `_leadingUnderscore`
  privates. User-facing strings Turkish; code, comments and commit messages **English only**.
- **Error handling**: handle deliberately or let it propagate. **Never a silent catch.**
  `ArgumentError` for a programmer or config error, `FormatException` for an untrusted
  payload, `ProviderFault` as the vocabulary for provider failure. No fallback `try/catch`.
- **Comment density**: heavy doc blocks carrying the why, the measurement and the failure
  mode, citing `file:line`. This is the repo's most distinctive convention; a doc block that
  restates the signature is not one. No em-dash or en-dash in any artifact.
- **Type discipline**: strict. Explicit types on locals, `--fatal-infos --fatal-warnings`,
  `unawaited_futures: error`. **No linter or type-checker suppression, ever.**
- **File organization**: `lib/app/{controllers,models,protocol,provider,providers,support}`,
  `lib/ui/{components,layouts}`, `lib/resources/views` (excluded from the coverage
  denominator, so behaviour goes in the layout). Atomic component folders.
- **Import convention**: relative within `lib/`, `package:` for external.
  `flutter/widgets.dart` plus `material.dart show Icons` only; never a Material widget for
  anything Wind expresses. `Form` and `FormField` are in `widgets.dart`, so no exception is
  needed here.
- **Path aliases**: n/a (Dart). Hard rule instead: never edit `**/*.g.dart`.
- **TDD**: `tdd`. Failing test first on every step, **and prove the test discriminates by
  breaking the source once on purpose.** This session found three consecutive versions of one
  teardown test that could not fail; only breaking the source revealed it.
- **LSP false-positive whitelist**: n/a.
- **Test mount discipline**: `pumpScreen` (`test/support/screen.dart:44`) for a whole screen.
  It wraps in `MaterialApp > WindTheme > Scaffold`, so an `Overlay` and a `Navigator` exist
  but `MagicRouter` is never built, which is why every navigation is a constructor seam
  (`PlaybackLayout.onBack` is the precedent). `setUp(WindParser.clearCache)` is mandatory or
  every className resolves to nothing. `MagicTest.init()`, `Vault.fake()` / `Vault.unfake()`,
  `DatabaseManager().setConnection(sqlite3.openInMemory())`. **Banned**: overflow assertions,
  because the test font makes every glyph a square. Wind aliases print a harmless
  "shadows a built-in token" line on every run; it is not a failure.

## Reuse Map

| Existing | Provides | Used by |
|---|---|---|
| `lib/ui/layouts/provider_settings_layout.dart` | the placeholder screen and its five tests | step 5 replaces it |
| `lib/routes/app.dart:41` | `/saglayici`, registered and titled | step 6 adds middleware to the others |
| `lib/app/protocol/xtream/xtream_credentials.dart:88` | base URL scheme, host and authority validation; all four fields required | step 4's validators defer to it |
| `xtream_credentials.dart:92` `save`, `:159` `load`, `:179` `clear` | the persistence surface; `clear` has no caller yet | steps 2, 3, 4 |
| `lib/app/protocol/xtream/xtream_client.dart:84` | `handshake()` on any constructed client, so a credential is testable before it is stored | step 4 |
| `lib/app/protocol/xtream/xtream_account.dart:205` | `classifyProviderFault`; a wrong password is HTTP 200 `{"auth": 0}`, valid JSON, so `:219` yields `expired` | step 4 |
| `lib/ui/components/provider_notice/provider_notice.dart:44` | renders all four faults, `onOpenSettings` already points at `/saglayici` | step 5 |
| `magic_middleware.dart:71` | the pre-build redirect hook | step 6 |
| `lib/app/provider/provider_session.dart:123` `developmentCredential` | an already-injected seam, which is why the define's interference is testable at all | steps 3 and 6 inject it; step 8 is forbidden from running under the launcher |
| `tool/xtream-mock/` | a local panel with real video and `demo:demo` | step 8 |
| `test/support/screen.dart` | `pumpScreen`, the error-collecting harness | steps 5, 6 |

## Work Objectives

1. **A user can enter their own credential and the app stores it.** The form on `/saglayici`
   validates, confirms with a handshake, and only then writes to the Keychain.
2. **The Keychain actually accepts the write on macOS.** Today it does not, which is why
   nothing above objective 1 has ever been exercised on the one platform with a player.
3. **A credential-less user is sent to the form** rather than shown a fixture they cannot
   play.
4. **A user can sign out**, and doing so cannot leave a half state or destroy what
   `accountKey` was designed to preserve.
5. **No new leak surface.** The password reaches the Keychain and the panel's query string
   and nowhere else: not a semantics label, not an IME dictionary, not an interceptor log.

## Tier Calibration

Nine steps: one `verification`, one `junior`, five `junior-high`, one `senior`, one `infra`
at `junior-high`.

`rule-5-criticality` fires **once**, on step 4, and the before-and-after is concrete: before,
no credential can be entered or stored at all; after, a typed password is confirmed against a
third-party panel and written to the Keychain. That is a login flow deciding whether a
credential is accepted, not merely touching one.

It deliberately does **not** fire on two steps that look like it does. Step 5 adds fields to
a login form, which the rule's own text calls touching rather than deciding. Step 6 changes
which navigations get through, but a defect there shows a user a fixture rather than exposing
anything, and the rule protects surfaces where a defect "ships silently and is exploited or
loses money". Both sit at `junior-high` on `rule-none` instead, at 3.2x less than `senior`.

## Execution Strategy

Six waves. Waves 1 and 2 are independent of each other and could run together, but wave 1
is ordered first because **nothing after it can be verified on macOS until the Keychain
accepts a write**, and a green suite would otherwise certify a flow no human can complete.

- **Wave 1**: step 1 (signing and entitlements), step 2 (the vault-read failure path). Both
  touch the boot path; step 1 is native and step 2 is Dart, so they do not collide.
- **Wave 2**: step 3, the session's ability to adopt a credential and forget one. One file,
  one worker, because `adopt` and `signOut` share the private state they both reset.
- **Wave 3**: step 4, the controller that decides whether a credential is accepted.
- **Wave 4**: step 5, the form. Its own wave rather than an ordering note inside wave 3,
  because it imports the controller wave 3 creates and a barrier is what that needs.
- **Wave 5**: step 6, the redirect guard. Needs `hasCredentials` to be trustworthy, which is
  step 3.
- **Wave 6**: step 7 (the two invariant tests and one stale comment), step 8 (the end-to-end
  walk), step 9 (the magic sibling PR). Step 9 is in a different repository and blocks
  nothing here.

## Steps

### Wave 1

- [ ] **Step 1**: Sign the macOS target so the Keychain accepts a write

    > **DEFERRED mid-run, and the account-side half is already done.** `asc` created what was
    > actually missing, non-interactively: the App ID `com.watchools.app` (`SW57679G5G`, seed
    > `883V9SVA54`), this Mac registered as a device (`8Q46CPBVM9`, which a
    > `MAC_APP_DEVELOPMENT` profile requires and an iOS one does not), and the profile itself
    > (`6SRPP332YR`, ACTIVE to 2027) downloaded and installed. Three build attempts still fail:
    > automatic signing wants `-allowProvisioningUpdates`, which `flutter build macos` does not
    > pass and offers no way to; manual signing with the profile's name and then with its UUID
    > both answer `"Runner" requires a provisioning profile`. Xcode is not indexing a profile
    > that is installed, ACTIVE, and matches the bundle ID and team, and the remaining move is
    > interactive. **The repository was reverted to HEAD for this step** rather than left
    > carrying a configuration that fails every macOS build.
    >
    > Also correct the plan's own text when this resumes: the team is `883V9SVA54` for every
    > configuration. The split onto `936TDTZJN9` came from misreading `security find-identity`,
    > where an Apple Development certificate's parenthetical is the individual developer's ID
    > rather than the team.
    - **Type**: infra
    - **Tier**: junior-high
    - **Why this tier**: rule-none: the change is four lines of Xcode configuration, but the wrong four leave `-34018` in place while looking correct, and the authority for the right four is an indexed snippet rather than a page anyone could reach, so the step has to prove its own outcome instead of trusting its source.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/macos/Runner.xcodeproj/project.pbxproj`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/macos/Runner/DebugProfile.entitlements`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/macos/Runner/Release.entitlements`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`
    - **Description**: `Vault` is the Keychain and cannot write on macOS: every `Vault.put` fails with OSStatus `-34018`, measured in the running app with `com.apple.security.app-sandbox` both true and false. Two changes together, and neither works alone. **First**, add `<key>keychain-access-groups</key><array/>` to both entitlements files; the empty array is what the plugin's own example app ships and it asks for the app's default access group rather than a named one. **Second**, and this is the half that was missing, set `CODE_SIGN_IDENTITY[sdk=macosx*]` and `DEVELOPMENT_TEAM` on the **Runner target's** build configurations, and the values differ per configuration. The project level sets `CODE_SIGN_IDENTITY = "-"` in all three (`project.pbxproj:460`, `:536`, `:592`) and the target overrides it nowhere, so adding a team alone leaves the build ad-hoc signed; an ad-hoc signature carries no `application-identifier`, and the data-protection keychain has no group to place the item in.

**The two teams, and why they are not one.** `security find-identity -v -p codesigning` on this machine returns exactly two identities: `Apple Distribution: Anilcan Cakir (883V9SVA54)` and `Apple Development: Anilcan Cakir (936TDTZJN9)`. The team the user named, `883V9SVA54`, has **no** Apple Development certificate here, so pairing it with `"Apple Development"` sends Xcode looking for a certificate that does not exist, and automatic signing cannot mint one inside a headless `flutter build`. So: **Debug and Profile** take `"Apple Development"` with `DEVELOPMENT_TEAM = 936TDTZJN9`, which is the team whose development certificate is installed; **Release** takes `"Apple Distribution"` with `DEVELOPMENT_TEAM = 883V9SVA54`, which is where that certificate lives. This step verifies Debug only, because that is the configuration `flutter run` and every gate in this plan use; the Release pairing is written now so the file is not half-configured, and it is untested here. Do not touch the `RunnerTests` target. Then record in `CLAUDE.md`, in the paragraph that currently says `Vault` cannot write on macOS, that a signing certificate is now a **build requirement** on this platform and that a checkout without one uses the `--dart-define` development path instead.
    - **References**:
        - `macos/Runner.xcodeproj/project.pbxproj:460`, the project-level `CODE_SIGN_IDENTITY = "-"` that has to be overridden at target level
        - `macos/Runner/DebugProfile.entitlements:11-14`, the existing comment style for an entitlement: what it grants and what breaks without it
        - `research/librarian-keychain.md`, the full source trail including why `keychain-access-groups` being a restricted entitlement is what forces provisioning
    - **Done when**:
        - `flutter build macos --debug` exits 0
        - `codesign -d --entitlements - build/macos/Build/Products/Debug/watchools.app 2>&1 | grep -c 'com.apple.application-identifier'` prints a number greater than 0
        - `rg -c 'keychain-access-groups' macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements` prints 1 for each file
        - `grep -c 'CODE_SIGN_IDENTITY\[sdk=macosx\*\]' macos/Runner.xcodeproj/project.pbxproj` prints 3
        - `grep -c 'DEVELOPMENT_TEAM = 936TDTZJN9' macos/Runner.xcodeproj/project.pbxproj` prints 2 (Debug and Profile) and `grep -c 'DEVELOPMENT_TEAM = 883V9SVA54' macos/Runner.xcodeproj/project.pbxproj` prints 1 (Release)
    - **QA**: start the app inside this worktree with `./bin/fsa start --device macos --vm-service-port 8299 --timeout 300`, then run `./bin/fsa tinker --eval "Vault.put('probe','hello').then((_) => Vault.get('probe')).then((v) => debugPrint('ROUNDTRIP: \$v')).catchError((e) => debugPrint('VAULT_ERROR: \$e'))"`, wait 3 seconds, and grep the session log at `~/.artisan/sessions/*/flutter-dev.log`. Expect exactly `ROUNDTRIP: hello` and **no** `VAULT_ERROR` line. That command is the same one that produced the `-34018` measurement, so a pass here is a direct before-and-after. Then `./bin/fsa stop`.
    - **Must NOT**:
        - Do not disable `com.apple.security.app-sandbox`. It was tested and made no difference, because the sandbox was never the variable.
        - Do not name a specific access group in the array. An empty array asks for the app's own; a named one is what issue #804 shows still failing.
        - Do not change `PRODUCT_BUNDLE_IDENTIFIER`, and do not touch the `RunnerTests` target's configurations.
        - Do not commit anything under `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`; `.gitignore`'s `.swiftpm/` does not match it and it is Xcode's, not ours.

- [x] **Step 2**: Stop a keychain read failure from booting the app to nothing
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: a three-line widening of one existing catch, but it needs the surrounding contract read to pick the right fault, and it needs a test double the framework does not provide.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/provider_session.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/support/throwing_vault.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/provider_session_test.dart`
    - **Description**: `MagicVaultService` wraps any `PlatformException` as `MagicVaultException` on **reads** as well as writes (`magic/lib/src/security/magic_vault_service.dart:48-54`), and the darwin plugin turns every non-success `OSStatus` into one. `ProviderSession._loadCredentials` catches only `FormatException`, and `start()` is awaited inside `Magic.init()` before `runApp()`, so a keychain read failure propagates out and the app boots with no UI at all and no way for the user to clear the state. Widen the catch to `MagicVaultException` and map it to **`ProviderFault.unreachable`**, not `expired`: `expired` is the one fault whose panel withholds the retry and sends the user to settings, and a keychain that is momentarily unavailable is not a dead subscription. Keep the existing `FormatException` arm and its `expired` mapping exactly as it is, including its doc block. `FakeVaultService` overrides every operation with a no-throw body (`magic/lib/src/testing/fake_vault_service.dart:37-59`) and can never simulate this, so write `test/support/throwing_vault.dart` first: a `MagicVaultService` subclass whose `get` throws `MagicVaultException`, registered the way `Vault.fake()` registers its own.
    - **References**:
        - `lib/app/provider/provider_session.dart:334`, the `on FormatException` arm to widen, and the doc block above it explaining why an unreadable payload is `expired`
        - `lib/app/models/provider_fault.dart`, the four members and what each one's panel offers
        - `magic/lib/src/testing/fake_vault_service.dart:20-28`, the `forTesting()` super-constructor a throwing double has to use so `_storage` is never assigned
    - **Done when**:
        - `flutter test test/app/provider/provider_session_test.dart` passes
        - a new test asserts `session.fault == ProviderFault.unreachable` and `session.hasCredentials == false` after `start()` against the throwing vault, and asserts `start()` itself did **not** throw
        - `rg -c 'MagicVaultException' lib/app/provider/provider_session.dart` prints 1 or more
        - reverting only the new catch clause makes that test fail with an uncaught `MagicVaultException` rather than an assertion mismatch
    - **QA**: `flutter test test/app/provider/provider_session_test.dart`, then delete the `on MagicVaultException` clause and re-run to watch it fail, then restore. Report both outputs. Do not report the test as done on the passing run alone; `Vault.fake()`'s no-throw bodies are exactly why this branch has never been reachable.
    - **Must NOT**:
        - Do not map it to `expired`. That fault withholds the retry.
        - Do not catch bare `Exception` or add a `catch (_)`. The repo forbids a fallback catch outright.
        - Do not change what `FormatException` maps to, and do not touch `XtreamCredentials.load`.

### Wave 2

- [x] **Step 3**: Let the session adopt a credential and forget one
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: both methods reset the same five private fields in an order that is load-bearing, one of them owns a timer that leaks one instance per calendar day if disposed in the wrong order, and neither may reach into the playback layer even though a sign-out has to stop a playing core.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/provider_session.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/provider_session_test.dart`
    - **Description**: `_credentials`, `_client` and `_account` are set in `start()` and never cleared, so there is no way to accept a credential at runtime or to forget one. Add two public methods. **`Future<void> adopt(XtreamCredentials credentials)`**: store it in the vault via `credentials.save()`, set `_credentials`, rebuild `_client` as a fresh `XtreamClient(credentials)` so nothing keeps addressing the previous panel, clear `_account` and `_fault`, restore the cached catalogue for the new `CatalogueStore.accountKey(credentials)` the same way `start()` does, and `notifyListeners()`. **`Future<void> signOut()`**: `XtreamCredentials.clear()` **first**, so nothing destructive follows a failed vault delete, then null `_credentials`, `_client`, `_account` and `_fault`, then `_clock?.dispose()` **before** nulling `_clock` and `_midnight`, then empty `_channels` and `_titles`, then `notifyListeners()`. **Leave `catalogue_channels` and `catalogue_titles` alone**: `accountKey` excludes the password on purpose (`catalogue_store.dart:118-121`), so a user who signs out to enter a rotated password returns with the same key, and `replaceChannels` reads `_starredChannels(account)` at `:182` before its `DELETE` and re-applies it, so favourites and watch progress come back on the next refresh for free. Deleting them would throw that away in the most likely reason anyone signs out. This class must not import `lib/app/playback/`; stopping a playing core is the caller's job, and the caller is `lib/app/controllers/provider_setup_controller.dart`, which holds an injected seam for it.
    - **References**:
        - `lib/app/provider/provider_session.dart` `start()`, for the cache-restore shape `adopt` mirrors
        - `lib/app/provider/provider_session.dart:628-633`, the comment recording that a detached `TickingGuideClock` keeps a live one-minute timer, so the dispose has to precede the null
        - `lib/app/provider/catalogue_store.dart:118-121` and `:182-184`, why the rows stay
        - `lib/app/provider/provider_session.dart:123`, the `developmentCredential` seam a sign-out test has to neutralise
    - **Done when**:
        - `flutter test test/app/provider/provider_session_test.dart` passes
        - a test asserts that after `adopt`, `hasCredentials` is true, `streamUrlFor` on a channel with a `streamId` returns non-null, and the vault holds the record
        - a test asserts that after `signOut`, `hasCredentials` is false, `channels` and `titles` are empty, and `await Vault.get(XtreamCredentials.vaultKey)` is null
        - a test asserts that after `signOut` the **catalogue rows survive**, by adopting the same credential again and reading `CatalogueStore.channelsFor(accountKey)` back non-empty
        - `! rg -q "import '\.\./playback" lib/app/provider/provider_session.dart` exits 0. Written as a negated `-q` rather than `rg -c ... prints 0`, because `rg -c` prints **nothing** and exits 1 when it finds no match, so a "prints 0" criterion on it can never be satisfied
    - **QA**: `flutter test test/app/provider/provider_session_test.dart`. Then prove the row-survival test discriminates: add a `DELETE FROM catalogue_channels WHERE account = ?` into `signOut`, re-run, watch it fail, and remove it. Report both outputs.
    - **Must NOT**:
        - Do not delete catalogue rows, and do not add a purge method while here.
        - Do not import anything from `lib/app/playback/`.
        - Do not call `refresh()` from `adopt`. The caller decides when the network is touched, and the connection gate exists because that decision matters.
        - Do not re-run `start()` to adopt. It migrates the schema and does work the caller did not ask for.

### Wave 3

- [x] **Step 4**: Confirm a typed credential with a handshake before storing it
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, no credential can be entered or stored at all; after, a password typed by the user is confirmed against a third-party panel over plaintext HTTP and written to the Keychain. This step decides whether a credential is accepted, which is the login decision itself rather than a field on a form.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/controllers/provider_setup_controller.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/controllers/provider_setup_controller_test.dart`
    - **Description**: a `SimpleMagicController` that owns the submit flow, following `PlaybackController`'s shape: a narrow facade interface beside it for the screen to read, an injected `ProviderSession?` defaulting to the container, and an injected way to stop playback so this file does not import the engine. `submit({required String baseUrl, required String username, required String password, required String userAgent})` runs in this order: construct `XtreamCredentials` (which validates and normalises the base URL, and throws `ArgumentError` on a scheme-less one, so catch that and report it as a field error rather than letting it escape), construct a throwaway `XtreamClient(credentials)`, `await client.handshake()`, pass its `statusCode` and `body` plus `account: XtreamAccount.fromHandshake(...)` when the body parsed to `classifyProviderFault`, and **store only when that returns null** by calling `session.adopt(credentials)`. A wrong password arrives as HTTP 200 with `{"auth": 0}`, which is valid JSON, so it takes `xtream_account.dart:219` and classifies as `expired`: the user sees the real reason at the moment they caused it, instead of a stored-and-wrong credential producing the same fault on some later launch. **The user agent is not optional at this boundary**, whatever the form does: `XtreamCredentials`'s constructor requires all four fields with no default (`xtream_credentials.dart:88`), and a reuse report that claimed otherwise was refuted, see `research/verification-log.md`. So `submit` takes `String userAgent` as a **required** parameter and the screen is what supplies `'Watchools/1.0'` when the advanced disclosure was never opened; this controller never invents one, because a silently-defaulted header is what makes a reseller's rejection unexplainable. Expose `ProviderFault? fault`, a `bool busy` so the screen can refuse a double submit, and `String? fieldError`. Also expose `Future<void> signOut()` that stops any playing core through the injected seam **first** and then calls `session.signOut()`. Wire the seam in `app_service_provider.dart` next to the existing gate closure, which is the only place allowed to know about both layers.
    - **References**:
        - `lib/app/controllers/playback_controller.dart:23-52` for `PlaybackFacade`, the narrow interface a screen reads, and `:56-88` for the controller's own doc block on why it is narrow
        - `lib/app/controllers/playback_controller.dart:110`, the factory-seam pattern for a dependency that must not be constructed at `register()` time
        - `lib/app/providers/app_service_provider.dart:65`, the gate closure, and the comment on why only the composition root knows both layers
        - `lib/app/protocol/xtream/xtream_account.dart:205-239`, `classifyProviderFault`, and specifically `:219` for the wrong-password path
        - `lib/app/protocol/xtream/xtream_credentials.dart:88`, the `ArgumentError` this controller has to catch and turn into a field error
    - **Done when**:
        - `flutter test test/app/controllers/provider_setup_controller_test.dart` passes
        - a test with a faked panel answering `{"auth": 1}` asserts the credential reached the vault and `session.hasCredentials` is true
        - a test with a faked panel answering HTTP 200 `{"auth": 0}` asserts `fault == ProviderFault.expired`, `session.hasCredentials == false`, and `await Vault.get(XtreamCredentials.vaultKey) == null`, which is the assertion that the store did not happen
        - a test with `statusCode: 0` asserts `fault == ProviderFault.unreachable` and again nothing stored
        - a test passing `baseUrl: 'panel.example:8080'` asserts `fieldError` is set and that no request was sent, via the fake driver's `assertNothingSent()`
        - a test asserts `signOut()` stops playback before the session clears, by recording the order on the injected seam
        - `! rg -q "^import.*playback|^import.*watchools_player" lib/app/controllers/provider_setup_controller.dart` exits 0. Scoped to import lines deliberately: this step's own doc blocks say the word "playback" repeatedly, as they must, so a bare content grep would contradict the Description and the repo's comment convention at once
    - **QA**: `flutter test test/app/controllers/provider_setup_controller_test.dart`. Then prove the store-only-on-success test discriminates: move the `session.adopt` call above the fault check, re-run, and watch the `auth: 0` test fail on the vault assertion. Restore and report both outputs.
    - **Must NOT**:
        - Do not store the credential before the handshake has answered, and do not store it on any non-null fault.
        - Do not import `lib/app/playback/` or `watchools_player`.
        - Do not interpolate the password into any string, any log, any exception message or any `toString`. `XtreamCredentials.toString` already substitutes `***`; nothing here may go around it.
        - Do not call `session.refresh()` from `submit`. Adoption restores the cache; the first refresh is `boot()`'s job or the user's.
        - Do not add a retry loop. `unreachable` already means "try again" and the panel offers it.

### Wave 4

A wave barrier rather than an ordering note inside wave 3: this step imports
`lib/app/controllers/provider_setup_controller.dart`, which the previous wave creates, and a
declared dependency between two steps of one wave is what a barrier is for.

- [x] **Step 5**: Replace the placeholder with the real form
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: this is the app's first `FormField` of any kind and its first hand-built disclosure, so there is no in-repo pattern to copy, and three field-level settings that look cosmetic are the difference between a contained password and one the IME learns.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/provider_settings_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/resources/views/provider_settings_view.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/ui/layouts/provider_settings_layout_test.dart`
    - **Description**: turn the placeholder into a `Form` with a `GlobalKey<FormState>` and three `WFormInput` fields (panel URL, user name, password) plus a fourth behind an "advanced" disclosure for the user agent, a submit control, and a sign-out control shown only when a credential already exists. The password field takes `type: InputType.password`, which is the only route to `obscureText` in Wind and therefore the only thing that keeps the password out of the semantics tree. **All three visible fields take `autocorrect: false` and `enableSuggestions: false`**, because both default to true (`w_form_input.dart:108-109`) and the IME would otherwise learn the user name, which is half of `CatalogueStore.accountKey`. Wind ships no disclosure or accordion widget, so build one: a `WAnchor` toggling a `bool` in this widget's state with the field rendered conditionally. **When the disclosure was never opened, this screen supplies `'Watchools/1.0'`** as the user agent, because the controller's `submit` requires the parameter and `XtreamCredentials` requires the field: the default belongs here, where the user can see and change it, rather than being invented a layer down. Validators do the shallow checks only (non-empty, and a URL that starts with `http://` or `https://`); the real base URL validation belongs to `XtreamCredentials`'s constructor and the controller reports what it throws through `fieldError`. **The user-agent field's `FocusNode` is created in this `State`'s `initState` and disposed in its `dispose`**, then passed into `WFormInput.focusNode`; letting `WFormInput` mint its own would give the revealed field a fresh node on every rebuild, which is the defect `search_focus_test.dart` exists for and the reason the focus criterion below is about node identity rather than about something being focused. Render a `ProviderNotice` for the controller's `fault` rather than inventing a second error surface. The view becomes a `MagicStatefulView<ProviderSetupController>` like the other four screens, and the layout takes the facade plus an `onSaved` navigation seam defaulting to `MagicRoute.to('/')`, because `MagicRouter` is never built under `pumpScreen` and `PlaybackLayout.onBack` is the precedent for that.
    - **References**:
        - `lib/ui/layouts/playback_layout.dart:54`, the navigation-seam doc block and why an untestable control is the wrong trade
        - `lib/ui/layouts/provider_settings_layout.dart`, the current placeholder including its `items-start` comment: a column stretches its children, and the back affordance shipped as a full-width pill because of it
        - `lib/ui/layouts/support/page_gutter.dart:20-48`, the only spacing vocabulary allowed
        - `wind/lib/src/widgets/w_form_input.dart:74-110`, the constructor surface
        - `test/ui/layouts/search_focus_test.dart:28-32`, what a focus assertion has to pin: the same `FocusNode` instance, not merely that something is focused
    - **Done when**:
        - `flutter test test/ui/layouts/provider_settings_layout_test.dart` passes at both `desktop` and `mobile`
        - a test enters three values, taps submit, and asserts the facade received them; this is the suite's first `enterText`
        - a test asserts an empty user name blocks submit and renders a message, and that the facade was never called
        - a test asserts the password field's `WFormInput` carries `type: InputType.password`, and that all three visible fields carry `autocorrect: false` and `enableSuggestions: false`
        - a test asserts the user-agent field is absent until the disclosure is tapped and present after
        - a test asserts the revealed user-agent field keeps the **same `FocusNode` instance** across a rebuild triggered by typing in it
        - a test asserts the sign-out control is absent when the facade reports no credential and present when it does
        - `! rg -q 'Colors\.|Color\(0x' lib/ui/layouts/provider_settings_layout.dart` exits 0
    - **QA**: `flutter test test/ui/layouts/provider_settings_layout_test.dart`. Then prove the obscuring test discriminates by removing `type: InputType.password` and watching it fail. Then start the app and look at the screen with `./bin/fsa dusk:screenshot`: the placeholder shipped with a stretched control that every widget assertion passed over, so a screenshot is part of this step's QA rather than optional. Scope any `dusk:snap` **past** the password field or omit it: an obscured field still reports its exact character count in the semantics tree.
    - **Must NOT**:
        - Do not import a Material widget. `Form` and `FormField` are in `flutter/widgets.dart`.
        - Do not use a raw `Color`, a raw `TextStyle`, or any value not in the semantic theme.
        - Do not put validation logic that duplicates `XtreamCredentials`'s base URL rules into a validator. Two validators disagreeing is worse than one.
        - Do not keep a `TextEditingController` holding the password alive past `dispose`.
        - Do not write the password into a `semanticLabel`, a placeholder, or a test expectation string.

### Wave 5

- [x] **Step 6**: Send a credential-less user to the form
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: the mechanism is small but it loops forever unless it returns null at its own target, and it has to be registered in a file that is currently empty, so there is no working example in this repo to copy.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/middleware/ensure_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/kernel.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/routes/app.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/middleware/ensure_provider_test.dart`
    - **Description**: today the app boots to `/` unconditionally and shows a 23-channel fixture the user cannot play, because `GuideController.channels` falls back to it whenever `hasCredentials` is false (`guide_controller.dart:227`). Add a `MagicMiddleware` whose `redirectTarget(String location)` returns `'/saglayici'` when the resolved `ProviderSession` has no credential, and **null when `location` is already `/saglayici`**; magic's own doc block warns the redirect loops otherwise, and although `magic_router.dart:469` also skips a self-redirect, relying on that would make this file wrong if the router ever changed. Register it in `lib/app/kernel.dart`, which is all comments today, and apply `.middleware(['provider'])` to `/`, `/kutuphane`, `/baslik` and `/izle` but not to `/saglayici`. The ordering is already safe: `ProviderSession.start()` is awaited inside `Magic.init()` before `runApp()`, so `hasCredentials` is settled before `MaterialApp.router` first reads `routerConfig`.
    - **References**:
        - `magic/lib/src/http/middleware/magic_middleware.dart:46-71`, `redirectTarget`, its worked `EnsureAuthenticated` example, and the loop warning
        - `magic/lib/src/routing/route_definition.dart:105`, `middleware(List<dynamic>)` and the alias form
        - `magic/test/routing/redirect_guard_mount_test.dart`, the shape a guard test takes in the sibling
        - `lib/app/kernel.dart`, the commented `Kernel.route` usage block to follow
        - `lib/app/provider/provider_session.dart:123`, the `developmentCredential` seam, which a guard test must set to `() => null` or the define signs the user back in
    - **Done when**:
        - `flutter test test/app/middleware/ensure_provider_test.dart` passes
        - a test asserts `redirectTarget('/')` returns `'/saglayici'` with a credential-less session
        - a test asserts `redirectTarget('/saglayici')` returns **null** with the same session, which is the loop guard
        - a test asserts `redirectTarget('/')` returns null once the session has a credential
        - **two** tests about the development seam, because one alone proves the wrong thing. With `developmentCredential: () => null` (the seam neutralised, which is what a define's *absence* looks like) `redirectTarget('/')` returns `'/saglayici'`; with `developmentCredential: () => <a real credential>` it returns null, which is the app's behaviour under `tool/dev/run_with_provider.sh` and the reason a walk must not run there
        - `rg -c "middleware\(\['provider'\]\)" lib/routes/app.dart` prints 4
        - `! rg "MagicRoute\.page\('/saglayici'" lib/routes/app.dart | rg -q middleware` exits 0, so the form's own route is not guarded and cannot loop
    - **QA**: `flutter test test/app/middleware/ensure_provider_test.dart`, then prove the loop guard discriminates by removing the `location == '/saglayici'` early return and watching that test fail. Then start the app with **no** defines (`./bin/fsa start --device macos`), confirm with `./bin/fsa dusk:get_routes` that the location is `/saglayici` rather than `/`, and report it.
    - **Must NOT**:
        - Do not apply the middleware to `/saglayici`.
        - Do not use `MagicRouter.setInitialLocation`. It runs once at boot, so nothing sends the user back after a sign-out.
        - Do not redirect from `handle`. The doc block records that it runs post-mount and remounts the destination.
        - Do not remove the fixture fallback in either controller. It is out of scope and still the preview path.

### Wave 6

Step 9 is in another repository and blocks nothing here. Step 8 needs steps 1 through 6.

- [x] **Step 7**: Correct the fault comment this plan makes false
    - **Type**: code
    - **Tier**: quick
    - **Why this tier**: rule-none: one comment in one file, but the surrounding reasoning has to be read closely enough to change only the half that went stale.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_account.dart`
    - **Description**: `classifyProviderFault`'s step 3 comment (the block at `xtream_account.dart:222-231`, with the stale clause at `:227`) justifies classifying a first-launch generic denial as `throttled` partly with "since no onboarding screen exists". This plan builds that screen, so the clause becomes false and the next reader could take it as licence to reclassify. **The classification itself is correct and must not change**: an unparseable handshake genuinely says nothing about the credential, and a blocked address, a blocked user agent and a reverse proxy's HTML error page all land there, all three recoverable. Rewrite only the justification: `expired` is still the wrong answer because it is the fault that withholds the retry, and now that `/saglayici` carries a real form the reason is that retrying is the right offer for a denial the panel has not explained, not that the alternative destination is useless.
    - **References**:
        - `lib/app/protocol/xtream/xtream_account.dart:222-231`, the comment to rewrite and the reasoning that survives it
        - `lib/ui/components/provider_notice/provider_notice.dart:125`, which fault routes to settings rather than to a retry
    - **Done when**:
        - `! rg -q 'no onboarding screen exists' lib/app/protocol/xtream/xtream_account.dart` exits 0
        - `git diff --stat lib/app/protocol/xtream/xtream_account.dart` reports the only changed file, and `git diff lib/app/protocol/xtream/xtream_account.dart | rg -c '^[-+]\s*(if|return)'` prints nothing, proving no branch moved
        - `flutter test test/app/protocol/xtream/xtream_account_test.dart` passes unchanged
    - **QA**: `flutter test test/app/protocol/xtream/` and paste the count. Then `git diff` the file and read it aloud in the report: the whole step is one comment, so the diff IS the deliverable.
    - **Must NOT**:
        - Do not change any branch, condition or return of `classifyProviderFault`. Comment only.
        - Do not add an interceptor test. One already exists and is better than a new one would be: `test/app/protocol/xtream/xtream_client_test.dart:182-198` resolves `DioNetworkDriver`, reads `dio.interceptors.length` inside `configureDriver`, asserts it is **1** because dio seeds its own `ImplyContentTypeInterceptor` so one is the empty state, and has a non-vacuity control at `:165-181` that ships a driver carrying `AuthInterceptor` to prove the capture is live. An earlier draft of this plan asked for a duplicate that would have asserted 0 through an interface (`NetworkDriver`) that exposes no interceptor list at all.
        - Do not extend `redactProviderSecrets` to the HTTP path. Its own doc block argues against a second door with no traffic.

- [ ] **Step 8**: Walk the whole flow on the running app against the local mock

    > **DEFERRED with step 1.** This walk's whole point is that the credential survives a
    > restart, which needs a real Keychain write, and its `Must NOT` forbids the
    > `--dart-define` path that would fake it. Run it in the same sitting as step 1.
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**: every gate can be green while the flow a person performs is broken, and this session has twice found a defect that only looking could see. Drive the real app on macOS against `tool/xtream-mock`, which serves real video and costs no provider request. **Start the app with no `--dart-define`**, because `tool/dev/run_with_provider.sh` would supply a credential and the redirect under test would not fire. Sequence: boot and confirm the location is `/saglayici` rather than `/`; fill the three fields with `http://127.0.0.1:3300`, `demo` and `demo`; submit; confirm the app lands on `/` showing 8 channels rather than 23; tap a channel and confirm the mock's request log shows a `/live/demo/demo/` request followed by the tokenised `302` target; restart the app and confirm it lands on `/` directly, which proves the credential survived in the Keychain; then sign out and confirm the location returns to `/saglayici` and `Vault.get` reads null. Capture the mock's request log and one screenshot of the form.
    - **Commands**:
        - `node tool/xtream-mock/server.mjs > /tmp/mock.log 2>&1 &`
        - `./bin/fsa start --device macos --vm-service-port 8299`
        - `./bin/fsa dusk:get_routes | tee -a .ac/plans/onboarding-user-enters-their-own/evidence/08-routes.txt`
        - `./bin/fsa dusk:screenshot --output=.ac/plans/onboarding-user-enters-their-own/evidence/08-form.png`
        - `./bin/fsa dusk:observe --roles textbox,button` (read the q-handles; the three fills below use them)
        - `./bin/fsa dusk:fill --ref <panel url handle> --text http://127.0.0.1:3300`
        - `./bin/fsa dusk:fill --ref <username handle> --text demo`
        - `./bin/fsa dusk:fill --ref <password handle> --text demo`
        - `./bin/fsa dusk:exceptions --clear`
        - `./bin/fsa dusk:find --text Kaydet` then `./bin/fsa dusk:tap --ref <the handle it returns>`
        - `./bin/fsa dusk:get_routes | tee -a .ac/plans/onboarding-user-enters-their-own/evidence/08-routes.txt`
        - `./bin/fsa dusk:snap --grep 'kanal ·' --interactiveOnly`
        - `./bin/fsa dusk:find --text '<a channel name from the snap> izle'` then `./bin/fsa dusk:tap --ref <handle>`
        - `./bin/fsa dusk:exceptions`
        - `./bin/fsa restart`
        - `./bin/fsa dusk:get_routes | tee -a .ac/plans/onboarding-user-enters-their-own/evidence/08-routes.txt`
        - `./bin/fsa dusk:navigate --route /saglayici` then `dusk:find` and `dusk:tap` the sign-out control
        - `./bin/fsa dusk:get_routes | tee -a .ac/plans/onboarding-user-enters-their-own/evidence/08-routes.txt`
        - `cp /tmp/mock.log .ac/plans/onboarding-user-enters-their-own/evidence/08-mock-requests.txt`
        - `./bin/fsa stop`
    - **Done when**:
        - `dusk:get_routes` reports `/saglayici` on the first boot with no credential stored
        - after submit, `dusk:get_routes` reports `/` and a snapshot scoped with `--grep` shows a channel count of 8
        - `/tmp/mock.log` contains a line matching `GET /live/demo/demo/` and a following line matching `GET /live/play/`
        - after `./bin/fsa restart`, `dusk:get_routes` reports `/` without any credential being re-entered
        - after sign-out, `dusk:get_routes` reports `/saglayici`
        - `./bin/fsa dusk:exceptions` reports `"count":0` at every checkpoint, read after a `--clear` so a stale entry from an earlier screen is not attributed here
        - the **app's own** session log at `~/.artisan/sessions/*/flutter-dev.log` contains no `demo` at all: `! rg -q demo ~/.artisan/sessions/*/flutter-dev.log` exits 0. The mock's log is deliberately **not** asserted on, because the handshake legitimately carries `password=demo` in its query string (`server.mjs:954` logs `${method} ${path}${search}`) and a stream URL carries it as a path segment rather than as `password=`, so a criterion phrased against `password=` in a stream path could never fail and would have read as a passing security check
    - **Evidence**:
        - `.ac/plans/onboarding-user-enters-their-own/evidence/08-form.png`
        - `.ac/plans/onboarding-user-enters-their-own/evidence/08-mock-requests.txt`
        - `.ac/plans/onboarding-user-enters-their-own/evidence/08-routes.txt`
    - **Must NOT**:
        - Do not run this under `tool/dev/run_with_provider.sh`, and do not pass any `XTREAM_*` define. The development credential makes the redirect step pass for the wrong reason.
        - Do not use a real provider credential. The mock serves real video and the measured account allows one connection.
        - Do not commit a `dusk:snap` of the form into the evidence files. An obscured field still discloses its exact character count.

- [x] **Step 9**: Open the magic PR that unblocks an unsigned checkout
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: a different repository under its own rules and its own definition of done, and the option's semantics are the opposite of what its name suggests, so writing it from the name alone ships the wrong behaviour.
    - **Files**:
        - `/Users/anilcan/Code/fluttersdk/magic/lib/src/security/magic_vault_service.dart`
        - `/Users/anilcan/Code/fluttersdk/magic/lib/src/testing/fake_vault_service.dart`
    - **Description**: `MagicVaultService`'s constructor passes only `aOptions` and `iOptions` (`:24-29`), so macOS gets `flutter_secure_storage`'s default `usesDataProtectionKeychain: true` (`macos_options.dart:24`) and a consumer cannot configure it through the facade at all. Add `mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device, usesDataProtectionKeychain: false)` so an unsigned macOS build can store a secret. The PR body has to state the cost, because the option's name misleads: `false` does not set the flag false, it **omits** the key entirely (`FlutterSecureStorage.swift:227-231`), so the item lands in the legacy login keychain and becomes invisible to any later read that sets the flag true. There is no migration, so a consumer that later gains signing loses every stored secret silently. Second commit on the same PR: give `FakeVaultService` a way to simulate a platform failure, because it overrides every operation with a no-throw body (`:37-59`), so no consumer can test its own vault-failure branch. watchools works around this with a local double at `test/support/throwing_vault.dart`; that workaround is what this commit makes unnecessary for the next consumer, and it is not deleted here. **Read `/Users/anilcan/Code/fluttersdk/magic/CLAUDE.md` first**; that repository's conventions win inside its tree. Branch off its default branch, run its own gates, open the PR, and stop there.
    - **References**:
        - `/Users/anilcan/Code/fluttersdk/magic/CLAUDE.md`, that project's rules, which override this plan's conventions inside its tree
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/.claude/rules/workflow.md`, the sibling flow: a branch, that project's gates, a PR, and CI green before merge
        - `magic/lib/src/security/magic_vault_service.dart:24-29`, the constructor to extend
        - `magic/lib/src/testing/fake_vault_service.dart:37-59`, the no-throw overrides
    - **Done when**:
        - that repository's own test suite and analyzer pass locally
        - a test asserts the fake can be made to throw `MagicVaultException` from `get` and from `put`
        - `gh pr view --json state` on the new PR reports `OPEN`
        - the PR body names the legacy-keychain migration cost in its own paragraph
    - **QA**: run whatever `magic/CLAUDE.md` names as that project's gates and paste the output. Then confirm the PR exists with `gh pr view`.
    - **Must NOT**:
        - Do not publish magic to pub.dev, do not bump `fluttersdk_wind` or `magic` in this app's `pubspec.yaml`, and do not touch `pubspec.lock`. That is outward-facing and the user decides it.
        - Do not merge the sibling PR. `.claude/rules/workflow.md` requires its CI green first, and the standing authorisation covers this repository only.
        - Do not change the iOS or Android options.
        - Do not commit `pubspec_overrides.yaml` in either repository.

## Risks Accepted

- **A signing certificate becomes a macOS build requirement.** After step 1, a fresh checkout
  on a machine without an Apple Development certificate fails to *build* rather than failing
  to store, which is a worse failure to debug. Accepted because the alternative leaves the
  product unusable on its only playing platform. Mitigated two ways: step 9's magic PR is the
  no-signing route, and step 1 records in `CLAUDE.md` which route a given checkout is on.
- **Step 1's authority is an indexed snippet, not a page.** Apple's `errSecMissingEntitlement`
  page and TN3137 were unreachable through all three fetch layers, so the reasoning rests on
  an indexed TN3137 quote plus the corroborating shape of the plugin's own example project and
  issue #804. Accepted because the step verifies its own outcome with `codesign` and a live
  `Vault.put` round trip rather than trusting the source.
- **An obscured field still discloses its exact character count** in the semantics tree
  (`editable.dart:1348-1350` substitutes one bullet per character). So a committed `dusk_snap`
  of the form leaks the password's length. Accepted; step 5 and step 8 both forbid snapping the
  field, which is a discipline rather than a guarantee.
- **The development define signs a signed-out user straight back in.** `_loadCredentials`
  falls through to `XtreamCredentials.fromEnvironment` after a vault miss, so an app launched
  by `tool/dev/run_with_provider.sh` has a credential again on the next `start()`. Accepted
  because the seam that makes it testable already exists; steps 6 and 8 both pin it, and step 8
  is forbidden from running under the launcher.
- **Sign-out leaves the account's catalogue rows on disk.** A deliberate reversal of the first
  answer, argued in `interview-log.md` under CRITICAL 3: `accountKey` excludes the password on
  purpose, so a password rotation returns to the same key and `replaceChannels` carries
  favourites and progress over for free. Accepted rather than mitigated; the wipe, if wanted,
  is a separately confirmed control and is deferred below.

## Cross-Project Observations

- **magic exposes no macOS options for `flutter_secure_storage`.**
  `magic/lib/src/security/magic_vault_service.dart:24-29` passes only `aOptions` and
  `iOptions`, so every consumer on macOS gets the plugin's default
  `usesDataProtectionKeychain: true` and cannot reach the workaround that makes an unsigned
  build work. Step 9 is the PR. The fix is four lines; the value is that no other consumer has
  to rediscover `-34018` from scratch.
- **`FakeVaultService` cannot simulate a platform failure.**
  `magic/lib/src/testing/fake_vault_service.dart:37-59` overrides every operation with a
  no-throw body, so the branch every consumer needs for a locked keychain or a lost entitlement
  is untestable through the framework's own double. Second commit on step 9's PR.
- **`Vault` has no capability probe.** No `isAvailable`, `canWrite` or equivalent anywhere in
  the facade, so a consumer cannot ask whether secure storage works before offering the user a
  form that depends on it. Not filed as work here because the exception path is a sufficient
  answer once step 2 handles it, but it is the reason step 2 exists.
- **`.gitignore`'s `.swiftpm/` does not match Xcode's `xcshareddata/swiftpm/`**, so two
  untracked directories appear after any macOS build. One line in this repo's `.gitignore`;
  out of scope here and mentioned so step 1 does not commit them by accident.

## Deferred Ideas

- **Publishing magic and bumping the constraint here.** Outward-facing, and
  `.claude/rules/workflow.md` puts it after the sibling's own CI is green. Step 9 stops at an
  open PR.
- **A separately confirmed "delete this provider's data" control.** The shape the purge would
  have taken if it were not a side effect of signing out. Wanted on a shared machine, but it
  needs a confirmation dialog and this app has none.
- **Migrating items out of the legacy keychain.** If a consumer ever flips
  `usesDataProtectionKeychain` from false to true, every stored secret silently reads as null.
  The plugin ships no migration. Named in step 9's PR body rather than solved.
- **Extending `redactProviderSecrets` to the HTTP path.** Its own doc block argues against a
  second door with no traffic, and step 7 pins the invariant that actually holds the URL in
  (the provider driver installs no interceptors).
- **A first-run experience distinct from the settings form.** Step 6 sends a credential-less
  user to `/saglayici`, which is the settings screen wearing an onboarding hat. A real
  welcome surface is a design question, not a wiring one.
- **Onboarding for an M3U playlist provider.** `CLAUDE.md` names it as a supported provider
  shape; nothing in the protocol layer implements it, so it is a plan of its own.
