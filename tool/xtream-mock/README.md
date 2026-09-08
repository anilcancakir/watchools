# Mock Xtream panel

A local Xtream Codes panel to develop the client against. It speaks
`player_api.php`, `get.php`, `xmltv.php`, the three stream URL shapes and both
catch-up conventions, and every channel it serves is a different codec pair.

```sh
node tool/xtream-mock/encode.mjs      # once, ~4 s, needs ffmpeg
node tool/xtream-mock/server.mjs      # http://127.0.0.1:3300
```

Open that URL for the account and channel list. `PORT` and `HOST` override the
defaults; it binds to loopback because it authenticates nothing, so
`HOST=0.0.0.0` is the deliberate step for pointing a phone or a TV box at it.

Media is generated from a `testsrc2` pattern and a sine tone, so nothing here is
provider content and nothing is fetched at runtime. `media/` is gitignored: it
is 48 MB and regenerating it is one command.

## The codec matrix

Live entries in this protocol carry no codec field, so each channel states its
own in its name. That is also how real providers do it, with `FHD` and `HEVC`
in the channel title.

| id | Channel | Video | Audio | Serves |
|---|---|---|---|---|
| 10001 | 01 H.264 AAC \| HLS/TS | H.264 | AAC | `.m3u8` (TS segments), `.ts` |
| 10002 | 02 H.264 AAC \| RAW TS | H.264 | AAC | `.m3u8`, `.ts` |
| 10003 | 03 H.264 AC-3 \| HLS/TS | H.264 | AC-3 | `.m3u8`, `.ts` |
| 10004 | 04 H.265 AAC \| HLS/fMP4 | H.265 | AAC | `.m3u8` (fMP4 segments), `.ts` |
| 10005 | 05 H.265 E-AC-3 \| HLS/TS | H.265 | E-AC-3 | `.m3u8`, `.ts` |
| 10006 | 06 MPEG-2 MP2 \| RAW TS | MPEG-2 | MP2 | `.m3u8`, `.ts` |
| 10007 | 07 AV1 Opus \| HLS/fMP4 | AV1 | Opus | `.m3u8` only |
| 10008 | 08 H.264 MP3 \| HLS/TS | H.264 | MP3 | `.m3u8`, `.ts` |

Channel 07 answers 404 with the reason on a `.ts` request, because AV1 has no
MPEG-TS mapping. That is a container fact rather than a gap in the mock, and
saying it beats an empty body the client reads as its own decode failure.

Categories group by container, not by genre, so the category strip separates
the three cases that fail differently: HLS with MPEG-TS segments, HLS with fMP4
segments, and progressive MPEG-TS.

Three VOD titles (20001 to 20003) exist for `container_extension` and for
`get_vod_info`, which is where this protocol really carries codec metadata.
`get_series` answers `[]`, which is not a stub: one of the four captured real
panels answers exactly that.

## Accounts

| Credentials | What the panel does |
|---|---|
| `demo:demo` | Works. Every channel plays. |
| `expired:expired` | `auth: 1`, `status: "Expired"`, `exp_date` in the future. |
| `lapsed:lapsed` | `auth: 1`, `status: "Active"`, `exp_date` in the past. |
| `banned:banned` | `auth: 1`, `status: "Banned"`. |
| `disabled:disabled` | `auth: 1`, `status: "Disabled"`. |
| `throttled:throttled` | HTTP 200 carrying the bare word `blocked`. Not JSON. |
| `hang:hang` | Accepts the connection and never answers. |
| anything else | HTTP 200 with `auth: 0`. Never a 401. |

`expired` and `lapsed` are both a dead subscription and they are the reason the
client cannot read one field. A client checking only `status` passes `lapsed`
as active; a client checking only `exp_date` passes `expired` as active. The
test has to be a disjunction of `auth != 1`, `status != "Active"` and a past
`exp_date`.

`throttled` is what throttling looks like on the wire: there is no status code
and no JSON field for it, so it can only be inferred from a body that failed to
parse. `hang` is the half of unreachable that a dead port cannot produce, and a
dead port produces the other half, so there is no account for it.

A non-active account still lists its whole catalogue and only fails at the
stream, with HTTP 403. That is what a real panel does, and it is the state
where the app looks healthy and nothing plays.

## Where the wire shapes came from

Every field, and its type, was taken from real captured panel responses in
[`tellytv/go.xtream-codes`](https://github.com/tellytv/go.xtream-codes)
`testData/` (four panels, MIT) rather than from prose about the protocol. No
official specification survives; Xtream Codes was raided in 2019.

The types drift and the mock reproduces the drift rather than tidying it, since
tidying it would let a client pass here and break on a provider:

- `auth` is a bare integer while `max_connections`, `active_cons`, `is_trial`
  and `exp_date` are quoted strings.
- In one and the same object `category_id` is a string and `parent_id` and
  `tv_archive` are integers.
- `epg_channel_id` is nullable, and channel 06 is null on purpose.
- `exp_date` is nullable on a real lifetime account, confirmed by capture.

Two asymmetries worth knowing, both reproduced here. EPG titles and
descriptions are base64 in the JSON actions and plain text in `xmltv.php`. And
XMLTV offsets are emitted in the correct spaced form (`+0300`), while real
panels also emit the spaceless form that a parser silently reads as UTC; the
mock does not currently offer that variant.

## Both catch-up conventions

```
/timeshift/<user>/<pass>/<duration>/<start>/<id>.ts
/streaming/timeshift.php?username=&password=&stream=&start=&duration=
```

Duration is minutes in every Xtream convention. The content is not really time
shifted, but each form echoes what it parsed into `X-Timeshift-Duration` and
`X-Timeshift-Start`, which is what makes a client's URL derivation assertable
rather than only observably playing something. A channel whose `tv_archive` is
0 answers 404 rather than serving the live edge, so a wrong derivation fails
loudly.

## How live works

HLS playlists are synthesised per request over four pre-encoded segments: the
media sequence advances with the wall clock, there is no `ENDLIST`, and a
`DISCONTINUITY` is emitted where the window wraps, because the loop really does
reset the timeline.

The progressive `.ts` endpoint spawns `ffmpeg -re -stream_loop -1 -c copy`
rather than re-sending the file, since concatenating the same MPEG-TS bytes
repeats their timestamps and a player then stalls or jumps. Verified continuous
across the loop boundary: a 22 s read of a 16 s source probes as one 22 s
stream. This makes ffmpeg a runtime dependency and not only a build one.
