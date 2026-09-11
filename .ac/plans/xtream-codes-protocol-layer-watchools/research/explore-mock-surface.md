# The mock panel's wire contract (ac:explore)

The executable contract the parser is written against. Paths into
`tool/xtream-mock/server.mjs` unless stated.

## Routes

- `/player_api.php` (`:901`), `/get.php` (`:922-927`), `/xmltv.php`. All three authenticate on
  `username` + `password` query parameters.
- Actions (`:257-275`): `get_live_categories`, `get_vod_categories`, `get_series_categories`,
  `get_series`, `get_live_streams`, `get_vod_streams`, `get_vod_info`, `get_short_epg`,
  `get_simple_data_table`. **No action = the handshake** (`user_info` + `server_info`).
- Unknown action returns `[]` (`:250`), not an error.
- `get.php` takes `type` (`m3u_plus` for attributes, else plain) and `output` (`ts` | `m3u8`).
- Streams: `/<kind>/<user>/<pass>/<file>` where kind is `live` | `movie` | `series` (`:1017-1018`).
- Catch-up, two spellings of `xc` only: `/timeshift/<user>/<pass>/<duration>/<start>/<id>.ts`
  (`:1076-1077`) and `/streaming/timeshift.php?...` (`:1083-1091`). Five conventions exist in the
  wild (`README.md:189-191`); the other three are absent.

## Type drift, which is the whole point of the fixture

**Handshake `user_info`:** `auth` is a **bare integer** while `is_trial`, `active_cons`,
`created_at` and `max_connections` are all **quoted strings**. `exp_date` is a **quoted string or
null** (null = lifetime). `allowed_output_formats` is an array of strings.

**Rejected credentials:** `{ auth: 0 }` and **nothing else** (`:142-143`). A model with a
non-nullable `status` or `exp_date` breaks here, which is why the fixture refuses to pad it.

**Categories:** `category_id` is a **string** (`:259`, `String(c.id)`) beside `parent_id` as a
**bare integer**, in the same object.

**`get_live_streams` entry:** `category_id` **string** beside `tv_archive` **integer** in the same
object (`:212`). `epg_channel_id` is **string or null** (`:210`). `num`, `stream_id`,
`tv_archive_duration` bare integers; `added` a quoted epoch.

**`get_vod_streams` entry:** `rating` a **quoted string** beside `rating_5based` a **bare number**.
`container_extension` decides the movie URL: `mp4` | `mkv` | `avi`.

**`get_vod_info`:** `{ info: {...}, movie_data: {...} }`. Inside `info`, `duration_secs` is a bare
number and `duration` a `HH:MM:SS` string; `audio.sample_rate` is a **quoted string** while
`audio.channels` is a bare number.

**EPG (`get_short_epg`, `get_simple_data_table`):** `title` and `description` are **base64** in the
JSON API (`:356`, `:360`) and **plain text** in `xmltv.php`. `start_timestamp` and
`stop_timestamp` are **quoted** epochs; `start` and `end` are `YYYY-MM-DD HH:MM:SS` panel-local
strings. `get_simple_data_table` adds `now_playing` and `has_archive` as bare 0/1 (`:332-333`).

## Failure, which never uses a status code

| Credentials | Signal | Status |
|---|---|---|
| `demo:demo` | works | 200 |
| `expired:expired` | `auth 1`, `status "Expired"`, **future** `exp_date` | 200 |
| `lapsed:lapsed` | `auth 1`, `status "Active"`, **past** `exp_date` | 200 |
| `lifetime:lifetime` | `auth 1`, `status "Active"`, `exp_date: null` | 200 |
| `expiring:expiring` | works, then the stream token lapses after 15 s | 200 then **509** |
| `banned` / `disabled` | `auth 1` with that `status` | 200 |
| `throttled:throttled` | HTTP 200 carrying the plain word `blocked`, not JSON | 200 |
| `hang:hang` | accepts the connection and never answers | none |
| anything else | `{auth: 0}`, single key | 200 |

Stream refusal (`:760-784`) is **HTTP 200 with a plain-text body**: `blocked`, `Expired`,
`No User Found`, or the status word. `get.php` and `xmltv.php` refuse with **200 and an empty
body** (`:915-921`).

**Token lapse is HTTP 509**, empty body, `Connection: close`,
`Content-Type: text/html` (`:989-998`). Indistinguishable from any other 5xx.
Unreadable token: 404 `Not a stream token` (`:968-970`).

## Redirect mechanics

1. `GET /live/user/pass/10001.m3u8` → **302** with
   `Location: /live/play/<TOKEN>/10001.m3u8`, `Content-Type: text/html`,
   `Connection: close`, `Access-Control-Allow-Origin: *` (`:1017-1047`). Sniffing the first
   response sees **HTML**, not a playlist.
2. **No `Cache-Control` on the redirect, deliberately** (`:1038-1042`): FFmpeg caches by `Expires`
   plus `Cache-Control`, so `no-store` would skip every entry and make it immune to stale reuse
   in a way a real panel is not.
3. Token: `base64url(username:password:expiry)` (`:86-91`), 300 s TTL, **15 s** for the `expiring`
   account. Not signed. Read once per stream (`:109-124`, `:965`).
4. Ranges: unranged → 200 with the panel's non-standard `Accept-Ranges: 0-<total>` (`:574`);
   ranged → 206 with `Content-Range` (`:600-607`); unsatisfiable → 416 (`:583-585`); tail
   `bytes=-N` supported (`:591`) for an MP4 `moov` read.

## What the mock deliberately does NOT reproduce

From `README.md`, and these are the gaps the client must not be developed against:

- Only two of five catch-up conventions (`:189-191`).
- `lapsed` and `expired` are **defensive code against unverified states**, not proven by capture
  (`:99-123`). Only `lifetime`'s null `exp_date` is proven by a real capture.
- Real panels drift far more (`:168-174`): `stream_type` sometimes `radio_streams` (23% on one
  panel) or `created_live`; **63 to 88% of real channels have a null `epg_channel_id`** against 1
  of 8 here; `stream_icon` empty far more often; `direct_source` populated more often;
  `tv_archive_duration`, `category_id` and `custom_sid` drift type or go null.
- XMLTV offsets emitted spaced (`+0300`) only; real panels also emit the spaceless form that some
  parsers read as UTC (`:179-180`).
- `catalogue.mjs:13-16` — the captured corpus does **not** cover `get_vod_info`, `get_short_epg`,
  `get_simple_data_table` or any failure mode. Those shapes came from client implementations and a
  published fork, which is weaker sourcing.
- `get_series` returns `[]`, matching one real panel (`catalogue.mjs:48-50`).
- Known defect (`README.md:52-92`): the four HLS channels cannot play past the first loop wrap;
  the RAW TS channels are clean. Fixed for timestamps in PR #22 but the last wrap remains.

## Gaps the librarian found that this mock cannot currently produce

Cross-referencing `librarian-xtream-reality.md`: the mock always base64-encodes EPG text, always
sends `null` rather than `0` for a lifetime `exp_date`, only implements the correctly spelled
`get_simple_data_table`, and always answers a bare handshake. Real panels vary on all four. Those
are mock work, and they are what makes the corresponding client hedges testable.
