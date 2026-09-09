# Plan: xtream-codes-protocol-layer-watchools

**Steps**: 14
**Waves**: 6
**Codebase State**: disciplined
**Auto mode**: false
**Generated**: 2026-09-09

## Research Summary

Eleven research files under `research/`. `verification-log.md` carries what I checked myself
against source; prefer it over any other file where they disagree.

**Every piece of infrastructure already exists in the `magic` sibling.** The delta is the Xtream
parsers, the type-drift coercion, the fault classification, the mapping into the app's existing
value types, a catalogue store, and the controller swap.

Load-bearing verified facts:

- **`Http.get(absoluteUrl, ...)` bypasses the driver's `base_url`**
  (`magic/lib/src/network/drivers/dio_network_driver.dart:181-196`). A per-user panel host needs no
  runtime driver and no deviation from `CLAUDE.md`'s `Http` facade mandate.
- **The HTTP test double is first-party**: `Http.fake([stubs])`
  (`magic/lib/src/facades/http.dart:138`) with a URL-pattern map, a callback,
  `Http.response()` and `Http.unfake()`, plus `FakeNetworkDriver.assertSent()`.
- **`DB.statement(String sql, [List<Object?> params])`** binds parameters
  (`magic/lib/src/facades/db.dart:105`) and is **synchronous**, returning void. `DB.transaction`
  (`:183`) wraps a sync BEGIN/COMMIT around an async callback.
- **The ORM is headless-testable**: `magic/test/database/query_builder_test.dart` passes 12/12
  under `flutter test` on this machine. magic uses `sqlite3` (Dart FFI), not `sqflite`.
- **There is no pagination.** Five independent real clients plus one compatible server agree
  `category_id` is the only filter, so one call returns all 38,247 VOD rows.
- **The fault disjunction is confirmed independently twice** (`iptvnator`, `tvarr`). No fourth dead
  arm. Match `status` case-insensitively; treat `0`, negative, missing or unparsable `exp_date` as
  no-expiry.
- **The app already virtualises.** `lib/ui/components/rail/rail.dart:11-15` uses
  `ListView.builder` deliberately, and `now_layout.dart:87` and `showcase_layout.dart:75` are
  `SliverList.builder`. Catalogue size does not threaten the render path.
- **A single response cannot be classified.** `tool/xtream-mock/README.md:126-129`: the
  200-plus-non-JSON shape is produced by throttled, a blocked address, a blocked user agent, an
  HTML error page and an expired stream request alike. Classification needs the handshake as
  context.

One defect blocks a requirement, one claim was refuted, one gate stays open. All three are in
`## Risks Accepted`.

## Codebase Conventions

- **Naming**: `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` members. Test files
  mirror the source path with a `_test.dart` suffix.
- **Error handling**: no fallback `try/catch` that swallows. magic's `MagicResponse` never throws,
  so this layer reads `statusCode` and body rather than catching. A transport failure is
  `statusCode: 0`.
- **Comment density**: doc blocks everywhere, and they carry what the signature cannot: the
  contract, the failure mode, the unit, the measurement that decided a number. Never restate a
  parameter name. This is the single strongest convention in the repo; match it or the code reads
  as foreign.
- **Type discipline**: strict. Explicit types on every parameter, return and field. No `dynamic`
  unless a wire boundary forces it.
- **File organisation**: nested by role under `lib/app/`, one concept per file. No barrel exports
  under `lib/app/`; a UI component folder is the exception and does carry an `index.dart`
  (`lib/ui/components/provider_notice/index.dart:7-8`), alongside `*.recipe.dart` and
  `*.preview.dart` with a **dot**, which is what `previews:refresh` discovers.
- **Import convention**: relative within `lib/`, `package:` for external.
- **Path aliases**: none.
- **LSP false-positive whitelist**: `lib/config/wind_theme.g.dart` and `lib/app/_plugins.g.dart`
  are generated; never edit, never report their diagnostics.
- **Test mount discipline**: `wrapWithTheme()` (`test/support/wind_test_app.dart:34`) for a leaf
  widget, `pumpScreen()` (`test/support/screen.dart:44`) for a whole screen. Every widget test
  calls `setUp(WindParser.clearCache)` or it can pass for the wrong reason. `.env` is a real asset
  during `flutter test`, so assert an **overridden** value via
  `Env.reset(); Env.load(mergeWith: {...})` and never a default.
- **TDD**: yes. Infrastructure exists (`flutter test --coverage`, 90% floor in CI). Failing test
  first, on every `code` step. The denominator excludes `lib/resources/views/`,
  `lib/app/providers/`, `lib/app/kernel.dart`, `lib/routes/app.dart`, so binding code in
  `providers/` carries no coverage obligation and the client's own logic must clear 90%.
- **Wind and Magic are not optional**: `className` strings and `W`-prefixed widgets for anything
  visual; `Http`, `Vault`, `DB` facades for everything below. Never `dio`, `shared_preferences` or
  `sqflite` directly.
- **Numbers off the wire**: decode every numeric as `num`, never `as int` or `as double`. On web
  `int` and `double` share one float; on native they do not. This is a hard rule for this layer.

## Reuse Map

| Need | Reuse | Where |
|---|---|---|
| HTTP with a per-user host | `NetworkDriver.get(absoluteUrl, query:, headers:)` on a **dedicated** driver, not the shared `Http` singleton; see step 4 | `magic/lib/src/facades/http.dart:80` for the signature, `dio_network_driver.dart:181` for the passthrough |
| HTTP test double | `Http.fake()`, `Http.response()`, `Http.unfake()`, `FakeNetworkDriver.assertSent()` | `magic/lib/src/facades/http.dart:138`, `:144`, `:159` |
| Worked faking example | magic's own suite | `magic/test/network/http_fake_test.dart:16-56` |
| Secret storage | `Vault.put/get/delete/flush`, strings only | `magic/lib/src/facades/vault.dart:17-36` |
| Raw parameterised SQL | `DB.statement(sql, params)` | `magic/lib/src/facades/db.dart:105` |
| Atomic write | `DB.transaction(callback)` | `magic/lib/src/facades/db.dart:183` |
| Prepared statement, for the bulk path | `CommonDatabase.prepare` via `Magic.make<DatabaseManager>('db').connection` | `sqlite3/lib/src/database.dart:158` |
| Controller base and notification | `SimpleMagicController`, `refreshUI()` | `lib/app/controllers/guide_controller.dart:54` |
| Loading / error state on a controller | `MagicStateMixin`, **but not usable here**: it mixes into a `MagicController` and both app controllers are `SimpleMagicController`, so the session holds its own state instead | `magic/lib/src/http/magic_controller.dart:140` |
| Fault vocabulary and its panel | `ProviderFault`, `ProviderNotice` | `lib/app/models/provider_fault.dart:24`, `lib/ui/components/provider_notice/` |
| Target value types | `Channel`, `Programme`, `TitleItem`, `Episode` | `lib/app/models/channel.dart:31`, `programme.dart:11`, `title_item.dart:133`, `:24` |
| The executable wire contract | the mock panel, 70 checks | `tool/xtream-mock/server.mjs`, `verify.mjs` |

**Not reused, deliberately**: `MagicPaginator`. The protocol has no pagination, so a paginator
would be scaffolding around a single call.

## Work Objectives

1. Credentials **already in `Vault`** become a live catalogue on all four existing screens,
   replacing the fixtures, with the swap mechanical because the client returns the same
   `List<Channel>` and `List<TitleItem>` the controllers already read.

   **There is deliberately no onboarding screen in this plan**, which means no user-facing way to
   enter a credential: development seeds `Vault` directly, and `.env.local` is already reserved and
   gitignored for real test credentials. That is a scope boundary rather than an oversight, and it
   has a visible consequence: `provider_notice.dart:39` routes `onOpenSettings` to `/saglayici`, a
   route no step here registers, so the fault panel's button leads nowhere until the onboarding
   plan lands. Recorded in `## Deferred Ideas`.
2. A provider fault reaches the UI as one of four `ProviderFault` values, classified from the
   handshake rather than from whether a list parsed, and rendered by the `ProviderNotice` that
   already exists and currently has nothing to show.
3. The catalogue survives a restart as a cold-start cache, written atomically with every provider
   string bound rather than interpolated.
4. Nothing in this plan reaches for `dio`, `sqflite` or `shared_preferences`, and nothing logs a
   credential.

## Tier Calibration

Three steps carry `rule-5-criticality` and land on `senior`: step 1 decides where a user's provider
password lives, step 4 decides which hosts receive our own bearer token, and step 7 decides how
untrusted third-party strings reach SQL. Each is a before-and-after decision on a listed surface
rather than a step that merely touches one. Step 4 was `junior-high` in the first draft and was
escalated by the security pass, which found that magic's `AuthInterceptor` sits on the one shared
driver with no host test.

Four steps carry `rule-none` and land on `junior-high`: the client, the classifier, the session and
the controller swap. Each is heavier than pattern application without being cross-layer, and the
risk each carries is one the five numbered rules do not name: a silent wrong answer that looks like
success. The remainder are `junior`, applying a pattern the repo already demonstrates.

No step is `quick`. The codebase is `disciplined` with an unusually heavy doc-block convention, and
a mechanical edit that ignores it produces code that reads as foreign, which rule 4 catches.

## Execution Strategy

Six waves. Wave 1 is three independent foundations and can run in parallel. Wave 2 needs wave 1's
coercion helpers. Wave 3 needs the client. Wave 4 needs the store and the classifier. Wave 5 is the
consumer swap and needs everything. Wave 6 measures and gates.

| Wave | Steps | Why together |
|---|---|---|
| 1 | 1, 2, 3 | No dependencies between them; step 3 is in another repository |
| 2 | 4, 5 | Both need the coercion helpers from step 2 |
| 3 | 6, 7 | Mapping and storage, both need the client's output shape |
| 4 | 8, 9 | The session needs the store and the classifier; the fault member is independent but lands with its consumer |
| 5 | 10, 11 | The controller swap and the fault rendering touch the same four layouts |
| 6 | 12, 13, 14 | Mock fidelity, then the two measurements that gate the plan |

### Dependency Notes

The wave table above is the barrier order; these are the cross-step dependencies inside it, which a
worker holding one step cannot see.

| Step | Needs | Why |
|---|---|---|
| 4 | 1 | resolves `XtreamCredentials` for the base URL and the user agent |
| 4, 5, 6 | 2 | every decode goes through `lib/app/protocol/xtream/xtream_json.dart` |
| 5 | none for the enum | step 5 adds `ProviderFault.evicted` itself, which is why step 9 no longer does |
| 6 | 4 | maps the client's output shape |
| 7 | 6 | stores what the factories build, and depends on `ChannelStatus` being computed rather than stored |
| 8 | 4, 5, 7 | holds the client, the classifier and the store |
| 9 | 5 | renders the member step 5 introduced |
| 10 | 8 | reads the session |
| 11 | 9, 10 | needs the rendered arm and the controller's fault getter |
| 13 | 7 | times the writer |
| 14 | all | the gate |

Step 7 sits in wave 3 beside step 6 and depends on it, so within that wave step 6 completes first.
If the executor runs a wave's steps in parallel, split step 7 into its own wave rather than racing
them.

**Step 13 is an escalation gate, not a formality.** If the measured catalogue write exceeds two
seconds on the slowest target, the synchronous path is not survivable behind a progress state and
the answer becomes a background isolate, which magic's web arm cannot provide. Stop and re-plan
rather than shipping it.

## Steps

Paths are absolute into the worktree this plan executes in,
`/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/`. The plan itself is a tracked
artefact (`.gitignore:63`), so a later reader outside that worktree should read them as
repo-relative from the segment after `player-reconnect/`.

### Wave 1

- [x] **Step 1**: Store provider credentials in Vault behind a serialised record
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, no provider password exists anywhere in the app; after, a user's panel password is written to the platform keystore under a key this step names and read back on every launch, so this step decides where a credential lives and what its record looks like.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_credentials.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_credentials_test.dart`
    - **Description**: Define `XtreamCredentials` as an immutable value type holding the panel base URL, username, password and the per-provider `userAgent`, plus `save()` / `load()` / `clear()` against the `Vault` facade. Also expose `String describe(Uri)` here, the only sanctioned way to name a provider URL in a log, an error or a diagnostic: it returns scheme, host, port and path with the **query dropped** and any **path segment equal to the stored username or password replaced**, because a stream URL carries the credentials in the path (`/live/<username>/<password>/<id>.ts`) where dropping the query does nothing. `Vault` stores strings only (`magic/lib/src/facades/vault.dart:17`), so serialise the record yourself; JSON is fine and the key must be a single fixed constant so `clear()` is total. Normalise the base URL on construction: strip a trailing slash and reject a URL without a scheme, because every later call concatenates onto it and `Http` only bypasses the driver `base_url` when the string starts with `http:` or `https:`. `toString()` must **redact** the password, because a value type's `toString` reaches error messages and logs, and `CLAUDE.md` forbids logging a credential.
    - **References**:
        - `magic/lib/src/facades/vault.dart:17-36`, the four-method API
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/channel.dart:31`, the `@immutable` value-type shape and doc-block density to match
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, "Provider requests": never log a credential, never commit one
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_credentials_test.dart` passes with a case asserting `toString()` does not contain the password
        - a test with a faked Vault asserts `save()` wrote exactly one key and `clear()` removed it, which proves the write went through `Vault` in a way a grep for an absent import cannot
        - a test asserts `describe()` on `http://h:8080/live/bob/s3cret/1.ts?username=bob&password=s3cret` contains neither `s3cret` nor a query string
    - **QA**: `flutter test test/app/protocol/xtream/xtream_credentials_test.dart`. Assert: a round trip through a faked Vault returns an equal record; a base URL given as `http://host:8080/` loads back as `http://host:8080`; a URL with no scheme throws; `toString()` contains the username and not the password; `describe()` redacts both the query and the credential path segments.
    - **Must NOT**:
        - Put the credential in any other store, or add a second Vault key beyond the one constant
        - Log, print or include the password in an exception message
        - Depend on anything under `lib/app/provider/` or on the client; this file is a leaf

- [x] **Step 2**: Write the type-drift coercion helpers the wire demands
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: one file of small pure functions, but each one encodes a measured wire behaviour rather than a general convenience, so it needs the research in front of it.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_json.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_json_test.dart`
    - **Description**: Pure top-level functions that read one field out of a decoded JSON map and return a Dart type, absorbing the drift this protocol actually sends. Needed: an int reader that accepts a bare number **or** a quoted string (`auth` is bare while `max_connections` is quoted, in the same object); a nullable-string reader (`epg_channel_id`, `exp_date`); a bool reader for the bare `0` / `1` integers (`tv_archive`, `now_playing`); a double reader (`rating` arrives quoted beside `rating_5based` bare); and an epoch reader that treats `0`, a negative, a missing key and an unparsable value all as **null meaning no-expiry**, which two independent real clients do. Also a base64 text reader that falls back to the **raw string** on decode failure, because panels disagree about whether EPG text is encoded and `iptvnator` hedges exactly this way. Every numeric read goes through `num` first and converts after: on web `int` and `double` share one float, so `as int` throws on a fractional value and `as double` throws on a bare integer. Finally a body reader that accepts either an already-decoded `Map` or a raw `String` and decodes the latter, because the panel answers `text/html` on some paths and Dio then skips its JSON fast path entirely.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-mock-surface.md`, the per-response field tables with the type as sent
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-dart-http.md`, item 3, the web-versus-native number rule
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-xtream-reality.md`, section 3, the four real unreliabilities
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_json_test.dart` passes with at least one case per drift shape named in the Description
        - `grep -cE 'as int|as double' lib/app/protocol/xtream/xtream_json.dart` returns 0
    - **QA**: `flutter test test/app/protocol/xtream/xtream_json_test.dart`. Assert: `1` and `"1"` both read as `1`; `exp_date` of `null`, `"0"`, `"-1"` and `"garbage"` all read as null; a base64 title decodes and a non-base64 title returns unchanged; a `"7.5"` and a `7.5` both read as `7.5`.
    - **Must NOT**:
        - Import anything from `lib/app/models/` or `magic`; these are pure functions over maps
        - Throw on a shape the protocol is known to send; an unreadable field returns null and the caller decides

- [x] **Step 3**: Fix magic's lost header case, in the sibling repository
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: a one-line change plus a test, but it lands in another repository with its own CLAUDE.md and its own definition of done, which has to be read first.
    - **Files**:
        - `/Users/anilcan/Code/fluttersdk/magic/lib/src/network/drivers/dio_network_driver.dart`
        - `/Users/anilcan/Code/fluttersdk/magic/test/network/` (a new or extended test, named per that repo's convention)
    - **Description**: magic's Dio driver never sets `preserveHeaderCase`, whose default is `false` (`dio-5.11.1/lib/src/headers.dart:11`, `lib/src/options.dart:152`), and the IO adapter forwards the flag (`io_adapter.dart:109`). So every header the `Http` facade sends is lowercased, and watchools requires exactly `User-Agent` because ExoPlayer's lookup is case sensitive and a lowercase key silently ships the wrong agent. It cannot be fixed at the call site: the facade accepts only `Map<String, String>` and never exposes Dio `Options`. Set `preserveHeaderCase: true` on the driver's `BaseOptions`, add a test proving a mixed-case key survives, and open a PR. **Read `/Users/anilcan/Code/fluttersdk/magic/CLAUDE.md` before the first edit**; that project's conventions win inside its tree, and per `.claude/rules/workflow.md` a sibling PR needs its own CI green before merge.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/verification-log.md`, the three-link evidence chain
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/.claude/rules/workflow.md`, the sibling flow: branch, that project's gates, PR, CI green
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, "Provider requests", the exact-case requirement
    - **Done when**:
        - `grep -n 'preserveHeaderCase' /Users/anilcan/Code/fluttersdk/magic/lib/src/network/drivers/dio_network_driver.dart` returns a line setting it true
        - magic's own test suite passes: `cd /Users/anilcan/Code/fluttersdk/magic && flutter test test/network/`
    - **QA**: In magic: `flutter test test/network/`. Assert a request made with a `User-Agent` key reaches the adapter with that exact casing. Then report the finding in the watchools reply per `CLAUDE.md`'s ecosystem rule, with the source line, the measurement, the local opt-out and the fix.
    - **Must NOT**:
        - Change anything in watchools in this step
        - Widen the change beyond header-case preservation; a per-request timeout is a separate gap and a separate PR
        - Merge without that repository's CI green
        - Treat the PR or its CI as this step's completion. Opening the PR and waiting for CI is real work but it is not provable by a command in under a minute, so it does not gate the wave; the publish and the `magic:` constraint bump in this repository's `pubspec.yaml` are tracked in `## Deferred Ideas` as the follow-through `.claude/rules/workflow.md` requires

### Wave 2

- [x] **Step 4**: Give provider traffic its own driver, then write the client over the handshake and nine actions
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, every request through `Http` carries the user's watchools bearer token because `AuthInterceptor` is attached to the one shared driver with no host test; after, provider requests resolve a separate interceptor-free driver and no watchools credential can reach a third-party host. This step decides which hosts receive our auth token.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_client.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_client_test.dart`
    - **Description**: **First, the driver, because the client must never resolve the shared one.** `magic/lib/src/auth/auth_interceptor.dart:20-30` attaches the token to every request with no host, scheme or origin test, `auth_service_provider.dart:85` adds it to the single `'network'` driver, and `Http` resolves exactly that singleton (`magic/lib/src/facades/http.dart:23`). This app registers both providers today (`lib/config/app.dart:27` and `:31`). So an absolute-URL call through `Http` would ship `Authorization: Bearer <watchools token>` to a stranger's IPTV panel over plaintext HTTP, and worse: `auth_interceptor.dart:40-73` treats a 401 from that panel as a signal to call `refreshToken()`, re-attach the **fresh** token and replay the request to the panel, while a failed refresh calls `Auth.logout()`. Register `provider_network` as a second `DioNetworkDriver` in `app_service_provider.dart` with an empty base URL, empty default headers, **no interceptors**, and `configureDriver((dio) { dio.options.followRedirects = false; })` so a 3xx is a fault to surface rather than a hop to take. Both `DioNetworkDriver` and `NetworkDriver` are exported from `magic/lib/magic.dart:104-105`, so this needs no sibling release. Then `XtreamClient` resolves `provider_network` and exposes one method per action: the handshake (no `action`), `get_live_categories`, `get_vod_categories`, `get_series_categories`, `get_series`, `get_live_streams`, `get_vod_streams`, `get_vod_info`, `get_short_epg`, `get_simple_data_table`. Credentials go in the `query:` map, **never** built into the URL string, because that is the only reason the telescope integration's recorded URL stays clean (`magic_devtools/lib/src/telescope_integration.dart:191` records `options.path`, which excludes the query). Send `{'User-Agent': credentials.userAgent}`. Do **not** try to suppress `Content-Type` by omitting it from the header map: `Options(headers: headers)` merges **over** the driver's `BaseOptions.headers` (`magic/lib/src/network/drivers/dio_network_driver.dart:185-191`, `:24-28`), so anything the driver declares still ships. The dedicated `provider_network` driver is registered with **empty** default headers, which is where that is actually solved, and the body still has to survive arriving as a raw `String` when a panel answers `text/html`, which the dual map-or-String reader in `lib/app/protocol/xtream/xtream_json.dart` handles. Pin the scheme, host and port of every URL to the stored panel URL: ignore `server_info.url` for routing and ignore `direct_source` unless its authority matches, because the credentials ride in the **path** of a stream URL and a rewritten field hands them to any host. Do not classify a fault, do not paginate, send `limit` on `get_short_epg`, and fall back to the typo'd `get_simple_date_table` on an empty result.
    - **References**:
        - `magic/lib/src/auth/auth_interceptor.dart:20-30` and `:40-73`, the unconditional attach and the 401 replay
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-mock-surface.md`, the route and action list with query parameters
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-xtream-reality.md`, sections 1, 2 and 5
        - `magic/test/network/http_fake_test.dart:16-56`, the faking pattern to test against
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_client_test.dart` passes
        - a test seeds a token through `Auth` and asserts the recorded provider request has **no** `Authorization` header; this is the step's load-bearing assertion
        - `! grep -q "Http\." lib/app/protocol/xtream/xtream_client.dart`, proving the client never resolves the shared driver
        - a test asserts the stream-list methods' query maps carry no pagination key, by inspecting the recorded request rather than by grep, since `get_short_epg` legitimately sends `limit`
        - a test asserts the request carried the header key exactly `User-Agent`, marked `skip:` with the reason naming step 3's sibling PR. **Skipped, not red**: step 14 requires `flutter test --coverage` green, so a deliberately failing test would make the plan unfinishable by its own gate. Unskip it in the same commit that bumps the `magic:` constraint after the sibling publishes
    - **QA**: `flutter test test/app/protocol/xtream/xtream_client_test.dart` with a faked provider driver. Assert: no `Authorization` key on any provider request even with a token cached; the handshake carries `username` and `password` in the query and no `action`; a `text/html` body arriving as a raw `String` still parses; a 200 carrying the plain word `blocked` returns a non-null body rather than throwing; a 302 is surfaced rather than followed.
    - **Must NOT**:
        - Resolve the `network` driver or call any `Http.*` method for provider traffic
        - Add an interceptor to `provider_network`, now or later
        - Build the credentials into the URL string rather than the `query:` map
        - Follow a redirect, or take a host from `server_info` or `direct_source`
        - Classify a fault, decide a retry, or touch `ProviderFault`
        - Interpolate or `toString()` a `Uri`, `RequestOptions`, `MagicRequest` or `MagicError`, all of which carry the full URI

- [x] **Step 5**: Model the account and classify the four faults
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: the disjunction is three lines of boolean logic whose failure mode is showing a full line-up for a dead subscription, and the inputs drift in type and nullability, so it is small code carrying a large consequence.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/protocol/xtream/xtream_account.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/provider_fault.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/protocol/xtream/xtream_account_test.dart`
    - **Description**: **Add the fourth `ProviderFault` member, `evicted`, here rather than in step 9**, because this step is the first code that names it and a member added later would not compile against this one. Narrow `throttled`'s doc (`provider_fault.dart:39-45`) to hand the connection case over: the split is not cosmetic, since for `throttled` a retry is safe and for `evicted` the retry itself evicts the other device. Step 9 then only renders it. `XtreamAccount` parses the handshake's `user_info` and `server_info` through the readers in `lib/app/protocol/xtream/xtream_json.dart`, holding `auth`, `status`, `expiresAt`, `maxConnections`, `activeConnections`, `allowedOutputFormats` and the panel clock pair. Expose `bool get active` as the **disjunction**: not active when `auth != 1`, **or** `status` is not `Active` compared case-insensitively, **or** `expiresAt` is non-null and in the past. Treat a missing `status` with a truthy `auth` as active, which is what real clients do. Expose `bool get atConnectionLimit` as `activeConnections >= maxConnections`, which is a live-but-full subscription and orthogonal to death. Then a pure function mapping an account plus a response to a `ProviderFault?`: `expired` when the disjunction fails, `throttled` when the body is the generic non-JSON denial, `unreachable` on `statusCode == 0`, `evicted` when the account was active and at its connection limit. Never infer health from a list parsing: a dead subscription still returns its whole catalogue and fails only at the stream.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-xtream-reality.md`, section 4, the disjunction confirmed twice and the case-insensitive refinement
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/provider_fault.dart:24`, the vocabulary and each member's doc
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-mock-surface.md`, the nine account shapes and what each returns
    - **Done when**:
        - `flutter test test/app/protocol/xtream/xtream_account_test.dart` passes with one case per mock account: `demo`, `expired`, `lapsed`, `lifetime`, `banned`, `disabled`, `throttled`, and unknown credentials
        - a test asserts the `lifetime` account with `exp_date: null` is **active**, the trap a naive date comparison fails
    - **QA**: `flutter test test/app/protocol/xtream/xtream_account_test.dart`. Assert: `lapsed` (auth 1, status Active, past date) is not active; `expired` (status Expired, future date) is not active; `lifetime` (null date) is active; `"active"` lowercase is active; a single-key `{auth: 0}` response parses without throwing and is not active.
    - **Must NOT**:
        - Add a fifth `ProviderFault` member
        - Read `Vault`, make an HTTP call, or touch the store; this is a pure parse plus a pure decision
        - Treat a successful catalogue fetch as evidence of health
        - **Keep `username` or `password` on the parsed account.** The panel echoes both back inside `user_info` (`tool/xtream-mock/server.mjs:151-152`), and `magic_devtools/lib/src/telescope_integration.dart:207` records the first 8 KiB of every response body, which is far more than a handshake. So a debug build writes the provider password into `TelescopeStore` where the `telescope_*` tools and any session transcript can read it. Strip both fields on receipt, in this file, because the telescope interceptor is magic_devtools' and runs before anything of ours: a wrapper downstream is too late

### Wave 3

- [x] **Step 6**: Map the wire onto Channel, Programme and TitleItem
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: factories on four existing value types, following their existing shape, but each field needs the right source field and the derived ones must not be invented.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/channel.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/programme.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/models/title_item.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/models/channel_test.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/models/title_item_test.dart`
    - **Description**: Add `Channel.fromXtream`, `Programme.fromXtream` and `TitleItem.fromXtream` as factories on the existing models rather than a separate mapper layer, per `CLAUDE.md`'s "No new file where an edit to an existing one would do". Map `num` to `number`, `name` to `name`, the resolved category name to `group`, `stream_icon` to `logoUrl` with an empty string becoming null because it is empty far more often in reality than in the mock. `ChannelStatus` is **stored** on the model but must be **computed** here from the schedule against the injected clock, never read from the wire, because the wire has no such field and a persisted status goes stale. `Programme`'s unit is minutes since the schedule's midnight, **never wrapped**, per `CLAUDE.md`: a block running to 00:30 ends at 1470. `facts` is built from what the wire actually carries and stays empty rather than guessing. Leave `favourite` and `progress` alone: they are user state, not provider state, and step 8 owns them. Update `channel.dart:29`'s doc, which currently promises the model "becomes a `Model` when the Xtream client lands"; it does not, and the reason is that the controllers filter in Dart so there are no queries for an ORM model to serve.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-controllers.md`, the stored-versus-derived tables for all four models
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/support/guide_fixture.dart:30`, the shape the fixtures produce and this must match
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, the never-wrapped minute convention
    - **Done when**:
        - `flutter test test/app/models/` passes
        - a test asserts a programme running past midnight ends at a minute above 1440 rather than wrapping
        - a test asserts the same live entry maps to `ChannelStatus.live` against a clock inside a programme and to `idle` against a clock outside every programme, which proves the status is computed rather than read from the wire
    - **QA**: `flutter test test/app/models/channel_test.dart test/app/models/title_item_test.dart`. Assert: a live entry with an empty `stream_icon` yields a null `logoUrl`; a channel with no EPG yields an empty `schedule` and `hasSchedule` false; a title with `container_extension: mkv` keeps it; a programme spanning midnight is not wrapped.
    - **Must NOT**:
        - Create a mapper file or a wire-shaped model above these types
        - Persist or read `ChannelStatus` from the provider
        - Touch `favourite` or `progress`

- [x] **Step 7**: Build the catalogue store as a cold-start cache
    - **Type**: code
    - **Tier**: senior
    - **Why this tier**: rule-5-criticality: before, no provider-supplied string reaches SQL anywhere in the app; after, 41,000 third-party channel names, category names and descriptions from a host the user typed are written into SQLite on every refresh, so this step decides the injection surface and whether it is bound or interpolated.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/catalogue_store.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/pubspec.yaml`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/catalogue_store_test.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/catalogue_store_scale_test.dart`
    - **Description**: `CatalogueStore` owns the schema and the read and write of the cached catalogue. One table per kind keyed by the account, with columns that exist to rebuild a value object rather than to be filtered on: there are no queries, because the controllers filter in Dart over an in-memory list, which is also why the ORM's missing `Blueprint.index()` does not matter here. Carry `tv_archive` and `tv_archive_duration` as columns from day one so `ChannelStatus.catchup` stays computable and no migration follows. Every provider string is **bound**, never interpolated: `DB.statement(sql, params)` takes a params list (`magic/lib/src/facades/db.dart:105`). For the bulk path prefer one prepared statement over `insertAll`, which runs an `INSERT` plus a `SELECT last_insert_rowid()` per row and so costs 76,494 statements for 38,247 titles; reach `Magic.make<DatabaseManager>('db').connection` and use `prepare`, inside one `DB.transaction`. That reaches `CommonDatabase` from `package:sqlite3`, which is currently a **transitive** dependency only (`pubspec.lock:893`, absent from `pubspec.yaml`), and `flutter_lints` brings `depend_on_referenced_packages`, so importing it without a direct constraint fails step 14's `flutter analyze --fatal-infos`. Add `sqlite3` to `pubspec.yaml` with the constraint magic already resolves, and leave `pubspec.lock` unstaged if a local `pub get` rewrites it with sibling paths. Keep that write **synchronous and uninterrupted**: `DB.transaction` wraps a sync BEGIN/COMMIT around an async callback, so an `await` inside it leaves the transaction open for any other query in the app to join. A refresh replaces the previous contents for that account; preserve the user-state columns (`favourite`, `progress`) across a replace rather than dropping them, which is the whole reason they are separate.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-vault-sql.md`, the signatures, the verified ORM limits and the per-row cost table
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/oracle-architecture.md`, recommendation 5 and the open-transaction hazard
        - `magic/test/database/query_builder_test.dart`, the headless ORM test pattern that proves this is testable
    - **Done when**:
        - `flutter test test/app/provider/catalogue_store_test.dart` passes
        - the injection round-trip test below passes. **This replaces the grep an earlier draft used**, which could not fail: a pattern anchored to `statement('` misses `'''`-quoted multi-line SQL and misses any `DB.statement(sql, params)` whose `sql` was built on an earlier line, which is exactly how this SQL will be written
        - a test writes a channel whose name is `Robert'); DROP TABLE channels;--` and an EPG title of `?), (1, (SELECT ...` through the real writer, then asserts both tables survive with the literal strings stored
        - a test asserts every `DB.statement` call the writer makes carries a non-empty params list, which is the anti-stacking defence rather than a style rule
        - a test asserts `favourite` survives a full refresh
    - **QA**: `flutter test test/app/provider/catalogue_store_test.dart` against an in-memory database. Assert: a round trip of 1,000 channels returns equal value objects; both injection-shaped strings are stored and read back literally; a refresh replaces rows but preserves `favourite`; the write is inside one transaction, provable by a rollback test where a mid-write throw leaves the previous contents intact.
    - **Must NOT**:
        - Interpolate any provider-supplied value into a SQL string, **including inside a multi-row `INSERT`**
        - Call `DB.statement` with an empty params list when the SQL carries any provider-derived value. This is not stylistic: `sqlite3-3.5.2/lib/src/implementation/database.dart:287-310` routes an empty params list to `sqlite3_exec`, whose own comment says it "can run multiple statements at once", so one interpolated value there is arbitrary DDL and DML rather than a widened `WHERE`. A **non-empty** params list goes to `prepare(sql, checkNoTail: true)`, which rejects a trailing statement, so passing params is itself the anti-stacking defence
        - Build a multi-row `VALUES` list as text. Emit `?` placeholders only and chunk on a **computed placeholder budget** rather than a guessed row count, because SQLite caps bound variables per statement and hitting that cap is exactly the moment a developer reaches for string building
        - `await` anything inside the `DB.transaction` callback. `beginTransaction()` is synchronous on a single connection (`magic/lib/src/facades/db.dart:159-161`, `:183-193`), so any other `DB` write during an `await` joins this transaction and is rolled back with it
        - Add an index, a `LIKE` query or a `whereIn`; there are no queries here and the builder cannot express them anyway
        - Derive a table, column or index name from provider data; every identifier is a fixed literal

### Wave 4

- [x] **Step 8**: Own the session, the classification and the connection gate
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-none: it is the only object holding both the credentials and the last handshake, so every wrong answer it gives is a plausible one, and it is where the unmeasured connection-slot assumption is enforced.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/provider/provider_session.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/provider/provider_session_test.dart`
    - **Description**: `ProviderSession` is the app's single handle on "which provider, is it healthy, what is cached". It loads `XtreamCredentials` from `Vault`, holds the last `XtreamAccount` and the current `ProviderFault?`, and exposes the catalogue the controllers read. **Bind and start it here, because nothing else does.** `app_service_provider.dart:15-28` binds the two controllers with `Magic.put` in `register()`, which runs before `Magic.init()` completes; this session may not do I/O there. So bind the instance in `register()` and kick a `start()` from `boot()`, which is where `RouteServiceProvider` already does its deferred work, and have `start()` load the credentials and the cached catalogue and then classify. Until `start()` completes the session reports no credentials, which is the state step 10's fixture fallback covers. Note `lib/app/providers/` is excluded from the CI coverage denominator, so wiring placed there carries no coverage obligation while the session's own logic must clear 90%; keep the provider edit thin and the logic in `provider_session.dart`. Mind the directory names: `lib/app/provider/` is this layer and `lib/app/providers/` is magic's service providers, one character apart. Classification lives here rather than in the client because a single response cannot be classified: the same 200-plus-non-JSON shape is produced by throttled, a blocked address, a blocked user agent, an HTML error page and an expired stream request alike (`tool/xtream-mock/README.md:126-129`), so the answer needs the handshake as context. Classify on **every session start** from the handshake, never from whether a list parsed. Gate every refresh on **not currently playing**: whether a `player_api.php` call consumes one of the account's connection slots is unmeasured and the measured eviction had `.ts` on both sides, so the conservative rule holds until measured. Expose a `refresh()` that a caller may not invoke during playback and that returns without doing anything rather than throwing. Own `favourite` and `progress` writes, since they are user state that must survive a catalogue replace.

**Also fetch a now/next schedule, because without one two of the four screens render nothing.** `Şimdi` and `Zaman` are built around a schedule: the hero, the progress bars, the now line and the "N dk kaldı" all read `Channel.schedule`, and a provider channel mapped by step 6 has an empty one. So the full XMLTV import stays deferred but the **minimum** does not: call `get_short_epg` with its `limit` for the channels currently on screen, map the entries through `Programme.fromXtream`, and merge them into the held channels. That action is already implemented by step 4 and already served by the mock, and the volume is small because 91% of real channels carry no `epg_channel_id` at all (`.ac/research/player-layer.md:286`), so only about 268 of 2,976 can have a guide. A channel with no `epg_channel_id` is skipped rather than requested, which is also what makes `ChannelStatus` computable in step 6 rather than always `idle`.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/oracle-architecture.md`, recommendation 3 and the healthy-catalogue hazard
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/app_service_provider.dart:15-28`, where a singleton is bound and why eagerly
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/providers/route_service_provider.dart:24-54`, `boot()` as the place deferred work already happens
    - **Done when**:
        - `flutter test test/app/provider/provider_session_test.dart` passes
        - a test asserts a `lapsed` account yields `ProviderFault.expired` **even though** the catalogue lists parsed successfully
        - a test asserts `refresh()` during playback is a no-op rather than a request, provable by `assertSentCount(0)` on the faked provider driver
        - a test asserts a channel with a non-null `epg_channel_id` gains a non-empty `schedule` after the short-EPG pass, and one with a null id is never requested
    - **QA**: `flutter test test/app/provider/provider_session_test.dart` with a faked provider driver and a faked Vault. Assert: each of the four faults is produced by its shape; a healthy handshake clears a previous fault; `favourite` set before a refresh is still set after it; `start()` with no stored credentials leaves the session reporting none rather than throwing.
    - **Must NOT**:
        - Perform I/O in a constructor or during `Magic.init()`; `register()` binds, `boot()` starts
        - Classify from a catalogue response instead of the handshake
        - Fetch while playback is active
        - Request an EPG for a channel whose `epg_channel_id` is null
        - Import the full XMLTV guide; that is deferred and this is the on-screen minimum

- [x] **Step 9**: Render the `evicted` fault the account model introduced (run in wave 2, not wave 4: see Dependency Notes)
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: one rendered arm across a component, its recipe and its preview, following three existing arms exactly.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.recipe.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.preview.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/ui/components/provider_notice_test.dart`
    - **Description**: Step 5 adds the `ProviderFault.evicted` member; this step renders it. Three files, because the component is a recipe-driven atom: `provider_notice.recipe.dart` carries a `variants['fault']` map keyed by **member name**, read as `providerNoticeRecipe()(variants: {'fault': fault.name})` at `provider_notice.dart:76`, so a member with no variant entry renders with no styling. Add the `evicted` variant there, the message arm in `provider_notice.dart`, and the entry in `provider_notice.preview.dart` so `/preview` shows all four. The filename is `provider_notice.preview.dart` with a dot, not an underscore: `previews:refresh` discovers only `*.preview.dart` (`index.dart:4-5`). On the retry contract, follow the component as built rather than inventing a second shape: it always renders exactly one required-callback button (`provider_notice.dart:58-63`, `:115-125`), so `evicted` keeps that button and the **label** says the retry is manual and will interrupt the other device. Copy voice matches the existing three: name what happened from where the user sits, not what the protocol did. Wind only, and the status colours come from `lib/config/watchools_status_tokens.dart` or the generated theme's semantic aliases, never a hand-picked hex.
    - **References**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.recipe.dart`, the `variants['fault']` map the new member must join
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.dart:58-63`, the single-button shape that fixes the retry contract
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/oracle-architecture.md`, recommendation 4, the retry asymmetry that motivates the label
    - **Done when**:
        - `flutter test test/ui/components/provider_notice_test.dart` passes with a case per member, four in total
        - a test asserts the `evicted` arm's button label differs from `throttled`'s, which is the whole point of the split
        - `! grep -qE 'Colors\.|Color\(0x' lib/ui/components/provider_notice/provider_notice.dart`
        - `./bin/fsa previews:refresh` leaves `lib/_previews.g.dart` carrying the new entry
    - **QA**: `flutter test test/ui/components/provider_notice_test.dart` through `wrapWithTheme()` with `setUp(WindParser.clearCache)`. Assert each of the four renders its own message and its own recipe variant, and that `evicted`'s button label names the consequence.
    - **Must NOT**:
        - Add or change a `ProviderFault` member; step 5 owns the enum
        - Change what `unreachable`, `expired` or `throttled` render
        - Use a raw colour or a raw `TextStyle`
        - Rename the preview file or drop the `.preview.dart` suffix

### Wave 5

- [x] **Step 10**: Swap the controllers off the fixtures
    - **Type**: code
    - **Tier**: junior-high
    - **Why this tier**: rule-1-cross-layer: two controllers, their caches and the four internal cache invalidations, plus the fixture seam and the scale define that the performance harness depends on.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/controllers/guide_controller.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/controllers/library_controller.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/support/fixture_scale.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/controllers/guide_controller_test.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/app/controllers/library_controller_test.dart`
    - **Description**: Both controllers currently read `FixtureScale.channelList` (`guide_controller.dart:110`) and `FixtureScale.titleList` (`library_controller.dart:36`). Point them at `ProviderSession` instead, and give each a `ProviderFault?` getter the layouts read. Keep the fixture path alive behind the existing `WATCHOOLS_SCALE` define, because `tool/dusk/perf.sh` depends on a compile-time scale and the performance harness must keep working: a session with no credentials falls back to the fixture rather than showing an empty app. Preserve every existing getter signature exactly, because four layouts and their tests read them; this step must not change what `matches`, `sections`, `rails`, `countLabel` or `groups` return for a given input. Invalidate all four caches on a catalogue change, the same way the mutation methods already do. Add `WATCHOOLS_TITLE_SCALE` while here: `fixture_scale.dart:68` is `titles => channels ~/ 2` and `:58` clamps channels at 50,000, so the real 12.9:1 title-to-channel ratio is unreachable and the library screen has never been measured above 2,500 titles.

**Guard the empty catalogue, which currently throws.** `guide_controller.dart:115` is
`late Channel _channel = channels.first` and `library_controller.dart:41` is
`late TitleItem _selected = titles.first`, and `curtain_layout.dart:41` reads
`controller.selected` unconditionally. A fixture is never empty so nothing has exercised this, but
a provider list can be: a fresh account mid-refresh, a category with nothing in it, or a fault.
Make both selections nullable or lazily absent, and give `curtain_layout` an arm for no selection.
This is the same class as the fault arm in step 11 and lands in the same pull request.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-controllers.md`, the full read and mutate surface of both controllers with line numbers
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, "Measuring at provider scale", why the define is compile-time
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/app/support/fixture_scale.dart:58-85`, the seam being widened
    - **Done when**:
        - `flutter test test/app/controllers/` passes with every pre-existing assertion unchanged
        - a test asserts a session with no credentials still yields the fixture line-up, so the perf harness path survives
        - a test asserts an **empty** provider catalogue does not throw from either controller, covering the two `late … .first` fields
        - `./tool/dusk/perf.sh` still launches, proving the define still reaches the app
    - **QA**: `flutter test test/app/controllers/`. Assert: with a faked session holding two channels, `matches` returns two and `groups` returns their groups; with no credentials, the fixture count appears; a fault on the session surfaces on the controller's getter without emptying `matches`.
    - **Must NOT**:
        - Change the return type or semantics of any existing getter
        - Delete the fixture path or the `WATCHOOLS_SCALE` define
        - Perform I/O from a getter; the controller reads what the session already holds

- [x] **Step 11**: Render the fault on all four surfaces
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: four layout files, each a small conditional change, following a placement the component's own doc already specifies.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/now_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/time_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/showcase_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/layouts/curtain_layout.dart`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/test/ui/layouts/`
    - **Description**: A fault renders where the empty state renders: inside the `flex-1` body branch, under the pinned toolbar, per `provider_notice.dart:28-32`. Three layouts already branch there and gain a third arm: `now_layout.dart:79-98`, `time_layout.dart:146-149`, `showcase_layout.dart:66-86`. **`curtain_layout.dart:40-71` has no empty branch at all** and always renders `controller.selected`, so it needs a new arm rather than a third one; `CLAUDE.md`'s "one arm of an existing conditional per surface" is wrong about that fourth file and this step is where it gets corrected. Fault takes precedence over empty: a provider fault and an empty result are different statements and the fault is the more specific one. The toolbar and the category strip stay **above** the branch, because a widget owning focus or a scroll position must not sit inside a branch that swaps, which this app has already paid for once.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/explore-controllers.md`, the four quoted conditionals
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/CLAUDE.md`, the fourth layout trap: a focus or scroll owner must not sit in a swapping branch
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/lib/ui/components/provider_notice/provider_notice.dart:28-32`, the specified placement
    - **Done when**:
        - `flutter test test/ui/layouts/` passes
        - a test per layout asserts `ProviderNotice` appears when the controller holds a fault and the toolbar is still present
        - `grep -n 'ProviderNotice' lib/ui/layouts/*.dart` returns a hit in all four files
    - **QA**: `flutter test test/ui/layouts/` via `pumpScreen()` at both desktop and mobile sizes. Assert: with a fault set, the notice renders and the toolbar renders; with a fault **and** an empty result, only the notice renders; with neither, the body is unchanged from today.
    - **Must NOT**:
        - Move the toolbar or the category strip inside the branch
        - Render a fault and an empty state at once
        - Change any layout's arrangement beyond adding the arm

### Wave 6

- [ ] **Step 12**: Close the four mock gaps the research exposed
    - **Type**: code
    - **Tier**: junior
    - **Why this tier**: rule-2-context: a zero-dependency Node fixture with an established idiom and a 70-check verifier, so the work is pattern-following plus a check per behaviour.
    - **Files**:
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/server.mjs`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/catalogue.mjs`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/verify.mjs`
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/README.md`
    - **Description**: Real panels do four things this fixture cannot currently produce, each of which makes a client hedge from step 2 or step 4 untestable. Add, each behind an account or a query flag so the existing 70 checks keep passing: EPG text sent as **plain text** rather than base64, since panels disagree and a real client falls back on decode failure; an `exp_date` of `0` rather than null, which means no-expiry and which a naive date comparison reads as 1970; a panel that implements only the typo'd `get_simple_date_table`; and a panel that refuses a bare handshake so the client must try `get_account_info`. Add a verify check per behaviour, and update the README's "deliberately absent" section, which currently lists all four as gaps.
    - **References**:
        - `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-xtream-reality.md`, sections 3 and 5, each behaviour with the real client that hedges it
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/verify.mjs`, the `check()` idiom and how a panel is started on its own port
        - `/Users/anilcan/Code/watchools/.claude/worktrees/player-reconnect/tool/xtream-mock/README.md`, the "deliberately absent or unfaithful" section being updated
    - **Done when**:
        - `node tool/xtream-mock/verify.mjs` prints "All checks passed." and its output names each of the four new behaviours. **Not a check count**: `verify.mjs` counts only failures (`:42`, `:51`) and prints no total, so a numeric criterion here would be unobservable
        - the README no longer lists these four as absent
    - **QA**: `node tool/xtream-mock/verify.mjs`. Assert every pre-existing check still passes and each new behaviour is covered: plain-text EPG decodes, `exp_date: 0` is served, the typo action answers, the bare handshake is refused.
    - **Must NOT**:
        - Change any existing account's behaviour, which would silently move the client's target
        - Add a dependency; this tool is zero-dependency on purpose
        - Touch the media encoding pipeline

- [ ] **Step 13**: Measure the catalogue write at real scale
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**: The oracle set an escalation trigger here and it decides whether this design ships. `DB.statement` and the prepared path are **synchronous**, so whatever the write costs is a frozen UI for exactly that long. Write 2,976 channels and 38,247 titles, the real provider's measured counts, and time it. Above roughly two seconds the synchronous path is not survivable behind a progress state on a television, and the answer becomes a background isolate with its own connection, which magic's web arm cannot provide: stop and re-plan rather than shipping it.
    - **Commands**:
        - `flutter test test/app/provider/catalogue_store_scale_test.dart --plain-name 'writes the real catalogue size'`
    - **Done when**:
        - the test prints an elapsed millisecond figure for each of the two writes
        - the figure is recorded in the evidence file with the machine it was measured on
    - **QA**: read the printed elapsed time. Under 2,000 ms for the combined write, proceed. Over it, halt and report; do not soften the criterion to pass it.
    - **Evidence**: `.ac/plans/xtream-codes-protocol-layer-watchools/evidence/13-catalogue-write-timing.txt`
    - **Must NOT**:
        - Reduce the row counts to make the number look better; 2,976 and 38,247 are the measured real ones
        - Proceed past a figure over two seconds without re-planning

- [ ] **Step 14**: Run every gate the project enforces
    - **Type**: verification
    - **Files**: (no source edits; runs commands)
    - **Description**: The full local gate set before the pull request, in the order CI runs it. The lock check runs **before** `pub get`, because that is the only moment the committed file is still the committed file. Coverage is the one most likely to fail on this plan: the layer is large and its own logic must clear 90% over a denominator that excludes only the generated scaffold.
    - **Commands**:
        - `git diff --stat` then confirm `pubspec.lock` is unstaged if it changed
        - `flutter analyze --fatal-infos --fatal-warnings`
        - `dart format --output=none --set-exit-if-changed lib test`
        - `flutter test --coverage`
        - `node tool/xtream-mock/verify.mjs`
    - **Done when**:
        - `flutter analyze` reports no issues
        - `dart format` reports nothing changed
        - `flutter test --coverage` is green and the printed `hit/found` clears 90% over the CI exclusion list
        - `node tool/xtream-mock/verify.mjs` prints "All checks passed."
    - **QA**: run each command and capture its output. Every one exits 0. Read the coverage `hit/found` rather than trusting a green test run, because the denominator moves when a test imports something new.
    - **Evidence**: `.ac/plans/xtream-codes-protocol-layer-watchools/evidence/14-gates.txt`
    - **Must NOT**:
        - Stage `pubspec.lock` if a local `pub get` rewrote it with sibling paths
        - Lower the coverage floor to pass; a floor moves in the same pull request as the tests that earned it
        - Skip the mock verifier because it is not in CI; step 12 changed it

## Risks Accepted

**All four interview decisions were locked on their recommended option without an answer.** The
questions were put with research-grounded recommendations and no reply arrived within the wait, so
each below is a default rather than a choice. Any of them is cheap to revisit before execution.

1. **The header-case defect is fixed in parallel, not first.** Step 4's test asserts exactly
   `User-Agent` and goes **red until step 3's sibling PR ships and is published**. That is
   deliberate: the requirement lives in code rather than in someone's memory. The exposure while
   red is Android only, since macOS and iOS do not read the header case.
2. **Whether a `player_api.php` call consumes a connection slot is unmeasured**, and step 8 assumes
   it does. The measured eviction had `.ts` requests on both sides
   (`.ac/research/player-layer.md:226-230`). The cost of the assumption is a refresh that waits for
   playback to stop when it might not have needed to; the cost of the opposite assumption is
   killing the channel the user is watching. The controlled test that would settle it is in
   `## Deferred Ideas`.
3. **Two layers with no `CatalogueSource` interface.** One implementation today, and `CLAUDE.md`'s
   rule is the third concrete caller. If an M3U source lands, that is the second caller and the
   interface is still premature by that rule; at the third, extract it.
4. **The EPG is out of v1.** The two live layouts are built around a schedule and will keep reading
   a fixture one until it lands, so `Şimdi` and `Zaman` are only partly real after this plan. This
   is the item most likely to want pulling forward.
5. **`Channel` stays a value type**, contradicting its own doc block at `channel.dart:29` which
   promises it "becomes a `Model` when the Xtream client lands". Step 6 corrects the doc. The
   reason: the controllers filter in Dart, the query builder cannot express those filters, so
   there are no queries for an ORM model to serve.
6. **Vault on web is not a secret store, and it is worse than the first draft of this section
   said.** `flutter_secure_storage_web-2.1.1/lib/flutter_secure_storage_web.dart:37-41` returns
   `web.window.localStorage`, not IndexedDB, and `:182-191` exports the raw AES-GCM key and writes
   it to **the same localStorage** whenever `wrapKey` is unset. `MagicVaultService`
   (`magic/lib/src/security/magic_vault_service.dart:23-30`) passes only `aOptions` and `iOptions`,
   so `wrapKey` is always unset and there is no app-side way to set it: ciphertext and key sit side
   by side, readable by any same-origin script. A panel password is a reusable credential for a
   paid subscription, not an expiring token.

   **This is the one decision the security pass says should have been an interview question and was
   not**, because it arrived after the questions went out. It is recorded here as accepted only in
   the sense that web is a scaffolded target rather than a shipping one today. The two real
   options, for whenever web ships: hold the password in memory for the session and re-prompt after
   a reload, persisting only the panel URL and username; or add a `webOptions` seam to magic and
   persist knowing what it is. Do not describe web Vault as secure storage in the meantime.

## Cross-Project Observations

Three findings in the `magic` sibling. Each is that repository's work, with its own PR, its own
CLAUDE.md and its own CI, per `.claude/rules/workflow.md`. Only the first is in this plan's scope.

1. **Defect, in scope as step 3.** `DioNetworkDriver` never sets Dio's `preserveHeaderCase`, whose
   default is `false`, so the `Http` facade lowercases every header name on the wire. Evidence
   chain in `research/verification-log.md`. Contradicts a documented consumer requirement and
   cannot be worked around at the call site.
2. **Defect, out of scope, and it is the more serious of the two.** `AuthInterceptor` attaches the
   caller's bearer token to **every** request with no host, scheme or origin test
   (`magic/lib/src/auth/auth_interceptor.dart:20-30`), and `auth_service_provider.dart:85` adds it
   to the single `'network'` driver that `Http` resolves. Any app making an absolute-URL call to a
   third party through `Http` therefore leaks its own auth token. Worse,
   `auth_interceptor.dart:40-73` treats a 401 from that third party as a refresh signal: it calls
   `refreshToken()`, attaches the **new** token and replays the request to the same host, and on a
   failed refresh calls `Auth.logout()`. So a hostile or merely misconfigured host can harvest a
   freshly minted token and log the user out. Step 4 works around it app-side with a dedicated
   interceptor-free driver, which needs no sibling release, but the interceptor wants a host
   allowlist and `NetworkServiceProvider` wants to honour `network.default`
   (`network_service_provider.dart:15` hardcodes `Config.get('network.drivers.api')` and is the
   only reader, so the config's `'default'` key, `drivers` map and per-driver `'driver': 'dio'` key
   promise a multi-driver surface that silently does not exist).
3. **Gap, out of scope.** No per-request timeout: `DioNetworkDriver`'s five raw methods accept only
   `headers`, and the driver's single `timeout` becomes both `connectTimeout` and `receiveTimeout`.
   `receiveTimeout` is per-byte-event rather than total (`dio/options.dart:403-409`), so a
   38,247-row fetch and a handshake share one unchangeable setting.

Also worth a separate look: `magic/CLAUDE.md:92` says "Web = in-memory SQLite" while
`connection_factory_web.dart:41` opens an `IndexedDbFileSystem`-backed database, and
`web/sqlite3.wasm` is present in this repo. The sibling doc is probably stale. And
`sqlite3_flutter_libs: ^0.6.0+eol` is marked end-of-life.

All three go into `.ac/research/ecosystem-defects.md` and, per `CLAUDE.md`, get reported out loud
in the reply that carries this work rather than only in a file.

## Deferred Ideas

- **The connection-slot measurement.** Start a stream on the real account, fire
  `player_api.php?action=get_live_streams` at t=4 s, record whether the stream survives its window.
  Two logged requests, never repeated, per the standing constraint. Settles risk 2 and could
  loosen step 8's gate.
- **The EPG layer**: `xmltv.php` imported once and cached, now/next served from the cache,
  `get_short_epg` per channel on a miss, which is what real clients do. Volume is small: 91% of
  real channels carry no `epg_channel_id` (`.ac/research/player-layer.md:286`), so only ~268 of
  2,976 can have a guide at all.
- **Catch-up URL derivation** across the five conventions, plus the `server_info.timestamp_now`
  clock offset. `tv_archive` is set on 20 of 2,976 channels, so it buys 0.7% of the line-up. The
  columns land in step 7 so no migration follows.
- **`get_series_info`** on the title screen, lazily. Step 4 fetches the series list so the ID space
  is known; the per-series detail is a title-screen concern.
- **A `magic` `insertMany`** that builds multi-row SQL, removing the per-row
  `SELECT last_insert_rowid()`. Step 7 reaches the same place with a prepared statement, so this is
  an improvement rather than a prerequisite.
- **The onboarding screen and the `/saglayici` route.** No user-facing way to enter a credential
  exists after this plan; development seeds `Vault` directly. `ProviderNotice`'s
  `onOpenSettings` already routes to `/saglayici` (`provider_notice.dart:39`), so registering that
  route and building the form is the natural next plan and the one that makes objective 1 reachable
  by a person.
- **Publish magic and bump the constraint.** `.claude/rules/workflow.md` requires it after a
  sibling change, and step 4's `User-Agent` assertion stays `skip:`ped until it happens. The unskip
  belongs in the same commit as the bump.
- **A project-wide redaction lint.** Step 1 gives `describe(Uri)` and step 4 forbids interpolating
  a `Uri`, `RequestOptions`, `MagicRequest` or `MagicError`, but nothing enforces it outside those
  two files. A custom lint or a CI grep would make it a guarantee rather than a convention.
- **`MagicStateMixin` on both controllers** would need them to become `MagicController`s first,
  which is a wider change than a loading state is worth today.
- **A first-class loading state.** `CLAUDE.md` records that loading is deliberately still open and
  should be a skeleton of the layout it replaces rather than a message, which makes it three
  per-surface pieces rather than one shared component. Now more visible than before, because a
  provider fetch has real latency where a fixture had none.
