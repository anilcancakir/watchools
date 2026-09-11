# The stream URL contract, and the plugin's real control surface (ac:explore x2)

Two briefs merged here because a URL builder and the thing that consumes it are one decision.
Everything below the first heading comes from `tool/xtream-mock/`, which IS the executable wire
contract with 77 verification checks, rather than from documentation.

## Stream routes

| Kind | Path shape | Accepts | Answers |
|---|---|---|---|
| Live HLS | `/live/<user>/<pass>/<id>.m3u8` | `.m3u8` per channel | 302, then an HLS playlist |
| Live progressive | `/live/<user>/<pass>/<id>.ts` | `.ts` per channel | 302, then MPEG-TS |
| Movie | `/movie/<user>/<pass>/<id>.<ext>` | `.mp4`, `.mkv`, `.avi` per item | 302, then file bytes with ranges |
| Series | `/series/<user>/<pass>/<id>.<ext>` | per item | 302, then file bytes |
| Catch-up, path | `/timeshift/<user>/<pass>/<duration>/<start>/<id>.ts` | `.ts`, archive channels only | 200 |
| Catch-up, query | `/streaming/timeshift.php?username=&password=&stream=&start=&duration=` | same | 200 |
| Tokenised play | `/(live\|movie\|series)/play/<token>/<file>` | token-gated | segments, playlist or bytes |

`server.mjs:1098-1127` for the redirect, `:897` and `:904` for the kind parameter.

**The segment is `movie`, not `vod`.** `server.mjs:897` documents the parameter as
"`live`, `movie` or `series`" and `:904` branches on `kind === 'movie'`. A `/vod/` path 404s. This
was reported wrongly once during research and is logged in `verification-log.md`; no path in this
plan comes from anybody's recollection.

## The redirect

```
HTTP/1.1 302
Content-Type: text/html; charset=UTF-8
Location: http://{host}/(live|movie|series)/play/{token}/{file}
Access-Control-Allow-Origin: *
Connection: close

(empty body)
```

- **Token** (`server.mjs:86-90`): `base64url(username:password:expiry_unix_seconds)`. Opaque,
  **not signed**, carrying the credentials and an expiry. TTL 300 s, and 15 s for the `expiring`
  account. Read back at `:100-124`; an undecodable token is treated as expired.
- **No `Cache-Control`, deliberately** (`:1119-1123`): "FFmpeg caches redirects keyed on `Expires`
  and `Cache-Control`, and a `no-store` here would force every entry to be skipped, making the
  fixture immune to stale-redirect reuse for a reason the panel does not share."
- Sniffing the first response sees **HTML**, not a playlist.

## Output format

- The handshake's `allowed_output_formats` is `['m3u8', 'ts']` (`server.mjs:174`).
- Live channels carry a per-codec `formats` array (`catalogue.mjs:195-284`). Most serve both;
  **channel 07 (AV1) serves `.m3u8` only** and a `.ts` request 404s with a reason naming the real
  formats (`server.mjs:926-935`): "AV1 has no MPEG-TS mapping".
- VOD entries carry `container_extension`: `.mp4`, `.mkv`, `.avi`.

So an extension cannot be chosen from the account alone: the account says what the panel allows,
and the channel says what this channel actually has. Asking for the wrong one is a 404, not a
fallback.

## Catch-up

Two of the five wild conventions, both the `xc` spelling:

1. `/timeshift/<user>/<pass>/<duration_minutes>/<start>/<id>.ts`
2. `/streaming/timeshift.php?username=&password=&stream=&start=&duration=`

Duration is **always minutes** in both. Both echo what they parsed back as `X-Timeshift-Duration`
and `X-Timeshift-Start`. A channel with `tv_archive: 0` answers **404** naming the channel
(`:878-884`), with no fallback to the live edge. **Not implemented**: `default`, `append`, `shift`,
`flussonic` (README:270). And the mock's timeshift is **not really time-shifted**: it serves the
live loop and merely echoes `start` (`:889`).

## Ranges

`sendFile()` at `server.mjs:632-681`.

| Request | Status | Notable header |
|---|---|---|
| Unranged | 200 | `Accept-Ranges: 0-<total>`, `Cache-Control: no-store` |
| `bytes=N-M`, `bytes=-N`, `bytes=N-` | 206 | `Content-Range: bytes N-M/<total>` |
| Unsatisfiable or malformed | 416 | `Content-Range: bytes */<total>` |

**`Accept-Ranges` is non-standard on purpose**: `0-<total>` rather than `bytes` (`:622-626`),
because "FFmpeg's prefix match fails on it and falls back to `Content-Range`, which is what really
happens in the wild, and a hand-rolled Dart check of the shape
`headers['accept-ranges'] == 'bytes'` is exactly the code somebody writes."

## Failure shapes

| Condition | Status | Body |
|---|---|---|
| Blocked user, account or stream | 200 | `blocked` |
| Lapsed subscription | 200 | `Expired` |
| Rejected credentials, stream | 200 | `No User Found` |
| Banned / disabled / custom | 200 | the status string |
| Unknown credentials, API | 200 | `{"auth": 0}` |
| **Expired stream token** | **509** | empty, `text/html`, `Connection: close` |
| Unreadable token | 404 | `Not a stream token` |
| No archive on the channel | 404 | `No archive for channel {id}` |
| Format the channel cannot serve | 404 | explanation naming the real formats |
| Hanging provider | no response at all | - |

Two things worth stating plainly. **A stream refusal is HTTP 200 with a plain-text body, never a
status code**; `server.mjs:826` records that a 403 "was this mock's own first answer and was
backwards". And **token expiry is a 509**, which `reconnect_on_http_error=[4xx,5xx]` matches, so
FFmpeg retries a dead token until its retry cap.

## The plugin's control surface, which is nearly empty

Method channel, all five:

| Method | Args | Returns |
|---|---|---|
| `play` | `viewId`, `url`, `userAgent?` | nil or FlutterError |
| `state` | - | `{running, videoOutput, width, height, cacheSeconds?}` |
| `stop` | - | nil |
| `dispose` | `viewId` | nil |
| `captureSelf` | `path`, `viewId?` | motion dict, **spike affordance** |

Events: `tick` (500 ms, on a dedicated serial queue, `MpvEngine.swift:343`), `endFile`,
`videoReconfig`, `log`, `eventsLost`.

**Nothing implements seek, pause, resume, volume, speed, track selection, duration or a live-edge
offset.** Verified independently: `mpv_command` appears once in all four Swift files
(`MpvEngine.swift:157`, only `loadfile`), `"pause"` appears once and only in the tick's read loop
(`:363`), and `seek` appears zero times. So `PlayerTick.paused` reports a state nothing can set.

**One core at a time.** `WatchoolsPlayerPlugin.swift:144` holds a single `MpvEngine`;
`MpvEngine.swift:84-85` refuses a second `start()` while a core is alive. Views are weak-referenced
by id and `dispose(viewId)` tears the core down only if that view was the attached one.

This is not only a plugin limitation: `player-layer.md:206-216` measured the account's connection
budget at **1**, and a second concurrent variant killed the first at 5.79 s. So a single core is
aligned with what the provider permits, and two simultaneous streams were never available.

## mpv options the plugin already sets

`cache: yes`, `cache-secs: 180`, `cache-pause: no`, `cache-pause-initial: no`, `cache-pause-wait: 0`,
`demuxer-max-bytes: 800MiB`, `demuxer-max-back-bytes: 200MiB`, `network-timeout: 10`,
`stream-lavf-o: reconnect=1,reconnect_streamed=1,reconnect_on_http_error=[4xx,5xx],reconnect_max_retries=3`,
`ytdl: no`, `user-agent` from the caller, `msg-level: all=warn`, plus `vo: gpu-next`,
`gpu-api: vulkan`, `gpu-context: moltenvk`, `hwdec: videotoolbox` and `wid`.

**None of them can be changed after start**, which matters for the ladder later: a buffer retune
per variant would need either a native setter or a core restart.
