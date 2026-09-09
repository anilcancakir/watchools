# Reuse candidates (ac:explore)

Verdict: **magic already carries nearly the whole infrastructure stack.** The delta is the Xtream
parsers, a retry interceptor, and the mapping into the app's value types.

All paths are in the sibling checkout `/Users/anilcan/Code/fluttersdk/magic`.

## HTTP with a runtime base URL

| Candidate | What it gives |
|---|---|
| `lib/src/facades/http.dart:23` | `Http` facade delegating to a pluggable `NetworkDriver`. The driver takes `baseUrl` **at construction**, not only from static config. |
| `lib/src/network/drivers/dio_network_driver.dart:14` | Dio driver, `baseUrl` + timeout + headers via constructor. This is the per-user panel host mechanism. |
| `lib/src/network/network_service_provider.dart:8` | Registers the `network` driver singleton from config; `boot()` can add interceptors. Shows how to swap or extend at runtime. |

Note: magic wraps Dio. `CLAUDE.md`'s anti-pattern is reaching for `dio` **directly**, which this does not.

## Retry and backoff

- `lib/src/network/contracts/magic_network_interceptor.dart:23` — `onError` receives the failed
  request/response and may return a `MagicResponse` to retry. The seam for exponential backoff
  exists; the interceptor itself does not.

## JSON decode with drifting types

- `lib/src/http/magic_paginator.dart:117` — takes `E Function(Map<String, dynamic>)` as `fromMap`
  and delegates all coercion to the caller. So type drift is ours to handle, per field.
- `lib/src/database/eloquent/model.dart:14` — the ORM's `casts` map (datetime, json, bool, int,
  double) is the existing pattern for hydrating from raw JSON.

## Secrets

- `lib/src/facades/vault.dart:8` — `Vault.put/get/delete/flush`, platform-agnostic API. Tests swap
  in a `FakeVaultService`.

## Bulk write and raw SQL

- `lib/src/facades/db.dart:183` — `DB.transaction(callback)`, BEGIN/COMMIT/ROLLBACK, rolls back on
  exception. The wrapper for a 2,976-row and a 38,247-row insert.
- `lib/src/facades/db.dart:105` — `DB.statement(sql, params)`. **Takes bound params**, which
  matters because provider data is untrusted input reaching SQL.

## Pagination

- `lib/src/http/magic_paginator.dart:111` — `MagicPaginator<E>`, cursor and offset modes,
  auto-detects from the response envelope, custom fetchers via `MagicPageFetcher`.

## Client / controller shape to imitate

- `lib/src/http/magic_controller.dart:30` — `MagicController extends ChangeNotifier` with
  `onInit` / `onClose`, `refreshUI()`, `authorize()`.
- `lib/src/http/magic_controller.dart:140` — `MagicStateMixin` with loading / success / error /
  empty tracking and `setState` helpers. The app's two controllers do **not** currently use it.

## Test doubles, and this is the find that matters most

- `lib/src/network/drivers/fake_network_driver.dart:28` — `FakeNetworkDriver` records requests,
  stubs by URL pattern or callback, and **prevents stray requests**.
- `lib/src/facades/http.dart:138` — `Http.fake([stubs])` swaps the driver singleton,
  `Http.unfake()` restores.

So the HTTP test seam is first-party and already exists. No plan step needs to build one.

## Reported gaps

No candidate found for: an Xtream-specific parser, a retry interceptor implementation (only the
contract), or a mapping from wire JSON to `Channel` / `TitleItem`. Those are the real delta.
