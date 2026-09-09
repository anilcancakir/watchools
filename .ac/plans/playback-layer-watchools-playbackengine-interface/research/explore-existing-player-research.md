# What the existing research already settled (ac:explore)

Mined from `.ac/research/player-layer.md` (708 lines) and `.ac/research/stack-decisions.md` (412).
Where the two disagree, `player-layer.md` wins: `stack-decisions.md:19-24` marks its own section 1
superseded. Every measured number carries a 2026-09-09 date and was taken against the real
subscription (one account, 2,976 channels, 38,247 titles) on the macOS 26.5 SDK.

## Locked decisions

- **Fork nothing. libmpv primary on every target.** AVFoundation is a narrow second engine chosen
  by capability, never by guessing a codec from a URL (`player-layer.md:14-20`).
- **Apple TV needs no second native engine.** MPVKit 1.0.0's `Libmpv.xcframework` carries real
  `tvos-arm64_arm64e` and `tvos-arm64_x86_64-simulator` slices with `client.h`, `render.h`,
  `render_gl.h` and `stream_cb.h` at API 2.5 (`:78-95`). This **corrects** `stack-decisions.md`.
- **MPVKit ships static archives, not dynamic frameworks** (`:112-121`). Either build dynamic
  frameworks or prepare the relinkable-object route, and decide before the first store submission.
- **Connection budget is 1 on this account** (`:206-216`). Warm failover with a pre-warmed second
  `mpv_handle` is ruled out on this provider; sequential failover is never refused.

## The interface members the research argues for

- `player-layer.md:382`: **buffer, live offset, position, telemetry and fault as members rather
  than an options bag.** This is the sentence the plugin's own doc attributes.
- `:69-75`: **the contract must verify a video track after ready, not trust the ready signal.**
  Measured: an HEVC channel on the real provider reports `readyToPlay`, advances position, plays
  audio and **has no video track**, with no status code or error object carrying it. AVFoundation
  sees one video track on the RAW variant and none on the HEVC one.
- `:193-202`: **log messages are a fault channel.** Subscribe with
  `mpv_request_log_messages("warn")` and forward them, because FFmpeg renders a 509 as
  `End of file`, the same silent shape as `reason=0`.
- `:515-527`: **a Track type**, `{id, kind, lang, codec, title, isDefault, isForced, isExternal}`,
  plus `select(kind, id?)` and a `preferredLanguages` list **reapplied after every `loadfile`**.

## The three frozen clocks, measured, and why two of them are indistinguishable

`player-layer.md:588-621`. This is the most load-bearing table in the corpus for a health model:

| Scenario | `time-pos` | `underrun` | `demuxerIdle` | `fw-bytes` | Recovers |
|---|---|---|---|---|---|
| Display idle or screensaver | frozen | false | - | grows to cap | on wake |
| Live window starvation | frozen | **true** | false | 0 | ~8 s |
| Lapsed token | frozen | **true** | false | 0 | **never** |

**Starvation and a lapsed token present identically.** They differ only in whether they recover, so
no instantaneous reading can separate them and only elapsed time can. That is the measured
justification for the 12 s grace, and it means the interface cannot promise to distinguish them
synchronously.

## The variant ladder, deferred but not to be designed out

- Reads **one node**, `demuxer-cache-state` as `MPV_FORMAT_NODE` (`:557-578`). Not
  `demuxer-cache-duration`, which freezes rather than falls on a lapsed token. Not `cache-speed`
  beside `raw-input-rate`; they are the same value read twice.
- Predicate: `time-pos` not advancing while `pause` is false, with the node's `underrun` and `idle`
  saying why (`:568-578`).
- Three tiers (`:623-645`). Tier 0 reads `end-file` reason in {0, 4}, immediate switch. **Tier 1
  (3 s `time-pos` threshold) and tier 2 (10 s mean `raw-input-rate` below bitrate) are both marked
  UNVERIFIED**, because the harness had no playback clock.
- Guard: exclude `MPV_END_FILE_REASON_REDIRECT` (5) explicitly; it fires on playlist expansion and
  playback continues (`:632-637`).
- **Deleted tier**: `paused-for-cache` is gone, because the design sets `--cache-pause: no` so the
  property can never fire (`:626-645`).
- Four guards (`:647-653`): a variant stable for 30 s earns one same-variant retry; a 60 s cooldown
  before wrapping; a cap of about 10 switches per session; a longer grace before the first byte
  than after.
- **Channel names lie about quality** (`:687-702`). Measured on TRT 1's three variants: all three
  are 1080p, including the one called "4K". A preference key must come from a probed stream or a
  fixed codec preference, never from name extraction. This **invalidates** an earlier plan to
  extract quality from the name.

## Measured numbers

- `max_connections` 1, `allowed_output_formats` `["m3u8","ts"]`, 2,976 live channels, 38,247 VOD
  titles (`:25-26`).
- Container distribution (`:46-54`): **mp4 54.0%** (20,653), **mkv 45.6%** (17,444), avi 0.4% (137),
  everything else 0.0% (13). The 45.6% mkv share is why AVFoundation cannot be primary.
- Token lapse under four reconnect configurations (`:165-168`): mpv defaults 23.7 s;
  `reconnect_streamed=1` alone still alive at 75 s with the demuxer reading 7.0 s;
  `reconnect_on_http_error=[4xx,5xx]` alive at 75 s reading 3.0 s; both plus
  `reconnect_max_retries=3` 29.6 s. **Only the retry cap restores bounded failure.**
- Real-sized cache during a lapse (`:184-191`): mpv fetched three segments, then took 509 twelve
  times, while `demuxer-cache-duration` **froze at 15.68 s** rather than falling.
- Connection eviction (`:218-228`): variant A alone ran its full 14 s window; A plus B opening at
  t=4 s **died at 5.79 s**; B alone ran its full 8 s window.
- Buffer tuning, three configs against the HEVC variant, 45 s each (`:445-448`): mpv defaults zap
  3040 ms, buffer mean 20.2 s, read 1452 KB/s; media_kit shape zap 1690 ms, buffer 11.0 s, read
  582 KB/s; clubTivi's fast tier zap 1658 ms, buffer 18.1 s, read 1266 KB/s. **Zap time nearly
  halves on buffer settings alone.**
- Standalone Swift render proof (`:304-318`): 1920x1080, 50 fps, zero dropped frames. The
  `moltenvk` context is correct. `estimated-display-fps` is unavailable without display-sync.
- **Resize debt** (`:344-358`): resizing the layer mid-playback leaves mpv on the old swapchain;
  `drawableSize` becomes 1920x1080 while `dwidth`/`dheight` stay 640x360.

## Stream URL and catch-up

- The API host answers **302 to a different host** with a base64 token path, so every header,
  User-Agent and DNS decision applies to the redirect target rather than the panel (`:27-28`).
- Stay on `--user-agent`, `--http-header-fields` and `--stream-lavf-o` for the provider HTTP path;
  **do not** use `stream_cb` for it (`:145`).
- `--stream-lavf-o` is a key/value list and a comma must be **bracketed**:
  `reconnect_on_http_error=[4xx,5xx]`, never escaped with a backslash (`:147-154`).
- **No reconnect option survives a lapsed token**, and recovery therefore **belongs to the app
  layer**, via `demuxer-cache-state` plus a fresh `loadfile` (`:156-180`). So the answer to "who
  re-resolves a lapsed token" is already settled: not FFmpeg, not the engine's internals.
- Subtitles arrive in **five shapes** (`:503-527`): empty, an array of URLs, an array of keyed
  objects (`url|file|src|link|path`), a language-keyed map, or ffprobe stream descriptors for
  tracks muxed into the file. Sidecars attach with `--sub-files-append` and
  `--audio-files-append`. `dvb_teletext` is missing from the decoder set and needs
  `--enable-libzvbi`.
- **Catch-up resolution** (`stack-decisions.md:279-281`): an explicit `catchup-source` wins;
  otherwise derive by declared mode; otherwise, for Xtream with `tv_archive=1`, derive the `xc`
  form; otherwise no catch-up. The Xtream form puts duration in **minutes** and makes `/live/`
  optional. The timeshift endpoint interprets the start time in **server local time**, and the
  clock offset comes from `server_info.timestamp_now` minus device time.

That last line matters beyond catch-up: it is the same offset the protocol layer's
`Programme.fromXtream` currently ignores, and the research already specifies where it comes from.

## Corrections and retractions on record

Do not resurrect any of these:

- Apple TV does **not** need native TVVLCKit or AetherEngine (`:77-95`).
- `AVURLAssetHTTPUserAgentKey` **is** public as of iOS 16 / tvOS 16; the earlier "private key only"
  claim is outdated (`:97-110`).
- The LGPL relinking claim holds for the binaries **media_kit** consumes, not for MPVKit's static
  archives, which is the base watchools chose (`:112-121`).
- The `paused-for-cache` ladder tier is deleted (`:626-645`).
- Quality-from-channel-name is invalidated (`:687-702`).
- `stack-decisions.md` section 1 is superseded entirely on the engine split (`:19-24`).

## What the research says is still unverified

Tiers 1 and 2 of the ladder (`:626`, `:627`), real-panel window starvation behaviour (`:610`), and
whether a real panel starves the same way the mock does. All three are marked "no" in the Verified
column of their own tables.
