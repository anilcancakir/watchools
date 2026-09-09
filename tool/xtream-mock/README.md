# Mock Xtream panel

A local Xtream Codes panel to develop the client against. It speaks
`player_api.php`, `get.php`, `xmltv.php`, the three stream URL shapes and two
spellings of the `xc` catch-up convention, and every channel it serves is a
different codec pair.

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
`get_series` answers `[]`. One of the four captured real panels answers exactly
that, so the empty case is real, but the other three return populated series
lists: this is a stub with a citation attached rather than a modelled state.

## Accounts

| Credentials | What the panel does |
|---|---|
| `demo:demo` | Works. Every channel plays. |
| `expired:expired` | `auth: 1`, `status: "Expired"`, `exp_date` in the future. |
| `lapsed:lapsed` | `auth: 1`, `status: "Active"`, `exp_date` in the past. |
| `lifetime:lifetime` | `auth: 1`, `status: "Active"`, `exp_date: null`. |
| `banned:banned` | `auth: 1`, `status: "Banned"`. |
| `disabled:disabled` | `auth: 1`, `status: "Disabled"`. |
| `throttled:throttled` | HTTP 200 carrying the bare word `blocked`. Not JSON. |
| `hang:hang` | Accepts the connection and never answers. |
| anything else | HTTP 200 with `{"auth": 0}` and no other key. Never a 401. |

`expired`, `lapsed` and `lifetime` are three expiry states that no single field
read handles. Checking only `status` passes `lapsed` as active. Checking only
`exp_date` passes `expired` as active, and calls `lifetime` expired because
`Number(null)` is 0. So the test is a disjunction of `auth != 1`,
`status != "Active"` and a non-null `exp_date` in the past.

Being straight about how well that is grounded: `lifetime` is proven by capture
(`testData/eternal/auth.json` carries `"exp_date": null`). `expired` and `lapsed`
are not. One real XC fork derives `status` from `exp_date` on the fly
(`if (is_null($exp_date) || time() < $exp_date) "Active" else "Expired"`), and on
that fork neither state can occur: an Active account cannot have a past date and
an Expired one cannot have a future date. Other panels store `status` as a
column, where they can. Treat the disjunction as correct defensive code and
these two accounts as the states it defends against, not as proof they are
common.

`throttled` shows the panel's generic denial shape: HTTP 200 with a body that is
not JSON. There is no status code and no JSON field for throttling, so it can
only be inferred from a parse failure, and that same shape is what a blocked
address, a blocked user agent, an HTML error page and an expired stream request
all produce. It cannot on its own tell throttled from blocked from expired.
`hang` is the half of unreachable a dead port cannot produce, and a dead port
produces the other half, so there is no account for it.

A non-active account still lists its whole catalogue and only fails at the
stream, which is the state where the app looks healthy and nothing plays. The
refusal is **HTTP 200 with a short plain-text body**, not a status code: this
mock answered 403 at first and that was backwards. A real XC stream handler
answers `die('Expired')` and `die("No User Found")` under 200, and
`stack-decisions.md:264` records the same, that a client should expect 200 and
"only occasionally a real 401". So the client cannot tell a refusal from a
stream by status code and has to look at the first bytes.

## Where the wire shapes came from

No official specification survives; Xtream Codes was raided in 2019.

The handshake, the category lists, the live list and the VOD list are grounded in
real captured panel responses in
[`tellytv/go.xtream-codes`](https://github.com/tellytv/go.xtream-codes)
`testData/` (four panels, MIT). That corpus holds seven files per panel and does
**not** include `get_vod_info`, `get_short_epg` or `get_simple_data_table`, and
all four of its `auth.json` are `auth: 1, status: "Active"`, so it grounds no
failure mode either. Those shapes came from client implementations and from a
published XC fork's `player_api.php` instead, which is a weaker source and is
worth knowing before changing a field on its authority.

The types drift and the mock reproduces the drift rather than tidying it, since
tidying it would let a client pass here and break on a provider:

- `auth` is a bare integer while `max_connections`, `active_cons`, `is_trial`
  and `exp_date` are quoted strings.
- In one and the same object `category_id` is a string and `parent_id` and
  `tv_archive` are integers.
- `epg_channel_id` is nullable, and channel 06 is null on purpose. Both EPG
  surfaces agree about it: `get_short_epg` returns no listings and `xmltv.php`
  omits the channel.
- `exp_date` is nullable, meaning lifetime, on the `lifetime` account.

What the corpus proves and this does **not** reproduce, all worth adding later:
`stream_type` is `radio_streams` on 23 per cent of one panel's entries and
`created_live` on another's; 63 to 88 per cent of real channels have a null
`epg_channel_id` against 1 of 8 here; `stream_icon` is empty far more often than
not; `direct_source` sometimes carries a URL the panel wants played instead of
the derived one; and `tv_archive_duration`, `category_id` and `custom_sid` drift
type or go null inside a single response.

Two asymmetries worth knowing, both reproduced here. EPG titles and
descriptions are base64 in the JSON actions and plain text in `xmltv.php`. And
XMLTV offsets are emitted in the correct spaced form (`+0300`), while real
panels also emit the spaceless form that a parser silently reads as UTC; the
mock does not currently offer that variant.

## Catch-up, two spellings of one convention

```
/timeshift/<user>/<pass>/<duration>/<start>/<id>.ts
/streaming/timeshift.php?username=&password=&stream=&start=&duration=
```

These are the two spellings of the `xc` convention. `stack-decisions.md:270`
counts five in total (`default`, `append`, `shift`, `flussonic`, `xc`) and the
other three are not here.

Duration is minutes in every Xtream convention. The content is not really time
shifted, and the `start` is echoed rather than validated: each form reports what
it parsed into `X-Timeshift-Duration` and `X-Timeshift-Start`, so a client's URL
derivation is readable but a start in the wrong timezone or format still gets a
200. A channel whose `tv_archive` is 0 answers 404 rather than serving the live
edge, so at least that derivation fails loudly.

## How live works

HLS playlists are synthesised per request over four pre-encoded segments: the
media sequence advances with the wall clock, there is no `ENDLIST`, and a
`DISCONTINUITY` is emitted where the window wraps, because the loop really does
reset the timeline. `EXT-X-DISCONTINUITY-SEQUENCE` goes with it, since RFC 8216
section 6.2.1 derives a segment's discontinuity number from that tag plus the
tags above it, and without the tag one segment carried a different number
between two reloads.

Segment durations are read from the playlist FFmpeg wrote rather than declared
flat. Forced keyframes land a 4.120 s final segment on channels 04 and 05, so a
hardcoded `4.000` under-declared 120 ms per loop, about 27 s an hour, on two of
eight channels. That reads as a codec-specific player bug, which is the most
expensive kind of false lead.

The progressive `.ts` endpoint spawns `ffmpeg -re -stream_loop -1 -c copy`
rather than re-sending the file, since concatenating the same MPEG-TS bytes
repeats their timestamps and a player then stalls or jumps. Verified continuous
across the loop boundary: a 22 s read of a 16 s source probes as one 22 s
stream. This makes ffmpeg a runtime dependency and not only a build one.
