# Verification log

Stage 2a.1. Every claim below was checked against the source before it was allowed to move a
decision. A subagent report is a candidate list, not a finding.

## REFUTED

### "Vault has no web support, so credentials cannot ship to browser builds"

Reported by the Vault/SQL explore, sourced to
`magic/lib/src/security/magic_vault_service.dart:24-29` plus the assertion that
"flutter_secure_storage v10.0.0 does not provide a web implementation".

**Check**: `grep 'flutter_secure_storage_' /Users/anilcan/Code/fluttersdk/magic/pubspec.lock`

**Verdict**: refuted. Five platform implementations resolve, and
`flutter_secure_storage_web` is among them at `pubspec.lock:334`, beside `_darwin` (310),
`_linux` (318), `_platform_interface` (326) and `_windows` (342). Web is supported.

**What survives**: the web implementation is not a keychain. It encrypts into IndexedDB with a
WebCrypto key that same-origin JavaScript can reach, so the *security property* is weaker than on
Darwin or Android even though the API works. That is a real distinction for a credential store and
it belongs in the interview as a decision, not as a blocker. The reported version of this claim
would have cut web out of onboarding entirely on a false premise.

## CONFIRMED

### An absolute URL bypasses the driver's `base_url`

`magic/lib/src/network/drivers/dio_network_driver.dart:181-196` reads:

```dart
Future<MagicResponse> get(String url, {Map<String, dynamic>? query, Map<String, String>? headers}) async {
  final response = await _dio.get(url, queryParameters: query, options: Options(headers: headers));
```

The URL goes straight to Dio, which treats an `http://` or `https://` prefix as absolute. So a
per-user panel host needs **no** runtime driver registration and **no** deviation from
`CLAUDE.md`'s `Http` facade mandate. This was the single biggest open risk going in.

### The HTTP test seam is first-party and complete

`magic/lib/src/facades/http.dart:138` `static FakeNetworkDriver fake([dynamic stubs])`, with
`stubs` accepting null (all 200 empty), a `Map<String, MagicResponse>` of URL pattern to response,
or a `FakeRequestHandler` callback. Plus `Http.response([data, statusCode])` at `:144` as a stub
builder and `Http.unfake()` at `:159`. `FakeNetworkDriver` records requests and prevents stray
ones. No plan step needs to build a mock layer.

### `DB.statement` binds parameters

`magic/lib/src/facades/db.dart:105`:

```dart
static void statement(String sql, [List<Object?> params = const []]) {
  _db.connection.execute(sql, params);
}
```

Synchronous, returns void, takes bound params. Provider data is untrusted input reaching SQL, so
binding rather than interpolation is mandatory and available.

### All three of `CLAUDE.md`'s ORM claims

Verified by the explore against current sibling source and spot-checked here: no `index()` on
`Blueprint` (`blueprint.dart:152-248` lists the column methods and it is absent), no `whereIn` /
`like` / `join` on the query builder, and `insertAll` is a `for` loop over `insert`
(`query_builder.dart:302-306`). Each `insert` costs an `INSERT` plus a
`SELECT last_insert_rowid()`, so two statements per row: 76,000 for 38,247 VOD titles.

## CONFIRMED, and it is a blocking ecosystem defect

### magic's Http driver lowercases every header on the wire, including `User-Agent`

The librarian established that `dart:io` lowercases header names unless
`preserveHeaderCase: true` is passed (added in Dart 2.16,
`dart-lang/sdk#39657`), and that `package:http`'s `IOClient` sets it
unconditionally. It could not carry that to magic, because magic wraps **Dio**, not
`package:http`. So I checked the chain myself:

| Link | Evidence |
|---|---|
| Dio's flag defaults to false | `dio-5.11.1/lib/src/headers.dart:11` and `:17`, `lib/src/options.dart:152`, all `preserveHeaderCase = false` |
| Dio's IO adapter forwards it | `dio-5.11.1/lib/src/adapters/io_adapter.dart:109`, `preserveHeaderCase: options.preserveHeaderCase` |
| magic never sets it | `grep preserveHeaderCase magic/lib/src/network/drivers/dio_network_driver.dart` → no match |

So a request through the `Http` facade ships `user-agent`, not `User-Agent`.

**Why this blocks rather than annoys.** `CLAUDE.md`'s Provider requests section: "Normalise the
header key to exactly `User-Agent`: ExoPlayer's lookup is case sensitive and a lowercase key
silently ships `User-Agent: ExoPlayer` instead." The requirement is exact-case, the failure is
silent, and it lands on Android.

**It cannot be fixed at the call site.** magic's facade accepts only
`Map<String, String>? headers` (`facades/http.dart:80-112`) and never exposes Dio `Options`, so
there is no per-request route to the flag. This needs a change in magic: either
`preserveHeaderCase: true` on the driver's `BaseOptions`, or plumbing it through the facade.

Per `.claude/rules/workflow.md` that is a separate sibling PR with its own CI, and per
`CLAUDE.md`'s ecosystem rule it is our backlog rather than something to route around. It is a
**defect** in the three-way split (behaviour contradicting a documented consumer requirement)
rather than a gap or an improvement.

## UNSUPPORTED, carried into the interview

### "Dio follows redirects by default, up to 5, with no interception point in magic"

The explore found no `followRedirects` / `maxRedirects` / `validateStatus` anywhere in
`dio_network_driver.dart`, which is a sound negative about **magic**. The "up to 5" and the
header-resend behaviour across a cross-origin redirect are Dio and `dart:io` defaults that the
report asserted without a citation. The Dart HTTP librarian brief covers exactly this, so it is
left open here rather than assumed.
