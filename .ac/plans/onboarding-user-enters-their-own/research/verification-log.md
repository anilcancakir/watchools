# Verification log

Every subagent claim that would move a decision, checked against the source before it was
allowed to. A refuted claim is recorded so a compaction cannot let it quietly return.

## REFUTED: `XtreamCredentials`'s `userAgent` has a default

Claimed by the reuse explore: "`xtream_credentials.dart:137` -- userAgent parameter has a
default value of `'Watchools/1.0'`, making it optional at the call site."

Checked `:88`:

```dart
XtreamCredentials({required String baseUrl, required this.username, required this.password, required this.userAgent})
```

`required`, no default. The `'Watchools/1.0'` at `:137` is the default of
`fromEnvironment`'s own named parameter, which is a different member added by PR #28. The
report conflated the constructor with the factory.

**Why it matters:** the onboarding form has to produce a user agent one way or another. It
is either a fourth field, or a constant the form supplies. That is now a decision node
rather than something the constructor absorbs.

## CONFIRMED, and sharper than reported: a first-launch denial classifies as `throttled`

Claimed: "on first handshake with no prior account (account==null) and non-JSON body, the
fault is throttled, not expired".

Checked `xtream_account.dart:230`, and the comment above it says more than the claim did:

```
// 3. The generic denial with no account behind it, which is the first-launch
//    case: the handshake itself came back as unparseable text. That says
//    nothing whatsoever about the credential, so it must not be read as
//    `expired`, the one fault that withholds the retry
//    (`provider_notice.dart`'s button routes to settings for it and nowhere
//    useful, since no onboarding screen exists).
```

**Two things follow.** The classification itself stays correct after onboarding exists: an
unparseable handshake genuinely says nothing about the credential, and a blocked address, a
blocked user agent and a reverse proxy's HTML page all land there. But the parenthetical
justification goes stale the moment this plan ships, because the settings destination stops
being "nowhere useful". That comment needs updating in the same plan, or the next reader
takes it as licence to reclassify.

**And the case onboarding actually cares about is fine.** A wrong password returns HTTP 200
with `{"auth": 0}`, which is valid JSON, so it takes step 2 at `:219` and yields `expired`.
Verified by reading the branch, not inferred.

## CONFIRMED: nothing in this app has a form, a validator or a field error

Claimed by the form explore. Spot-checked: `search_field.dart:73` is a `WInput` bound with
value plus onChanged, `provider_notice.dart` is the only error surface and takes a
`ProviderFault` rather than a string, and no widget test in the suite calls `enterText`.
Consistent with what this planner already knew from writing
`provider_settings_layout_test.dart` today, whose assertion at `:48-49` is that the screen
has no `WInput` at all.

## CONFIRMED: magic has a redirect guard, and its doc block names the loop trap

`magic/lib/src/http/middleware/magic_middleware.dart:71` is
`String? redirectTarget(String location) => null;`, and the doc block above it says it is
"evaluated synchronously inside the router's `redirect` callback, so a redirect-style guard
resolves before any page is built and the destination view mounts exactly once", prefers it
over an imperative `MagicRoute.to()` inside `handle`, and warns: "Always return `null` when
[location] already equals the target, otherwise the redirect loops."

Applied through `RouteDefinition.middleware(List<dynamic>)`
(`magic/lib/src/routing/route_definition.dart:105`), which takes either a string alias
registered in `Kernel` or a factory closure. `lib/app/kernel.dart` carries **two**
non-comment lines, so nothing is registered today and the alias route is unused.

The ordering works: `ProviderSession.start()` is awaited inside `Magic.init()`, which
`main()` awaits before `runApp()`, so `hasCredentials` is settled before the router is ever
read.

## CONFIRMED: a sign-out leaves the previous subscriber's catalogue in SQLite

`catalogue_store.dart` has exactly two `DELETE` statements, `:184` and `:218`, both
`WHERE account = ?` and both inside `replaceChannels` / `replaceTitles`. There is no
unconditional purge and no delete-by-account entry point. Those two run only during a
refresh, which needs a credential, so after a sign-out the rows stay with nobody to replace
them. That is a privacy defect rather than stale cache, and it needs a step.

## CONFIRMED first-hand, and more precisely than reported: on macOS reads work, writes fail

The Vault explore reports that `get()` returns null only for a missing key and throws
`MagicVaultException` on a platform error, so it left open whether reads fail on macOS too.

Measured directly in the running app during this session rather than inferred:
`Vault.get('xtream_credentials')` returned `null` with no exception, while `Vault.put`
threw `MagicVaultException ... Code: -34018`. So the read path is intact and only the write
path is blocked, which is why the app boots and silently shows the fixture.

## A hole this exposes, found by reading the contract against the app

`Vault.get` CAN throw `MagicVaultException` (`magic_vault_service.dart:48-54`), and
`XtreamCredentials.load()` does not catch it, and `ProviderSession._loadCredentials` catches
only `FormatException`. So a platform read error propagates out of `start()`, which is
awaited inside `Magic.init()` before `runApp()`: the app would abort with no UI at all and
no way for the user to clear the bad state. Not reachable on macOS today because reads
succeed, but it is the same class as the `FormatException` case that path already handles
deliberately, and onboarding is what makes it matter.

## Sibling gap: magic exposes no macOS options for flutter_secure_storage

`magic_vault_service.dart:24-29` hardcodes iOS `first_unlock` and Android defaults and
exposes nothing for macOS, Windows, Linux or Web. `flutter_secure_storage` itself has
`MacOsOptions`. Whether one of those options is the actual fix for -34018 is what the
Keychain librarian brief is for; if it is, the fix belongs in magic rather than here, and
this app cannot reach it through the facade.
