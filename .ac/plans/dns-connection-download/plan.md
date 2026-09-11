# Plan: dns-connection-download

**Steps**: 9
**Waves**: 7
**Codebase State**: disciplined
**Auto mode**: true
**Generated**: 2026-09-11

## Research Summary

Six `ac:explore` briefs (internal, archived at `research/explore-findings.md`) and ten `ac:librarian`
briefs that ran immediately before this plan (external, archived at `research/external-findings.md`,
load-bearing claims re-verified at source by the main thread). One `ac:oracle` on the security
trigger, whose report refuted the premise the largest half of the original scope rested on.

**The refuted premise, and why this plan is smaller than the request.** The original scope pinned a
resolved address into the stream URL so a user's chosen resolver would reach playback. It cannot:
`.ac/research/player-layer.md:26-28` records, from a measurement against the real provider, that the
panel answers `302` to a **different origin**, and `libavformat/http.c:487-509` shows the redirect
loop replacing `s->location` and jumping to `redo` while `s->headers` survives untouched. So pinning
the panel host pins the connection that gets redirected rather than the one that carries video, and
a forced `Host` header rides the redirect to an origin it does not name, turning a channel that
plays today into a 404 on any vhost-multiplexing edge. Both halves verified at source before the
rescope.

**What that leaves is the stronger half anyway.** When a Turkish ISP cannot resolve a panel domain
the failure lands on `player_api.php` first: onboarding fails, no catalogue arrives, and the user
never reaches playback to care about the stream host. The resolver therefore belongs on the panel
API, where it also works correctly on https, because `SecureSocket.secure(socket, host: <name>)`
keeps SNI and certificate validation against the real hostname while connecting to an address we
chose. That is precisely what libmpv cannot do.

**The mechanism, and why it needs no sibling release.** `dio` is not a direct dependency and
`CLAUDE.md` forbids reaching for it; `configureDriver` hands over a `Dio` whose type the app never
names. Installing a connection factory through dio would therefore need a new capability in magic,
a sibling PR and a publish. `HttpOverrides.global` (Dart SDK `_http/overrides.dart:44`) reaches the
same place from outside: dio's IO adapter constructs a plain `HttpClient()`, which consults the
override. First-party Dart, no new dependency, no sibling blocker.

**Three measurements that shaped defaults**, taken on the owner's own Turkish line and flagged by
him as unrepresentative (1 Gbit TurkNet, AdGuard on OpenWRT), so treat them as the optimistic end:
a cold DoH query costs 71 to 108 ms against 13 ms for plain UDP, which is why DoH is a fallback and
never the default path; the panel host has exactly one A record, which is why no address-racing work
appears here; and the round trip to the origin is 86 ms, which is where tap-to-first-frame actually
goes and is not a DNS problem.

## Codebase Conventions

1. `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` members. Tests mirror the source
   path exactly: `lib/app/network/host_resolver.dart` is tested at
   `test/app/network/host_resolver_test.dart`.
2. **No fallback catch that swallows.** The house shape is `provider_session.dart:429-433`: catch the
   specific exception, map it into a vocabulary the UI already renders, and state in the doc block
   that the handling is deliberate.
3. **Doc blocks carry the contract, the failure mode, the unit, and the measurement that decided a
   number.** A doc block restating the parameter list is a defect here. Every number in this plan
   that reaches source carries its measurement with it.
4. Strict explicit types. `dynamic` only where a wire boundary forces it.
5. Nested by role under `lib/app/`, no barrel exports there. A UI component folder is the exception,
   with `index.dart` plus dotted `*.recipe.dart` and `*.preview.dart`.
6. Relative imports within `lib/`. No path aliases.
7. Generated and never edited: `lib/config/wind_theme.g.dart`, `lib/app/_plugins.g.dart`,
   `lib/_previews.g.dart`, and every platform plugin registrant.
8. **Wind owns styling.** `className` strings and `W`-prefixed widgets only. Never `Colors.*`, a raw
   `Color(0x...)`, or a bare `TextStyle`. Colours come from the semantic aliases in the generated
   theme.
9. Test mount discipline: `pumpScreen` (`test/support/screen.dart:44`) for a screen, `wrapWithTheme`
   (`test/support/wind_test_app.dart:34`) for a leaf, `setUp(WindParser.clearCache)` mandatory on any
   widget test, `MagicApp.reset(); Magic.flush();` for container tests, plus `MagicTest.init()` and
   `Vault.fake()` where a vault or database is touched. Assert an overridden `env()` value, never a
   default, because `.env` is a real asset during `flutter test`.
10. **TDD, and one rule beyond it.** Failing test first. And a test is not written until it has been
    proved to fail with the fix removed: break the source on purpose, watch the test go red, put the
    source back. `CLAUDE.md` records five tests in one sitting that each passed with their fix
    removed, and reading them caught none of it.

No linter or type-checker suppression, anywhere, for any reason.

## Reuse Map

| Need | Reuse | Anchor |
|---|---|---|
| Rebuilding a `Uri` field by field | the shape, not the function | `lib/app/protocol/xtream/xtream_stream_url.dart:113-122` |
| Validating a user-typed URL | `_normaliseBaseUrl`'s shape | `lib/app/protocol/xtream/xtream_credentials.dart:401` |
| Reading a required JSON field | `_requireString`'s `is! String` check | `lib/app/protocol/xtream/xtream_credentials.dart:419-427` |
| Classifying a network failure | `ProviderFault` and its classifier | `lib/app/models/provider_fault.dart:28`, `xtream_account.dart:210` |
| A named predicate over that enum | the extension pattern | `lib/app/models/provider_fault.dart:93` |
| The engine-wide mpv option set | add keys to the existing dictionary | `MpvEngine.swift:36-72`, loop at `:107-111` |
| A settings field, end to end | the `userAgent` chain | model `xtream_credentials.dart:78`, form `provider_settings_layout.dart:233-245`, facade `provider_setup_controller.dart:43-48`, persistence `provider_session.dart:344` |
| The disclosure | the hand-built `WAnchor` | `lib/ui/layouts/provider_settings_layout.dart:278-301` |
| Faking HTTP in a test | `FakeNetworkDriver` under `XtreamClient.driverKey` | `test/app/protocol/xtream/xtream_client_test.dart:60-66` |
| Asserting what actually went on the wire | `_RawPanel`, a real loopback `ServerSocket` | `test/app/protocol/xtream/xtream_client_test.dart:98-134` |
| The m3u8-only fixture | channel with `formats: ['m3u8']` | `tool/xtream-mock/catalogue.mjs:267` |

**Built fresh, because nothing exists**: a TTL cache (the nearest is a day-boundary recompute at
`provider_session.dart:828`, a different invalidation rule), an async timeout on provider traffic
(`lib/config/network.dart:14` sets one on the `api` driver only, never on `provider_network`), and a
DNS test double (no test in the suite fakes resolution or a socket connect).

## Work Objectives

1. **Stop the player evicting itself.** FFmpeg's HLS demuxer opens a second connection for the next
   segment by default, and this account allows one.
2. **Make a failing resolver a bounded, recoverable failure instead of an unbounded hang**, and give
   the user a resolver that actually applies to the requests that fail first.
3. **Say what the feature does and does not cover**, on screen, rather than letting the user find out.
4. **Correct three claims in our own documentation** that this research falsified.

## Tier Calibration

`quick` for a single-file mechanical edit. `junior` for one to three files of ordinary logic.
`junior-high` where the coupling or the context depth is borderline. `senior` for cross-layer work,
new infrastructure, or an edge case that has already bitten somebody.

Two steps are `senior`: the resolver itself, because it is new infrastructure plus a test double
that does not exist anywhere in the suite, and the override install, because a wrong `SecureSocket`
call silently sends cleartext to port 443 and the Dart SDK's own factory skips the TLS branch.

## Execution Strategy

Seven waves. Wave 1 runs two independent steps in parallel and wave 6 runs two more; waves 2 through
7 **must run in sequence**, each importing what the wave before it created.

Every step that touches Dart runs `flutter analyze --fatal-infos --fatal-warnings` and the tests it
names before it reports done. The final step is the gate over all of it.

One rule specific to this plan: **prove an mpv option took effect rather than asserting that it was
set.** `options.rst:8032` states that unknown or misspelled keys on a passthrough are silently
ignored, and `MpvEngine.swift:59-60` already carries a comment about having been bitten by exactly
that. Step 9 is where the proof lives.

### Dependency Notes

Three couplings a worker cannot see from inside its own step, so they are named here.

**Step 2 produces the setting that step 4 consumes.** `ResolverSetting` lands in
`lib/app/network/resolver_setting.dart` and `XtreamCredentials.resolver` becomes a stored string;
neither does anything until step 4 reads the credential, parses it and hands the result to the
resolver. A run that stops after step 3 has a resolver nothing configures.

**Step 3 produces one `HostResolver` and steps 4 and 7 must share it.** Step 4 registers a single
instance in the container and the settings screen in step 7 reads that same instance's cache. Two
instances would show the user an address that the requests never used, which is worse than showing
nothing, because the whole point of that line is that the destination is inspectable.

**Steps 4 and 5 both edit `lib/app/providers/app_service_provider.dart`** at different sites: step 4
adds the `HostResolver` registration and the `HttpOverrides.global` assignment, step 5 adds two
timeouts inside the `configureDriver` closure at `:124`. They are in separate waves for that reason
rather than because one needs the other's output.

## Steps

### Wave 1 (steps 1 and 2 are independent and run in parallel)

- [x] **Step 1**: Stop the HLS demuxer opening a second connection, and skip the probe request on a live stream
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-4-detail: the edit is two dictionary entries, but putting either key on the wrong passthrough is silent rather than an error, so the value is in getting the routing right and saying why in the doc block.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift
    - **Description**: Add two entries to the `liveOptions` dictionary at `MpvEngine.swift:36-72`, which is iterated once per `start()` at `:107-111`. First, a new key `"demuxer-lavf-o": "http_multiple=0"`. FFmpeg's HLS demuxer declares `http_multiple` with a default of `-1` (`libavformat/hls.c:2840`) and resolves that to ON for any HTTP/1.1 or HTTP/2 server (`hls.c:1710-1716`), then opens the NEXT segment on a SECOND connection while the current one is live (`hls.c:1720-1722`). This repository has already measured what a second connection does to a real account: `max_connections` is 1 and the panel evicted the older stream at 5.79 s (`.ac/research/player-layer.md:218-231`). So on an m3u8 channel the player evicts itself. Second, append `,seekable=0` to the existing `"stream-lavf-o"` value, which saves the initial probe request on a stream that can never be seeked. **The two keys travel on different passthroughs and this is the whole risk of the step.** `http_multiple` is declared in `hls.c`, the HLS demuxer, so it goes on `demuxer-lavf-o` (`options.rst:3992`, "Pass AVOptions to libavformat demuxer"). `seekable` is declared in `http.c`, the protocol, so it goes on `stream-lavf-o` (`options.rst:8031`). Swapping them is not an error: `options.rst:8032` says "Unknown or misspelled options are silently ignored", and the comment already at `MpvEngine.swift:59-60` records this project being bitten by exactly that. Write a doc comment above each entry carrying the reason and the measurement, in the voice of the entries already there. `ts` leads the container preference (`xtream_stream_url.dart:39`) so most channels never reach the HLS demuxer, which makes this latent rather than live today; say that in the comment so a later reader does not think it is dead code.
    - **References**:
        - packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift:36-72, the dictionary and the doc-comment voice to match
        - packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift:56-60, the existing comment about a silently dropped option
        - .ac/plans/dns-connection-download/research/external-findings.md, the verified FFmpeg quotes with their SHA
    - **Done when**:
        - `rg -q 'demuxer-lavf-o' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift` exits 0
        - `rg -q 'http_multiple=0' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift` exits 0
        - `! rg -q 'stream-lavf-o.*http_multiple' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift` exits 0, proving the demuxer key did not land on the stream passthrough
        - `! rg -q 'demuxer-lavf-o.*seekable' packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift` exits 0, proving the protocol key did not land on the demuxer passthrough
    - **QA**: The runtime proof is step 9 and it is not optional; a grep cannot see whether FFmpeg accepted the inner key. For this step, read the two entries back and confirm each sits under the passthrough that declares it.
    - **Must NOT**:
        - Touch any other entry in `liveOptions`, in particular the bracketed `reconnect_on_http_error=[4xx,5xx]` value, whose bracketing is load-bearing.
        - Add `http_persistent`. It already defaults to 1 (`hls.c:2838-2839`) and setting it would be a no-op that reads as a decision.
        - Change the Dart side. Both values are engine-wide, so no hop on the nine-hop channel path moves.

- [x] **Step 2**: Give the credential a resolver field that an old stored blob survives
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-5-criticality: a wrong read here bricks every existing install at boot, and the failure mode is a lie about the cause rather than an error, so the criticality escalates the tier rather than sitting inside it.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/network/resolver_setting.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/protocol/xtream/xtream_credentials.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/network/resolver_setting_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/protocol/xtream/xtream_credentials_test.dart
    - **Description**: Create `lib/app/network/resolver_setting.dart` holding `ResolverSetting`, the parsed and validated form of what the user picked. It carries a named choice (`system`, `cloudflare`, `google`, `custom`) and, for `custom`, the literal the user typed. **Quad9 is deliberately not on that list**: its JSON endpoint answers `400 DoH unable to decode BASE64-URL` on port 443, and port 5053, which its documentation names for the JSON API, timed out entirely when measured from a Turkish connection on 2026-09-11. Cloudflare (`https://cloudflare-dns.com/dns-query`) and Google (`https://dns.google/resolve`) both answered 200 in the same run. Give it `ResolverSetting.parse(String?)` returning the system setting for null, for an unknown name, and for a custom value that does not validate, plus `String? get storedValue` for the round trip and `Uri? get dohEndpoint`. **Validate a custom value as an IP literal (with an optional `:port`) or an `https` URL, and never as a hostname**: a hostname would have to be resolved by the resolver it is replacing, so the ladder would bootstrap on itself. Reuse the shape of `_normaliseBaseUrl` (`xtream_credentials.dart:401`) for the parse-and-reject discipline. Then add `final String? resolver;` to `XtreamCredentials` (beside `userAgent` at `:78`), as an optional named constructor parameter, emit it in `_toJson` (`:379-384`) only when non-null, and read it in `load` (`:159-176`) through a new `_optionalString` that mirrors `_requireString`'s `is! String` check (`:419-427`) but **returns null instead of throwing, for a missing key and for a wrong-typed value alike**. That asymmetry is deliberate and the doc block must say so: `_requireString`'s `FormatException` is caught at `provider_session.dart:430-431` and rendered as `ProviderFault.expired`, which sends the user to re-enter a credential that is perfectly good, and a bare `as String?` cast would throw `TypeError` instead, which neither that catch nor the `MagicVaultException` catch at `:434` handles, so the app would boot to nothing because `start()` is awaited inside `Magic.init()` before `runApp()`. A resolver value we cannot read means "use the system resolver", which is exactly what the user had before this feature existed.
    - **References**:
        - lib/app/protocol/xtream/xtream_credentials.dart:419-427, `_requireString`, the shape `_optionalString` mirrors
        - lib/app/protocol/xtream/xtream_credentials.dart:401, `_normaliseBaseUrl`, the parse-and-reject discipline
        - lib/app/provider/provider_session.dart:429-448, the two catches and what each renders
        - test/app/protocol/xtream/xtream_credentials_test.dart:67-140, the existing vault round-trip tests to extend
    - **Done when**:
        - `flutter test test/app/network/resolver_setting_test.dart test/app/protocol/xtream/xtream_credentials_test.dart` exits 0
        - A test named for it asserts that a JSON blob carrying only `base_url`, `username`, `password` and `user_agent`, the exact four-key shape the previous version wrote, loads with `resolver` null and throws nothing
        - A test asserts that a blob whose `resolver` is a number rather than a string also loads with `resolver` null, throwing neither `FormatException` nor `TypeError`
        - A test asserts `ResolverSetting.parse` rejects a bare hostname such as `dns.example.com` and yields the system setting
        - `! rg -q "as String\?" lib/app/protocol/xtream/xtream_credentials.dart` exits 0, proving the cast that throws `TypeError` was not used
    - **QA**: Prove each of the three new tests discriminates by breaking the source: make `_optionalString` delegate to `_requireString` and watch the four-key test go red; make it a bare cast and watch the wrong-type test go red with `TypeError`; allow a hostname through `parse` and watch the third go red. Restore after each.
    - **Must NOT**:
        - Add `resolver` to the `_requireString` list in `load`.
        - Emit a `resolver` key into `_toJson` when the setting is the system one, so a user who never touches this feature keeps writing the same four-key blob.
        - Touch the form, the facade or the controller. This step is the model and its parsing only.

### Wave 2 (must run after wave 1)

- [x] **Step 3**: Build the resolver: system first, DoH on failure, with a TTL cache and a tamper rung
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-1-cross-layer: this is new infrastructure plus the first DNS test double in the suite, and its failure modes are the ones the whole feature exists to handle.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/network/host_resolver.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/network/host_resolver_test.dart
    - **Description**: Create `lib/app/network/host_resolver.dart`. Define `abstract interface class HostLookup { Future<List<InternetAddress>> lookup(String host); }` with two implementations, one wrapping `InternetAddress.lookup` and one issuing a DoH GET (`?name=<host>&type=A`, header `accept: application/dns-json`) against the endpoint that `ResolverSetting.dohEndpoint` in `lib/app/network/resolver_setting.dart` names. Two endpoints ship and both were measured answering 200 on 2026-09-11: `https://cloudflare-dns.com/dns-query` and `https://dns.google/resolve`. Re-run those two curls before writing the client, and if either has moved, fix the endpoint rather than the test. Three implementations exist immediately (system, DoH, and the test fake), so the interface is earned rather than speculative. Then `HostResolver`, holding the setting and a TTL cache, exposing `Future<InternetAddress?> resolve(String host)` and `InternetAddress? cached(String host)` for the settings screen to display. **The ladder**: try the system lookup under a timeout; if it throws, times out, or returns an answer that fails the tamper check, and the setting names a DoH endpoint, try that; if both fail, return null and let the caller classify. The system rung goes first because a cold DoH query was measured at 71 to 108 ms against 13 ms for plain UDP, so making DoH the default would slow every healthy lookup to fix a minority's broken one; put that measurement in the doc block. **The timeout is the point of the whole step**, not a defensive extra: FFmpeg's `getaddrinfo` is a plain blocking libc call with no interrupt callback, so mpv's own `--network-timeout` cannot bound a resolver that never answers, and moving resolution into Dart is what converts an unbounded hang into a bounded failure. **The tamper check**: an answer that is loopback, unspecified, or link-local for a host that is neither `localhost` nor already an IP literal is treated as tampering and escalates to the next rung rather than being refused outright. That is the documented Turkish shape, Vodafone returning `127.0.0.1` for a blocked name, so escalating serves the feature's purpose where a refusal would just fail differently. Do not refuse a private-range answer: it breaks a genuine LAN or WireGuard panel and stops no attacker, who would simply answer with a public address they control. Cache on the answer's TTL where the DoH JSON supplies one and on a fixed ceiling otherwise, and state the ceiling's reasoning in the doc block.
    - **References**:
        - lib/app/protocol/xtream/xtream_credentials.dart:401, the parse-and-reject discipline for anything user-supplied
        - .ac/plans/dns-connection-download/research/external-findings.md, the DoH and UDP measurements and the Turkish tampering evidence
        - packages/watchools_player/lib/src/stall_detector.dart, for the house voice on a policy class whose thresholds carry their measurement
    - **Done when**:
        - `flutter test test/app/network/host_resolver_test.dart` exits 0
        - A test asserts the system rung is tried first and the DoH rung is never consulted when the system answer is good
        - A test asserts a system lookup that never completes is abandoned at the timeout and the DoH rung answers instead
        - A test asserts a system answer of `127.0.0.1` for a non-local host escalates to the DoH rung, and that the same answer for `localhost` does not
        - A test asserts a second `resolve` of the same host inside the TTL consults no lookup at all, and that one after the TTL consults again
        - `! rg -q 'quad9' lib/app/network/` exits 0, because that endpoint was measured unusable and must not reappear
    - **QA**: Prove each test discriminates by breaking the source: reverse the ladder order, remove the timeout, drop the tamper check, and disable the cache read, watching the matching test go red each time and restoring after. The fake `HostLookup` must be able to hang, because a timeout test written against a lookup that merely returns late proves nothing.
    - **Must NOT**:
        - Issue the DoH request through magic's `Http` facade. This is a security boundary, not a style preference: `app_service_provider.dart:100-107` records that the shared driver carries magic's `AuthInterceptor`, which "attaches the watchools bearer token to every request with no host, scheme or origin test", so a DoH call through the facade hands our own user's bearer token to Cloudflare or Google. Use a plain `HttpClient`.
        - Reach for `dio` or any other HTTP package directly, per `CLAUDE.md`'s mandate.
        - Add address racing or Happy Eyeballs. FFmpeg already implements RFC 8305 (`network.c:298`) and the measured panel has exactly one A record, so there is nothing to race.
        - Refuse a private-range answer.
        - Wire this into anything. Installing it is step 4.

### Wave 3 (must run after wave 2)

- [x] **Step 4**: Install the resolver process-wide through HttpOverrides, and feed it the stored setting
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: a connection factory that returns a plain socket for an https URL sends the subscription password in cleartext to port 443, and the Dart SDK's own factory skips the TLS branch, so this is the one place the whole feature can fail silently and dangerously.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/network/resolving_http_overrides.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/providers/app_service_provider.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/provider/provider_session.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/network/resolving_http_overrides_test.dart
    - **Description**: Three things, and the third is what makes the other two do anything. **First**, create `ResolvingHttpOverrides extends HttpOverrides` in `lib/app/network/resolving_http_overrides.dart`, overriding `createHttpClient` to take `super.createHttpClient(context)` as its base client and set that client's `connectionFactory` to consult `HostResolver` from `lib/app/network/host_resolver.dart`. **Call `super`, never `HttpClient()`**: the `HttpClient` factory at `dart-sdk/lib/_http/http.dart:1348-1354` reads `HttpOverrides.current` and delegates to `createHttpClient`, so constructing one inside the override recurses until the stack dies. **Second**, register a single `HostResolver` in the container and assign `HttpOverrides.global` from `app_service_provider.dart`, beside the `provider_network` registration at `:118`. One instance, resolved from the container, because the settings screen reads the same cache in step 7 and two instances would show the user an address the requests never used. `HttpOverrides` is the route rather than a dio adapter for a reason worth stating in the doc block: `dio` is not a direct dependency and `CLAUDE.md` forbids reaching for it, while `configureDriver` hands over a `Dio` whose type the app never names; dio's IO adapter builds a plain `HttpClient()`, which consults the override, so this reaches the same place with no new dependency and no sibling release. **Third, wire the stored setting through.** `XtreamCredentials.resolver` is a stored string and nothing reads it yet. Add a public accessor on `ProviderSession` in the shape of `playbackUserAgent` (`provider_session.dart:215-220`, public where the credential is not, with a doc block saying why), exposing both the configured panel host and the parsed `ResolverSetting`. Feed it to the `HostResolver` at registration, and **update it in `adopt` (`provider_session.dart:343-357`), which is where a new credential replaces the old one**: without that, a user who changes their resolver keeps resolving through the previous one until the process restarts. **The factory must return an already-secured socket for an https URL, upgraded with the ORIGINAL hostname**: `SecureSocket.secure(socket, host: uri.host)` so SNI and certificate validation both run against the name while the connection goes to the address we chose. Returning a plain socket for https is the documented Dart trap and it fails open rather than closed. For an http URL return the plain `ConnectionTask`. **Resolve only the configured panel host**; anything else falls through to the default connect, because this override is process-wide and silently redirecting unrelated traffic is not what the user agreed to. When `resolve` returns null, fall through rather than failing the request, so a resolver problem degrades to today's behaviour instead of taking the app offline.
    - **References**:
        - lib/app/providers/app_service_provider.dart:118-127, the registration and the existing `configureDriver` closure
        - lib/app/provider/provider_session.dart:215-220, `playbackUserAgent`, the accessor shape and the doc-block reasoning to mirror
        - lib/app/provider/provider_session.dart:343-357, `adopt`, where a replaced credential must push the new setting
        - test/app/protocol/xtream/xtream_client_test.dart:98-134, `_RawPanel`, the loopback server to assert against
    - **Done when**:
        - `flutter test test/app/network/resolving_http_overrides_test.dart test/app/provider/provider_session_test.dart` exits 0
        - A test using a loopback `ServerSocket` in the shape of `_RawPanel` asserts that a request for a host the resolver maps to `127.0.0.1` actually connects to that loopback server, and that the request it receives carries the original `Host`
        - A test asserts a host other than the configured panel is not resolved through `HostResolver` at all
        - A test asserts that when `resolve` returns null the request still goes out via the default path
        - A test asserts that `adopt` with a credential carrying a different resolver changes which lookup the next resolve consults
        - `rg -q 'super.createHttpClient' lib/app/network/resolving_http_overrides.dart` exits 0, proving the recursive `HttpClient()` was not used
        - `rg -q 'SecureSocket.secure' lib/app/network/resolving_http_overrides.dart` exits 0 and the call passes `host:` explicitly
        - `! rg -q "import 'package:dio" lib/` exits 0, proving no direct dio import was introduced
    - **QA**: Prove the https branch discriminates rather than trusting it: point the factory at a local TLS server presenting a certificate for one name, connect by address with `host:` set to that name and assert the handshake succeeds, then remove the `host:` argument and assert it fails. A test that only exercises http cannot see the trap this step exists to avoid.
    - **Must NOT**:
        - Rewrite a stream URL or touch `XtreamStreamUrl`, `PlaybackEngine`, `MpvPlaybackEngine` or anything under `packages/watchools_player/`. The stream half is out of scope and the reason is in the Research Summary.
        - Import `package:dio/dio.dart` anywhere in `lib/`.
        - Pin a host other than the configured panel.
        - Construct a second `HostResolver`. The settings screen must read the same instance the requests use.

### Wave 4 (must run after wave 3)

- [x] **Step 5**: Bound the provider driver's own timeouts
    - **OUTCOME: the premise was refuted and no code was written.** magic's `DioNetworkDriver`
      constructor (`magic/lib/src/network/drivers/dio_network_driver.dart:18-27`) declares
      `this.timeout = 10000` and builds `BaseOptions(connectTimeout: ..., receiveTimeout: ...)` from
      it, and `app_service_provider.dart:119` constructs the driver without passing one, so BOTH
      timeouts are already 10000 ms. The Stage 1 explore read the `configureDriver` closure, saw only
      `followRedirects`, and reported the timeout absent without opening the constructor. The
      objective this step existed for is already met, writing the line would restate a default, and
      its test would have been green before the edit. Surfaced to the user as a plan-spec question
      during execution; no answer inside the wait, so it takes the recommended option. Ticked because
      the objective holds, not because a change was made.
    - **Type**: code
    - **Tier**: quick
    - **Why this tier**: rule-none: one closure, two values, in a file the step above also touches but at a different site.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/providers/app_service_provider.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/providers/app_service_provider_test.dart
    - **Description**: Set a connect timeout and a receive timeout on the `provider_network` driver, inside the `configureDriver` closure that already sets `followRedirects = false` at `app_service_provider.dart:124`. `lib/config/network.dart:14` gives the magic-managed `api` driver 10000 ms and this driver has none, so a panel that accepts a connection and then says nothing has no bound at any layer. Its own concern rather than part of the override step: the resolver bounds name resolution, this bounds the request that follows it, and they fail for different reasons. Use the same 10000 the `api` driver uses so the two agree, and say in the comment that the number is borrowed rather than measured.
    - **References**:
        - lib/app/providers/app_service_provider.dart:118-127, the registration and the existing closure
        - lib/config/network.dart:14, the 10000 the `api` driver uses
    - **Done when**:
        - `flutter test test/app/providers/app_service_provider_test.dart` exits 0
        - A test asserts the registered `provider_network` driver reports both timeouts as 10000 ms
    - **QA**: Prove the test discriminates by removing one of the two assignments and watching it go red.
    - **Must NOT**:
        - Touch `followRedirects`. A 3xx off a panel is a fault to surface and the comment at `:121-123` says why.
        - Add an interceptor. The comment at `:96-110` records that this driver carries none deliberately.

### Wave 5 (must run after wave 4)

- [ ] **Step 6**: Put the resolver in the settings form as a named picker, and stop the disclosure eating it
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-4-detail: the widget work is ordinary, but two behaviours already in this file (clear-on-close, and no prefill) turn a naive addition into silent data loss the user would blame on something else.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/ui/layouts/provider_settings_layout.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/controllers/provider_setup_controller.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/ui/layouts/provider_settings_layout_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/controllers/provider_setup_controller_test.dart
    - **Description**: Add the resolver to the `Gelişmiş ayarlar` disclosure at `provider_settings_layout.dart:278-301`, beside the User-Agent field, as a `WFormSelect<String>` naming System, Cloudflare, Google and Quad9, plus a `WFormInput` for a custom value that mounts only when the custom entry is chosen. Use the shared `_fieldClassName` and `_labelClassName` at `:74-82`; Wind owns the styling and no raw colour or `TextStyle` appears. Thread the value through `ProviderSetupFacade.submit` (`provider_setup_controller.dart:43-48`) the way `userAgent` already travels, into the `XtreamCredentials` construction at `:251-254`. **Two behaviours in this file make the naive version lose data.** The disclosure clears its own field on close (`:290`) and the form never prefills, `_baseUrl`, `_password` and `_userAgent` all starting empty at `:109-111`; that is safe for the User-Agent because `_defaultUserAgent` fills the gap, and unsafe for a resolver because its default is the system resolver, which is the thing that was broken. A user who sets a resolver, later reopens settings to fix a password, and submits with the disclosure closed would silently lose reachability, and the symptom would read as "changing my password broke it". So **seed the resolver from the loaded credential in `initState` and exclude it from the clear-on-close rule**, or carry the stored value forward in `_submit` when the disclosure was never opened. Either is acceptable; the test is what matters. **Write the copy rather than leaving it to judgement.** Every string on this screen carries a documented rationale, so these do too. The picker's label is `DNS çözümleyici`. The custom field's helper line names the consequence rather than the format: `Buraya yazdığınız sunucu, panel adresinizi çözümler. Panel istekleri abonelik bilgilerinizi taşır, o yüzden yalnızca güvendiğiniz bir sunucu girin.` The validation message when a hostname is typed is `Sunucu adı değil, IP adresi veya https adresi girin.`, and the doc comment above the validator says why: a hostname would have to be resolved by the resolver it is replacing.
    - **References**:
        - lib/ui/layouts/provider_settings_layout.dart:171-172, `_disclosure()` followed by `if (_advancedOpen) _userAgentField()`, which is the insertion point for the new fields rather than `_disclosure()` itself
        - lib/ui/layouts/provider_settings_layout.dart:233-245, the `_userAgentField` shape to follow
        - lib/ui/layouts/provider_settings_layout.dart:278-301, the disclosure and its clear-on-close at :290
        - lib/ui/layouts/provider_settings_layout.dart:74-82, the shared field and label classNames
        - test/ui/layouts/provider_settings_layout_test.dart:301-335, the existing clear-on-close regression test to sit beside
    - **Done when**:
        - `flutter test test/ui/layouts/provider_settings_layout_test.dart test/app/controllers/provider_setup_controller_test.dart` exits 0
        - A test asserts that a credential stored with a non-system resolver, reopened and submitted with the disclosure never opened, still reaches the facade carrying that resolver
        - A test asserts the custom field is absent until the custom entry is picked
        - A test asserts a bare hostname typed into the custom field is refused with a field error and nothing is submitted
        - `! rg -q 'Colors\.|TextStyle\(|Color\(0x' lib/ui/layouts/provider_settings_layout.dart` exits 0
    - **QA**: Prove the carry-forward test discriminates by removing the seeding and watching it go red with the resolver arriving as the system default. Run the whole suite afterwards rather than this file alone: `CLAUDE.md` records a late change to a layout being caught only by a test about something else.
    - **Must NOT**:
        - Accept a hostname as a custom resolver.
        - Change the User-Agent field's own clear-on-close behaviour or the test at `:301-335` that holds it.
        - Introduce a Material widget. Wind owns this surface.

### Wave 6 (steps 7 and 8 are independent and run in parallel, after wave 5)

- [ ] **Step 7**: Show which address the panel actually resolved to
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-none: one read path and one line of copy, but it is the mitigation that makes the custom-resolver risk inspectable rather than invisible.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/ui/layouts/provider_settings_layout.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/controllers/provider_setup_controller.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/lib/app/providers/app_service_provider.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/ui/layouts/provider_settings_layout_test.dart
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/test/app/controllers/provider_setup_controller_test.dart
    - **Description**: Expose the resolver's cached answer for the configured panel host on `ProviderSetupFacade` (a nullable string, null when nothing has been resolved yet) reading `HostResolver.cached` from `lib/app/network/host_resolver.dart`, and render it inside the disclosure under the resolver picker as a single line naming the address. `ProviderSetupController` is constructed at `app_service_provider.dart:98` and again in its test at `provider_setup_controller_test.dart:123`, so both construction sites take the resolver the container already holds; take the registered instance rather than building one, because step 4 installed that instance into `HttpOverrides` and a second one would hold a different cache. This is the mitigation that turns "a resolver you pasted sends your credentials somewhere" from invisible into inspectable: the destination becomes a thing the user can read and compare. Render nothing rather than a placeholder when the value is null, so a fresh install shows no empty row. Also state, in one sentence beside the picker, that the resolver applies to the panel's catalogue requests and not to the video stream. A setting that silently applies to half of what the user thinks it applies to is worse than one that applies to none of it. The copy, written here rather than left to judgement because every string on this screen carries a rationale: `Bu ayar panel isteklerine uygulanır. Yayın, panelin yönlendirdiği başka bir adresten geldiği için sistem çözümleyicisini kullanır.` The address line above it reads `Panel adresi: <address>` and renders only when there is a cached answer.
    - **References**:
        - lib/ui/layouts/provider_settings_layout.dart:74-82, the label className for the line
        - lib/app/controllers/provider_setup_controller.dart:43-48, the facade contract to extend
    - **Done when**:
        - `flutter test test/ui/layouts/provider_settings_layout_test.dart` exits 0
        - A test asserts the address line is absent when the facade reports null and present, carrying the address, when it reports one
        - A test asserts the sentence about the stream is rendered inside the disclosure
    - **QA**: Diff the rendered labels against the no-resolver baseline and assert exactly the expected number of added lines, rather than asserting that some string is present: `CLAUDE.md` records a `contains` assertion on this very screen that discriminated only by luck.
    - **Must NOT**:
        - Trigger a resolution from the settings screen. This reads the cache and nothing else.
        - Render a placeholder when there is no cached address.

- [ ] **Step 8**: Correct the three claims this research falsified
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-4-detail: prose edits to three files, but each one replaces a claim rather than appending to it, and each correction has to be read back against the source quote it rests on, which is past what this plan's calibration calls a single-file mechanical edit.
    - **Files**:
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/CLAUDE.md
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/.ac/research/stack-decisions.md
        - /Users/anilcan/Code/watchools/.claude/worktrees/network-resolver/.ac/research/player-layer.md
    - **Description**: Three corrections, each replacing a claim rather than appending a note. First, `CLAUDE.md:184` and `.ac/research/stack-decisions.md:130-138` state that no app in this category ships an in-app DNS setting, naming TiViMate, OTT Navigator and IPTV Smarters. That is false: OwnTV's README line 94 reads "App-wide **custom DNS** — System, Google, Cloudflare, Quad9, custom DNS or DNS-over-HTTPS; the selected resolver persists across restarts", and OwnTV is the closest comparable there is, an Android TV client built on libmpv. Correct the claim and add the trap beside it, that the "Multi DNS" feature XCIPTV and IBO Player advertise is portal-address failover rather than name resolution. Second, both files frame custom DNS as an onboarding problem because no player exposes a resolver hook. The hook half is still true and the conclusion no longer follows: a resolver hook is not needed to pin an address, `HttpOverrides` reaches the app's own HTTP, and what genuinely cannot be reached is libmpv's byte fetch. Rewrite the section to say which half of the app the resolver covers and why the other half cannot be, citing the `302`-to-another-origin measurement at `player-layer.md:26-28` and the redirect loop at `libavformat/http.c:487-509`. Third, `.ac/research/player-layer.md`'s buffer section implies a large forward buffer protects a live stream; it largely does not, because the origin cannot serve a segment it has not published, so the playlist window binds before the byte budget does. Add the two reference points: hls.js targets 30 s of live buffer and Shaka fetches one segment ahead. Also record in `CLAUDE.md` that `http_multiple` defaults to on and why it is now off, since that is exactly the kind of silent default a later reader would otherwise rediscover.
    - **References**:
        - CLAUDE.md:184, the false sentence
        - .ac/research/stack-decisions.md:130-138, the section to rewrite
        - .ac/plans/dns-connection-download/research/external-findings.md, every quote and source needed
    - **Done when**:
        - `! rg -q 'ships an in-app DNS setting' CLAUDE.md .ac/research/stack-decisions.md` exits 0. The phrasing differs between the two files, `CLAUDE.md` writing "no app in this category" and `stack-decisions.md` writing "no player in this category", so the pattern deliberately matches only the tail they share; anchoring on either opening would leave the other file uncorrected and the criterion still green.
        - `rg -q 'OwnTV' CLAUDE.md` exits 0
        - `rg -q 'http_multiple' CLAUDE.md` exits 0
    - **QA**: Read each corrected paragraph against the source quote in `research/external-findings.md` and confirm the correction states what the source states, not more.
    - **Must NOT**:
        - Append a correction note while leaving the false sentence in place. `CLAUDE.md` is read as current fact.
        - Use an em dash or an en dash in any of these files.

### Wave 7 (must run after wave 6)

- [ ] **Step 9**: Prove the options took effect and the gates are green
    - **Type**: verification
    - **Files**: (no source edits, except one temporary and reverted option flip described below)
    - **Description**: Two things this plan cannot assert from source. **First, whether FFmpeg actually accepted `http_multiple=0`**, because an inner key on a passthrough is dropped silently when it is wrong, so every grep in step 1 can pass over an option that does nothing. The discriminating observation is the mock's own request log: play the m3u8-only channel at `tool/xtream-mock/catalogue.mjs:267` and look at whether two segment requests overlap in time. With the option ignored, FFmpeg opens the next segment while the current one is still being read (`hls.c:1720-1722`); with it applied, it does not. Capture the log twice. The control run needs the option inverted, which means **one temporary edit to `packages/watchools_player/macos/watchools_player/Sources/watchools_player/MpvEngine.swift`, changing `http_multiple=0` to `http_multiple=1`, rebuilt, captured, then reverted with `git checkout --` before the evidence files are written**. That flip is the only source change this step makes and it must not survive it: `git status` is clean at the end. Without the control, a log showing no overlap proves nothing, because a run where the option was silently dropped and a run where the panel happened to be slow look identical. **Second, the macOS build**, because CI compiles no Swift at all (`ci.yml` runs on `ubuntu-latest`), so a Swift edit is otherwise unverified until somebody runs the app.
    - **Commands**:
        - flutter analyze --fatal-infos --fatal-warnings
        - dart format --set-exit-if-changed lib test
        - flutter test --coverage
        - flutter build macos --debug
        - node tool/xtream-mock/server.mjs (background, port 3300, request log captured to the evidence path)
        - ./bin/fsa start -d macos (background, then drive to the m3u8-only channel and play it for at least 30 seconds)
        - git status --porcelain (must print nothing once the control flip is reverted)
    - **Done when**:
        - `flutter analyze --fatal-infos --fatal-warnings` exits 0 with no warnings and no infos
        - `dart format --set-exit-if-changed lib test` exits 0
        - `flutter test --coverage` exits 0, and the percentage computed by the inline Python block at `.github/workflows/ci.yml:115-143` run against `coverage/lcov.info`, with its own exclusion list, is at or above the `FLUTTER_COVERAGE_MINIMUM` of 90 declared at `ci.yml:18`
        - `flutter build macos --debug` exits 0
        - The captured mock log for the m3u8-only channel shows no two segment requests overlapping in time, **and** the inverted-option control log shows that they do. Both files are written; one without the other is not evidence
        - `git status --porcelain` prints nothing, proving the control flip was reverted
    - **Evidence**:
        - .ac/plans/dns-connection-download/evidence/08-gates.txt
        - .ac/plans/dns-connection-download/evidence/08-mock-requests-fixed.txt
        - .ac/plans/dns-connection-download/evidence/08-mock-requests-control.txt
        - .ac/plans/dns-connection-download/evidence/08-macos-build.txt
    - **Must NOT**:
        - Make a request to the real provider. Every observation here runs against `tool/xtream-mock`.
        - Report the coverage figure from a local run as the CI gate. Compute it with CI's own exclusion list.

## Risks Accepted

**Four decisions are defaults rather than choices.** The four interview questions went out with a
recommended option each and no answer arrived inside the 600 second wait, which is consistent with
the user's own statement that he is away from the machine. Each is locked on its recommendation and
any is cheap to revisit. Full reasoning in `interview-log.md`.

- **D1, scope.** The network layer and its setting. Offline download and a throughput health verdict
  are both out, each for the same class of reason: their prerequisites do not exist. See Deferred
  Ideas.
- **D2, storage.** The resolver lives in the credential record, so signing out forgets it. Accepted,
  because the alternative cannot be read during onboarding and onboarding is the first thing a
  broken resolver breaks.
- **D3 is retired rather than answered.** It asked what should happen on an https panel, on the
  premise that pinning was an http-only trick. With the stream half out of scope and `HttpOverrides`
  carrying correct SNI through `SecureSocket.secure(host:)`, the resolver applies to the catalogue on
  both schemes and there is no split to explain.
- **D4, the ladder.** System resolver first, DoH only on failure, timeout or a tamper signal.

**The resolver does not reach the video stream, and that is permanent for this design.** The panel
answers `302` to an origin it chooses, libmpv follows it alone, and that connection resolves through
`getaddrinfo`. The settings screen says so in a sentence (step 7). The user's reported symptom is
still addressed, because a resolver failure lands on the catalogue first and the user never reaches
playback.

**A DoH fallback discloses the panel hostname to Cloudflare, Google or Quad9** on every cold resolve.
Not a credential, and arguably better than the ISP resolver seeing it, but it is a new third party
and it belongs in the setting's copy.

**`HttpOverrides.global` is process-wide.** Step 4 bounds the blast radius by resolving only the
configured panel host and falling through for everything else, and the Must NOT says so, but the
mechanism itself is global and a later contributor could widen it without noticing.

**Step 1's fix is latent today.** `ts` leads the container preference, so most channels never reach
the HLS demuxer. The fix is still correct and step 9 proves it against the m3u8-only fixture.

**The macOS build is the only check on the Swift edit.** CI compiles no Swift at all, which is
already recorded as an ecosystem observation from an earlier plan.

## Cross-Project Observations

**magic has no seam for a custom connection factory on `DioNetworkDriver`.** `configureDriver` hands
over the `Dio` instance, which is the documented escape hatch for "custom adapters", but installing
one means naming `IOHttpClientAdapter`, which means importing `package:dio/dio.dart` into the app,
which `CLAUDE.md` forbids in the same breath as `shared_preferences` and `sqflite`. This plan routes
around it with `HttpOverrides.global`, which is a legitimate first-party mechanism rather than a
workaround, so nothing is blocked. The gap is still worth filing: a `NetworkDriver` that let a
consumer supply a resolver or a connection factory without importing the transport would be the
cleaner seam, and this app is the second caller to want it after timeouts.

Filed as an improvement rather than a defect: the current API works, it just costs an import the
project's own rules do not allow. Report it out loud in the pull request per `CLAUDE.md`'s ecosystem
rule, and record it in `.ac/research/ecosystem-defects.md`. Do not fix it inside this plan.

**`packages/watchools_player/example/macos/RunnerTests/RunnerTests.swift` is dead scaffold.** It
tests a `getPlatformVersion` method that does not exist against a no-argument initialiser that does
not match `WatchoolsPlayerPlugin.swift:14`. It is in our own repository rather than a sibling, and it
is out of scope here, but it means there is no Swift-side test to extend for step 1.

## Deferred Ideas

**Offline download**, for iOS, Android, Android TV and macOS. Blocked on a prerequisite that does not
exist: `container_extension` is consumed at parse into an uppercased display fact inside
`StreamFacts`, so a VOD URL cannot be derived from cached state, and recovering one would mean
lowercasing display data back into a path. It needs a real field on `TitleItem` and a store column,
which is a protocol-layer change plus a migration. Two findings are already settled and should not
be re-researched when it is picked up: **Apple TV is a platform stop, not a later task**, because
Apple's own guide caps local persistent storage at 500 KB with everything else purgeable; and
**multi-connection download is forbidden by the account rather than by the server**, which answers
the "make it fastest" half before the work starts. The mechanics are single connection, `Range` plus
`If-Range` against an `ETag` or `Last-Modified`, and dropping the `Range` header entirely on a `416`
rather than resending it.

**A throughput verdict from `inputRate`.** The field is sampled end to end today and inert: nothing
reads it. Two things it needs are missing, a reference bitrate to compare against, which exists
nowhere in the repository, and a recovery action to attach the verdict to, which is the variant
ladder and is unbuilt. A `PlaybackHealth` member naming a condition nothing acts on is the promise
`CLAUDE.md` warns about. The design is already drafted at `.ac/research/player-layer.md:623-627` and
marked unverified; it belongs with the ladder.

**Pinning the stream after all**, by setting `max_redirects=0`, walking the redirect chain in Dart,
resolving each hop ourselves and handing libmpv the final URL. Technically available and genuinely
out of scope here: token reminting, the reconnect ladder and the variant ladder all sit on that same
path, so it is a plan about the playback path rather than about DNS.

**Detecting a device whose strict-mode Private DNS points at a broken host**, via
`LinkProperties.getPrivateDnsServerName` on Android. A diagnostic rather than a fix, and Android
only, but it turns a confusing failure into a sentence that names the cause.

**Pre-resolving the panel host when the channel list renders** was in the original scope and is
dropped rather than deferred. It would have saved a lookup on tap, but taps open the stream host,
which this design no longer resolves, and the catalogue's own first request already warms the cache.
It would be work with no effect.
