# Xtream protocol against real clients (ac:librarian)

Sourced from five independent implementations: `tellytv/go.xtream-codes` (Go),
`Dispatcharr` (Django backend ingesting real multi-thousand catalogues), `iptvnator`
(TypeScript, production Electron app), `PyIPTV` (Python), `tvarr` (Go), plus `m3u-editor`'s
Xtream-**compatible server** as the other side of the wire.

## 1. There is no pagination. Settled.

`category_id` is the only narrowing parameter on `get_live_streams` / `get_vod_streams`. No
offset, no limit, no page, on any of the five clients or the compatible server.

- `tellytv/go.xtream-codes` `xtream-codes.go:172-202` — `GetStreams` takes an optional
  `category_id` and nothing else.
- `Dispatcharr` `core/xtream_codes.py:248-260` — `get_all_live_streams`, comment reads
  `# No category_id = get all streams`.
- `m3u-editor` `XtreamApiController.php:123-138` — the server's own docblock documents
  `category_id` as the only filter for either action.

So a panel returns the whole catalogue in one JSON array: **2,976 rows for live and 38,247 for
VOD in a single response.** The one-call fetch strategy is correct, and the cost lands on decode
and insert rather than on request count.

## 2. EPG: three calls with three different jobs

- `get_short_epg` — cheap now/next, per channel, and **`limit` is genuinely honoured**
  (`iptvnator` sends 10, `tellytv` and `PyIPTV` default to 4).
- `get_simple_data_table` — one channel's **full** schedule, unlimited. Heavier sibling, not a
  whole-station guide.
- `xmltv.php` — the whole multi-channel guide as XML. Real clients treat it as a **bulk import or
  cache source, not a per-request lookup**: `iptvnator`'s `resolveCurrentEpg`
  (`xtream-xmltv-fallback.service.ts:115-131`) prefers a locally cached XMLTV file and only calls
  `get_short_epg` live when the local guide is empty.

That is the strategy to copy: import XMLTV once, serve now/next from the cache, fall back to
`get_short_epg` per channel on a miss.

## 3. Four unreliabilities beyond the type drift the mock already reproduces

| Field | Reality |
|---|---|
| EPG `title` / `description` | Base64 is **not universal**. `iptvnator`'s `decodeBase64Unicode` (`xtream-api.service.ts:397-414`) silently falls back to the raw string on decode failure, because panels disagree. Our mock always encodes, so it cannot produce the other half. |
| `exp_date` | `0`, negative, missing **or unparsable** all mean "no expiry", a valid state on trial and reseller panels rather than a malformed response. `tvarr` `xtream_account.go:56-58`. Our mock models only `null`. |
| `tv_archive_duration` | Unit is convention, not contract. `m3u-editor` documents days, and `0` on panels that have catch-up but no known retention, so a client needs its own default. |
| `category_id` | Absent entirely on series rows on some panels. `tellytv` `structs.go:74` models it as a nullable pointer. |

## 4. The fault disjunction is confirmed, independently, twice

`iptvnator`'s `docs/architecture/xtream-portal-compatibility.md:61-84` states our exact
disjunction, and `tvarr`'s `Authorised()` / `Expired()` (`xtream_account.go:56-67`) implements it
independently in Go. **No fourth dead arm exists.**

Two refinements it does add:

- Match `status` **case-insensitively**, and treat a truthy `auth` as active only when the status
  text is absent.
- `active_cons >= max_connections` is a real state but **orthogonal to death**: the subscription is
  alive and fully booked. `tvarr` models it separately as `AtConnectionLimit()`. That maps onto
  `ProviderFault.throttled` rather than needing a new member, and it is derivable from the
  handshake we already parse.

## 5. Actions beyond the common set

- **`get_simple_date_table`** — a genuine typo ("date", not "data") that some real panels
  implement *instead of* the documented spelling. `iptvnator` carries both
  (`xtream-code-actions.ts:1-12`). A client that only sends the correct spelling gets nothing from
  those panels.
- **`get_account_info`** and **`get_profile`** — alternate spellings of the handshake. `iptvnator`
  probes `get_account_info`, then no action, then `get_profile`, because **some panels do not
  answer a bare request at all**.
- `portal.php?type=itv/vod/series` is Stalker/Ministra middleware, a different protocol. Not an
  Xtream extension; out of scope.

## Sourcing note from the agent, worth keeping

The `worldofiptvcom` community documentation claims to derive from a decompiled `player_api.php`
with line numbers, but it is reverse engineering rather than a spec or a client's own source, so
it was weighted below the five implementations and used only where they corroborated it. TiviMate
and OTT-Navigator have no public source and their behaviour writeups added nothing the OSS clients
did not already establish.
