# The player layer

What to build, what to reuse, and the measurements that decided it. Read this
before writing a line of playback code. Section 1 of
`.ac/research/stack-decisions.md` predates it and is corrected in three places,
noted inline.

Every number here was measured on 2026-09-09 against Anılcan's own provider
subscription and a macOS 26.5 SDK, or read out of a pinned source file. Where a
claim is second-hand it says so.

## The decision, in one paragraph

Fork nothing. There is no package here whose code we want. There is a binary we
want (MPVKit's xcframeworks), a header set we want (four files, 46 plus 11
symbols, one function added in five years) and a build tool we want
(`flutter-tvos plugin port`). We write a thin `PlaybackEngine` in Dart, a thin
native host per platform, and generate the FFI bindings. **libmpv is the primary
engine on every target.** AVFoundation is a narrow second engine selected by
capability, never by guessing a codec from a URL.

## Why libmpv is primary, measured on the real provider

The account: `max_connections` **1**, `allowed_output_formats` `["m3u8","ts"]`,
2,976 live channels, 38,247 VOD titles. The panel is a load balancer: the API
host answers `302` to a different host with a base64 token path, so the real
stream is on another origin and every header, User-Agent and DNS decision has to
apply to the redirect target rather than to the host the user typed.

**Live.** The provider carries TRT 1 in three variants, which is a controlled
experiment we did not have to construct:

| Variant | What it really is | AVFoundation |
|---|---|---|
| `TRT 1 RAW` | H.264 Main 1080p + HE-AAC, TS segments in HLS | `tracks=2 [vide,soun]` |
| `↺TRT 1 HEVC` | HEVC Main 1080p + AAC LC, TS segments in HLS | `tracks=1 [soun]`, **no video** |

Same provider, same delivery, same container. The only variable is the video
codec. Both report `readyToPlay`, both advance the play position, neither raises
an error. The HEVC one simply has no video track. Apple's HLS authoring rules
have always wanted HEVC in fMP4, so this is expected behaviour rather than a
defect, which is why waiting for a fix is not a plan. The provider's HEVC
category is 23 channels; nothing tells us the other 2,953 are not also HEVC,
because the codec is not in the catalogue.

**VOD.** Container distribution across all 38,247 titles:

| Container | Titles | Share |
|---|---|---|
| mp4 | 20,653 | 54.0% |
| **mkv** | **17,444** | **45.6%** |
| avi | 137 | 0.4% |
| ts, mpg, flv, m4v | 13 | 0.0% |

AVFoundation cannot open mkv or avi at all: `AVURLAsset.load(.isPlayable)`
throws "Cannot Open" on both, measured locally against generated files. So
**46% of the catalogue is unopenable** on an AVPlayer path. A sampled real mkv
holds ordinary H.264 Main plus MP2 audio, so the blocker is the container and
not the codec, and a stream-copy remux would fix it in principle. It does not
fix it in practice: the sampled film is 3.44 GB.

**Progressive raw MPEG-TS** fails on AVFoundation with
`AVFoundationErrorDomain -11850`, measured first-hand against our own mock
panel, which is the same code `stack-decisions.md:23` cites from Apple's forums.

## The fourth fault class

`ProviderFault` has three members and this is not one of them: a stream that
reports `readyToPlay`, advances its position, plays audio, and has no video
track. No status code and no error object carries it.

**The engine contract must therefore verify a video track after ready, not trust
the ready signal.** Every engine needs the same check, because the same silent
shape is reachable on Media3 when a decoder rejects a format the container
advertises.

## Correction: Apple TV does not need a second native engine

`stack-decisions.md:212` says media_kit's Darwin builds target iOS, simulator
and macOS only with no tvOS planned, and that the fix is native work wrapping
TVVLCKit or AetherEngine. The first half is true of media_kit. The conclusion is
wrong, because media_kit is not the only way to reach libmpv.

MPVKit 1.0.0 (2026-07-25) builds `libmpv v0.41.0` and `FFmpeg n8.1.2`. Its
`Libmpv.xcframework`, downloaded and inspected, carries:

```
macos-arm64_x86_64   ios-arm64   ios-arm64_x86_64-simulator
tvos-arm64_arm64e    tvos-arm64_x86_64-simulator
ios-arm64_x86_64-maccatalyst   xros-arm64   xros-arm64-simulator
```

The tvOS slice ships `client.h`, `render.h`, `render_gl.h` and `stream_cb.h` at
`MPV_CLIENT_API_VERSION 2.5`, the same as every other slice. One engine reaches
all five targets.

## Correction: the User-Agent has a supported key now

`stack-decisions.md:93-117` records that the only working header mechanism on
iOS is the private `AVURLAssetHTTPHeaderFieldsKey`, with Apple staff saying not
to use it. That is still true for arbitrary headers, and the private key is
absent from the SDK headers entirely. But for the User-Agent specifically, which
is the thing this product actually needs:

- `AVURLAssetHTTPUserAgentKey`, `AVAsset.h:609`, `API_AVAILABLE(macos(13.0),
  ios(16.0), tvos(16.0))`
- `AVURLAssetOverrideMIMETypeKey`, `AVAsset.h:553`, `macos(14.0) ios(17.0)
  tvos(17.0)`, which forces AVFoundation to ignore both the path extension and
  the server's `Content-Type`. That is the fix for a panel that mislabels a
  playable stream, and this protocol mislabels constantly.

## Correction: the LGPL reasoning does not hold for this base

`stack-decisions.md:73` says libmpv ships as dynamic frameworks and therefore
satisfies the LGPL relinking clause the ordinary way. That is true of the
binaries media_kit consumes. It is **not** true of MPVKit's: `file` reports
`current ar archive` on the macOS, iOS and tvOS slices alike. Static archives.

So adopting MPVKit means either building dynamic frameworks ourselves or
preparing the relinkable-object route. This is a decision to make before the
first store submission, not after.

## No loopback proxy

Earlier research concluded that a local HTTP proxy is the only mechanism that
answers custom headers and DNS together, and recorded the landmine that Dart's
`HttpClient.connectionFactory` skips the TLS branch (`http_impl.dart`), so a
factory returning a plain socket sends cleartext to port 443.

`stream_cb.h` removes the whole problem. `mpv_stream_cb_add_ro` registers a
protocol whose bytes we serve in-process, with our own read and seek callbacks.

**But do not use it for the provider HTTP path**, because neither reason for it
survives. The per-provider User-Agent has a supported option: mpv's
`--user-agent` maps to FFmpeg's `user_agent` and `--http-header-fields` to
`headers`, both per `mpv_handle`, and we run one handle per playback. And DNS is
already out of scope by this project's own doctrine (`CLAUDE.md`: "Custom DNS is
an onboarding problem, not a feature"). Taking the byte source over would mean
owning TLS, the redirect chain, the redirect cache, the reconnect ladder,
`Range` and seek, and `stream_cb.h` warns you cannot even cancel a stream from
the callbacks: libmpv keeps using it until it gives up.

So the provider path stays on `--user-agent`, `--http-header-fields` and
`--stream-lavf-o`. Reserve `stream_cb` for something that genuinely needs byte
control, a local disk cache or a recording tap.

**`--stream-lavf-o` is a key/value list, and its comma has to be bracketed.**
mpv's `read_subparam` accepts `"..."`, `[...]` and `%n%`, and has no backslash
escape, so `reconnect_on_http_error=4xx\,5xx` splits at the comma: read back as
a node map it is `reconnect_on_http_error` = `4xx\` plus a garbage key
`5xx,reconnect_max_retries` = `3`. A string readback cannot see this, because
mpv's own `print_keyvalue_list` joins pairs with a bare comma and no quoting, so
a mis-split value prints back identical to the input. Write
`reconnect_on_http_error=[4xx,5xx]`.

**And no reconnect option survives a lapsed token.** mpv leaves
`reconnect_on_http_error` empty so FFmpeg refuses to reconnect on any 4xx or
5xx, which reads like a missing setting, but adding it does not buy playback.
Measured one variable at a time against the mock's lapsing token with a starved
cache (`cache-secs=2`, `demuxer-readahead-secs=1`, `demuxer-max-bytes=8MiB`) and
a 75 s deadline:

| Arm | Outcome |
|---|---|
| mpv defaults only | ended after 23.7 s, `reason=0` |
| `reconnect_streamed=1` alone | alive at 75 s, demuxer read 7.0 s of content |
| `reconnect_on_http_error=[4xx,5xx]` alone | alive at 75 s, demuxer read 3.0 s of content |
| both plus `reconnect_max_retries=3` | ended after 29.6 s, `reason=0` |

The two surviving arms are the bad outcome. They retry a dead token
indefinitely: the core stays up, the video output still reports `gpu-next` and a
picture, and three to seven seconds of content arrive in seventy five. Nothing
raises a fault, so the client cannot tell a stall from a slow channel.

`reconnect_max_retries=3` therefore goes in **to restore a bounded failure**.
There is nothing to reconnect to at that layer: mpv keeps the post-redirect URL
as the playlist URL and refreshes that rather than the panel URL, so the token
cannot be renewed by FFmpeg at all. Recovery belongs to us, and it is the same
mechanism the variant ladder needs anyway: detect the stall from
`demuxer-cache-state`, re-resolve through `player_api.php`, `loadfile`.

**With a real-sized cache the stall is not bounded, and only the log stream
names it.** Re-run inside the Flutter plugin with the shipped option set rather
than the starved one, 75 s against the lapsing account: mpv fetched three
segments, then re-requested only the playlist and took a 509 twelve times
without ever asking for another segment. No `END_FILE`. `current-vo` stayed
`gpu-next` with a decoded size, and `demuxer-cache-duration` **froze at 15.68 s**
rather than falling, so the property that looks like the obvious stall detector
reports health for as long as the stall lasts. What did arrive, at `warn`, was
FFmpeg's own reconnect trace with its backoff (`http: Will reconnect at 0 in 1
second(s), error=End of file`) and then an `error` line when it gave up.

Three consequences for the interface:

- The ladder reads one `demuxer-cache-state` node plus `time-pos` and `pause`,
  never `demuxer-cache-duration`. See "The ladder" for why `fw-bytes` is the
  wrong predicate, why `cache-speed` is not a second reading, and why the
  thresholds are still unverified: the harness that produced them had no
  playback clock, so a healthy stream froze in it too.
- Log messages are a **fault channel**, not diagnostics. Subscribe with
  `mpv_request_log_messages("warn")` and forward them; `terminal=yes` writes the
  same lines to a stdout no release build reads.
- FFmpeg renders a 509 as `End of file`, which is the same silent shape as
  `reason=0`. Every HTTP status this provider uses to refuse arrives as EOF.

## Connection budget, and what it kills

`max_connections` is **1** on this account. The panel also serves VOD and live
from the same budget on at least one real backend, so the two compete.

- Parallel segment fetching was already out: ExoPlayer declined it
  (`google/ExoPlayer#565`, "we have no plans to support parallel loading") and
  Shaka declined preconnect (`shaka-player#2081`, will-not-implement).
- **A pre-warmed second `mpv_handle` on the predicted next channel is also out**,
  which reverses the obvious answer to "make zapping fast". Zap speed has to
  come from buffer tuning and connection reuse alone.

### How the cap is enforced, measured with a control

This was asserted before it was measured, so it is written down properly now.
Two `.ts` requests on different variants of the same channel, then the same
variant alone:

| Run | Result |
|---|---|
| variant A alone, 14 s window | HTTP 200, ran the **full 14.0 s** |
| variant A with variant B opening at t=4 s | HTTP 200, died at **5.79 s** |
| variant B, opened while A ran | HTTP 200, ran its **full 8 s window** |

**The panel evicts the older stream rather than refusing the newer one.** Three
consequences, and they are the whole shape of the failover design:

1. **Warm failover is impossible on this account**, now by measurement rather
   than by assumption. Opening the warm handle kills the stream it was meant to
   protect. This is what `clubTivi` does with a second muted player, and it
   needs a provider that allows two connections.
2. **Sequential failover is never refused.** The worry that the panel would hold
   the slot and reject our own reopen is disproven: a new stream opened while
   the old one was still live. The retry ladder will not burn itself against a
   closed door.
3. **A fourth fault class, and for a one-connection account it is the most
   likely interruption there is.** When anyone else uses these credentials, our
   stream dies mid-playback and the panel says nothing: the connection simply
   ends. At the player layer that is indistinguishable from a network drop, so
   it needs its own message ("another device is using your subscription") rather
   than a generic retry, and the retry itself would evict that other device in
   turn.
- Chunked parallel download is out for the same reason, even though the panel
  would allow it: it answers `206 Partial Content` with
  `Content-Range: bytes 1000000-1008191/3693628462`, so Range, seek and resume
  all work. The server permits what the account forbids.

Gate every concurrency decision on `max_connections - active_cons` read from the
handshake, and treat 1 as the common case rather than the edge case.

## Buffer, as a first-class member

mpv exposes the whole surface directly, which is the main reason to own the FFI
layer rather than inherit someone's Dart. `video_player_platform_interface`
offers `backBufferDurationMs` and nothing else; media_kit collapses mpv's two
directions into one `bufferSize` and defaults it to 32 MiB against mpv's own
150 MiB forward and 50 MiB back, so a media_kit app is more cache-starved than
stock mpv. media_kit also sets `network-timeout: 5` where mpv's default is 60.

Starting values worth arguing from, all read from source rather than invented:

| Source | Values |
|---|---|
| mpv defaults | `demuxer-max-bytes` 150 MiB, `demuxer-max-back-bytes` 50 MiB, `stream-buffer-size` 128 KiB, `cache-pause` yes, `cache-pause-wait` 1 s, `network-timeout` 60 s |
| Media3 `DefaultLoadControl` (≥1.6.0) | min/max buffer 50,000 ms, for-playback 1,000 ms, after-rebuffer 2,000 ms; connect and read timeouts 8,000 ms. Below 1.6.0 the last two are 2,500 and 5,000, which costs 1.5 to 3 s a zap |
| `clubTivi`, the closest comparable Flutter client | `cache-secs 180`, `demuxer-max-bytes 800M`, readahead tiers 60/120/180 s, and `cache-pause=no` on every tier so a starved buffer keeps playing rather than freezing |
| Kodi `inputstream.adaptive` retry | 6 attempts live, 3 VOD, flat 1,000 and 500 ms sleeps, no backoff, abort playback on exhaustion |

Two things Kodi tried and abandoned, worth not repeating: duration-based
adaptive buffer sizing, disabled in production because it caused OOM on 4K
(`inputstream.adaptive` commit `61f4fa5`), and the `ASSUREDBUFFERDURATION`
settings, still declared and never read.

## What the catalogue actually looks like

Measured over the 2,976 live entries, and every line of it is a difference from
`tool/xtream-mock`:

| Field | Reality | Our mock |
|---|---|---|
| `epg_channel_id` | empty on **91%** | null on 1 of 8 |
| `custom_sid` | `null` on **100%** | `''` |
| `category_ids` | a list, channels can be in several | absent |
| `is_adult` | present | absent |
| `tv_archive` | set on 20 of 2,976 | 2 of 8 |
| `stream_icon` | real tmdb.org URLs | local SVG |
| `stream_type` | all `live` here, `radio_streams` on other panels | all `live` |
| `rating_5based` | a string on VOD, int-or-float in the capture corpus | double |

Two traps the mock should grow: 30 unplayable separator rows the provider
inserts as visual group headers (`✦●✦ HEVC ✦●✦`), and one entry typed
`stream_type: live` whose `direct_source` is an `.mkv` on a different host, so a
"channel" that is really a file in a container AVFoundation cannot open.

## Step 2 is done, and it corrected its own instructions

Measured on an M1 Pro, macOS 26.5, MPVKit 1.0.0 through SPM, in a standalone
Swift executable with no Flutter, playing `tool/xtream-mock`'s H.264 channel and
then the real provider's HEVC one.

**libmpv renders into a caller-provided `CAMetalLayer`.** `wid` accepted,
`current-vo: gpu-next`, and `screenshot-raw` returns a 1280x720 `bgr0` frame
(640x360 at `contentsScale` 2.0, so the Retina scaling is right) with 100%
non-black coverage, 18.9% of pixels differing between two frames 0.6 s apart,
and the `testsrc2` timecode legible and the right way up. The compositor agrees
independently: `CGWindowListCreateImage` of the same window twice shows tens of
thousands of changed bytes with video and, in a control run with nothing loaded,
**zero**.

On the real provider's HEVC channel, the one AVFoundation reduces to audio:
1920x1080 decoded, 50 fps, zero dropped frames, and mpv followed the panel's
302 to the other host by itself.

Three corrections the run forced:

- **The context is `moltenvk`, not `macvk`, on every Apple target.** Upstream
  mpv reads `WinID` in exactly four files (`android_common.c`,
  `vo_mediacodec_embed.c`, `w32_common.c`, `x11_common.c`) and no macOS file
  among them, and `--wid`'s own documentation covers X11, win32 and Android and
  never mentions macOS. `wid` works here only because MPVKit carries
  `0001-player-add-moltenvk-context.patch`, whose context does
  `p->layer = (__bridge CAMetalLayer *)(intptr_t)ctx->vo->opts->WinID;` and
  registers ahead of upstream's `ra_ctx_vulkan_mac`.
- **Only the image encoders are missing.** MPVKit's FFmpeg is
  `--disable-encoders` plus an allowlist covering `aac`, `alac`, `flac`, `pcm*`,
  `h264_videotoolbox`, `hevc_videotoolbox` and `prores`, and the muxers include
  `matroska`, `mp4`, `mov`, `mpegts` and `webm`. So `screenshot-to-file` fails
  ("Could not open libavcodec encoder for saving images") while
  `--stream-record` works and `screenshot-raw` gives thumbnails through
  `CGImageDestination` with no FFmpeg encoder at all.
- **`estimated-display-fps` is a display-sync property, not a health signal.**
  It is `M_PROPERTY_UNAVAILABLE` unless a frame was display-synced, and
  `--video-sync=audio` is the default, so it reads unavailable on a stock
  desktop mpv too. Do not treat 0 as a fault. The related gap is real though:
  the patched context answers every VOCTRL with `VO_NOTIMPL`, so there is no
  nominal display fps either, and `--video-sync=display-resample` would need
  `--display-fps-override` fed from `NSScreen.maximumFramesPerSecond`.

**The one real debt, measured.** Resizing the layer mid-playback from 640x360 to
960x540 leaves mpv on the old swapchain: `drawableSize` becomes 1920x1080 while
`dwidth`/`dheight` stay 640x360, `osd-dimensions` stays 1280x720, and
`screenshot-raw` still returns 1280x720. Because `moltenvk_control` returns
`VO_NOTIMPL`, no `VO_EVENT_RESIZE` ever reaches `vo_gpu_next`, and only
`moltenvk_reconfig` reads `drawableSize`, on a video reconfig rather than a
layout change. Forcing a reconfig from the client API (`vf toggle null`) does
not pick it up either. In Flutter this bites constantly, because the platform
view's frame is set on every present.

The fix is a small patch we author and carry: have `moltenvk_control` handle
`VOCTRL_CHECK_EVENTS` by comparing `layer.drawableSize` against the swapchain,
call `ra_vk_ctx_resize`, and return `VO_EVENT_RESIZE`. We are already vendoring
a patched build, so this is a named dependency rather than a surprise, and it is
worth offering upstream to MPVKit.

## The plan

1. **One hour, before any Dart.** Point libmpv at the provider's five worst
   shapes: an extensionless live endpoint, a `.ts` live endpoint, an `.m3u8`
   master carrying `#EXT-X-MEDIA:TYPE=SUBTITLES`, an `.mkv` VOD and an `.avi`
   VOD, each with a player User-Agent. The HEVC live case is already done and
   passed.
2. ~~The smallest macOS plugin~~ **Done, see above.** What remains of it is the
   Flutter half: the same `CAMetalLayer` inside an `AppKitView` rather than a
   plain `NSWindow`. The engine hands a factory a real `NSView` and forces only
   `wantsLayer`
   (`FlutterPlatformViewController.mm`: "Flutter compositing requires
   CALayer-backed platform views"), composites it through Core Animation, and
   `video_player_avfoundation`'s 25-line `FVPNativeVideoView.m` is first-party
   precedent for an externally drawn layer. Set `contentsScale` and
   `drawableSize` in `layout` and `viewDidChangeBackingProperties`, because
   Flutter sets the view's frame on every present and never sets the scale.
   Keep every control in Flutter above the view: mouse events reach the view but
   Flutter's gesture arena does not hand gestures over on macOS.
3. **One day, the highest-information day.** The same on the tvOS simulator
   under `flutter-tvos`, same `moltenvk` context.
4. `ffigen` over the four headers, then `PlaybackEngine` with buffer, live
   offset, position, telemetry and fault as members rather than an options bag.
   Include `mpv_command_node` from the first cut, because `screenshot-raw`
   returns a node. Do not put `video_player_platform_interface` in the middle.
5. The byte source through `mpv_stream_cb_add_ro`: resolver, User-Agent,
   concurrency gated on the handshake's budget.
6. Measure zap from `loadfile` to the first `MPV_EVENT_VIDEO_RECONFIG` using
   `mpv_get_time_ns`, over ten channels, against the defaults. Do not build
   parallel fetching, and do not plan on a pre-warmed second handle.
7. Settle the LGPL question against the static-archive finding above. It arrives
   at first submission rather than after, because Flutter's generated Swift
   package is `libraryType: static`, so mpv's objects land inside Runner.

**Swift Package Manager needs no decision.** It is `enabledByDefault: true` on
stable, this project is already migrated (`FlutterGeneratedPluginSwiftPackage`
appears ten times in `macos/Runner.xcodeproj/project.pbxproj`) and there is no
`macos/Podfile` at all. Take MPVKit in the plugin's own `Package.swift` and add
no Podfile. One cost to know: MPVKit declares 38 binary targets and SPM fetches
them all, including the GPL variants, which is 1.7 GB of artifacts per machine.
Invisible to CI, which runs on `ubuntu-latest` and never builds macOS, and worth
replacing with our own `Package.swift` naming only the LGPL targets we link the
day a macOS build job exists.

## What the fallback is

If step 2 or 3 fails, `mpv_render_context` with
`MPV_RENDER_API_TYPE_OPENGL` is the route media_kit already takes, and we pay
its bridge cost on the platforms where `wid` did not work rather than
everywhere. Measured for scale: `media_kit_video`'s macOS render machinery is
about 1,000 lines of Swift across `OpenGLHelpers`, `TextureHW`, `VideoOutput`,
`TextureSW`, `SwappableObjectManager` and `Worker`, all of it in service of
feeding a Flutter `Texture`. The `wid` path replaces it with roughly the 25
lines of `FVPNativeVideoView.m`.

## Where AVFoundation still earns its place

Not as a codec path. As four capabilities libmpv cannot have:

- **AirPlay video.** media_kit's maintainer states it plainly in issues #207 and
  #721: not AVPlayer, so not AirPlay. A libmpv path degrades to screen
  mirroring.
- **System picture in picture.** `AVPictureInPictureController` takes an
  `AVPlayerLayer`, or an `AVSampleBufferDisplayLayer` plus delegate
  (`AVPictureInPictureController_AVSampleBufferDisplayLayerSupport.h:119`,
  `macos(12.0) ios(15.0) tvos(15.0)`). libmpv produces neither without a
  `CMSampleBuffer` bridge, which media_kit has attempted twice and not landed.
- **DRM**, which libmpv has no path to at all.
- **A mini player off one decoder.** One `AVPlayer` can back several
  `AVPlayerLayer`s. mpv allows one render context per core (`render.h:551`), but
  step 2 showed the `wid` path creates no `mpv_render_context` at all, so that
  limit does not bind here. What binds instead is one `CAMetalLayer` per mpv
  core: a second view onto the same stream still needs a second core, and
  therefore a second connection, which `max_connections=1` forbids on this
  account. A mini player showing the *same* stream has to reuse the one layer.

Select it by capability, never by sniffing an extension: the measurements above
are exactly the story of a URL that does not say what it contains.

## Buffer, bandwidth and stability, measured on the real channel

Three configs against the HEVC variant, 45 s each, strictly serial, `vo=null`
so this measures the pipe rather than the pixels:

| Config | Zap | Buffer mean / min | Read rate | Stalls | Drops |
|---|---|---|---|---|---|
| mpv defaults | 3040 ms | 20.2 s / 4.0 s | 1452 KB/s | 0 | 0 |
| media_kit's shape (32 MiB both ways, `network-timeout=5`) | 1690 ms | 11.0 s / 0.2 s | 582 KB/s | 0 | unreadable |
| clubTivi's fast tier | **1658 ms** | **18.1 s** / 0.2 s | 1266 KB/s | 0 | 0 |

Four things follow.

**Buffer policy alone moves zap from 3040 ms to 1658 ms**, a 45% cut with no
code. And clubTivi's tier holds both ends: the fast start *and* an 18 second
cushion, so there is no trade to make between them. Start from it.

**media_kit's shape is measurably worse**, reading at 582 KB/s against 1452 and
letting the cushion fall to 0.2 s. That is the concrete case for not inheriting
its Dart.

**Bandwidth is not the constraint.** The channel is about 3.5 Mbps and the
connection reads at roughly 11.6 Mbps, so there is 3.3x headroom. Buffer policy
is the lever; more sockets would collect nothing.

**135 seconds of playback across three configs, zero stalls, zero dropped
frames.** The stream is stable here, which means the failover work is for
provider faults and for eviction rather than for this connection.

### Why more sockets is the wrong answer

The request was to use the bandwidth "like reducing ping in games". The analogy
does not transfer, and the measurements say why. A game removes round trips from
the critical path; video with a buffer in front of it has no latency in its
critical path at all, only the question of whether the long-run read rate beats
the bitrate, and here it beats it by 3.3x with zero stalls.

Every mechanism is also absent. FFmpeg n8.1.2's `configure` has no `nghttp2`, no
`http2`, no `quic` and no `http3`, and `libavformat/http.c` writes `HTTP/1.1`
unconditionally, so a panel that speaks HTTP/2 gets HTTP/1.1 from libmpv anyway.
Multiplexing would add nothing regardless: it removes head-of-line blocking
between concurrent requests, and a sequential segment fetch has one outstanding.
`--stream-buffer-size` is documented as helping mp4 seek storms and cacheless
network filesystems, neither of which is live HLS. TCP window is auto-tuned by
the kernel and not exposed.

ExoPlayer's maintainer named the conditions where parallel fetching wins: a
large round trip time, short chunks, and throughput still good enough. The read
rate here is the proof the first is false.

Build the concurrency gate on `max_connections - active_cons` anyway, and put
exactly one thing behind it: a second `mpv_handle` for warm failover, which is
worth a great deal on a line that allows two connections and is impossible on
this one. Build no parallel chunk fetching.

## Tracks: what the provider actually sends

| Source | Tracks |
|---|---|
| `↺TRT 1 HEVC` live | 1 video (hevc), 1 audio (aac, `lang=-`), **0 subtitle** |
| A real `mkv` VOD | 1 video (h264), 1 audio (mp2, `lang=tur`), **0 subtitle** |

So the language tag arrives on VOD and not on live, and neither sample carries a
second audio track or any subtitles. Two samples of a Turkish film and a Turkish
channel prove nothing general, and one place has not been looked at:
`#EXT-X-MEDIA:TYPE=AUDIO` and `TYPE=SUBTITLES` in a master playlist, which is
the HLS-level shape rather than a second MPEG-TS PID.

On the Xtream side, subtitles hide in `get_vod_info` and `get_series_info` under
a field whose shape is up to the panel author. Five shapes exist in the wild:
empty, an array of URLs, an array of objects keyed `url|file|src|link|path`, a
language-keyed map, and **ffprobe stream descriptors** describing tracks already
muxed into the file rather than files to fetch. Filtering that last shape for a
URL and finding none is how a player reports "no subtitles" about a file with
two.

The engine exposes `Track {id, kind, lang, codec, title, isDefault, isForced,
isExternal}` plus `select(kind, id?)` and a `preferredLanguages` list reapplied
after every `loadfile`, which a variant switch needs anyway. External sources
are first-class: `--sub-files-append` and `--audio-files-append` attach a sidecar
with no reload, and `--secondary-sid` renders two subtitle tracks at once.

Our build's subtitle decoders, read off MPVKit's configure line: `ass`,
`ccaption`, `dvbsub`, `dvdsub`, `mpl2`, `movtext`, `pgssub`, `srt`, `ssa`,
`subrip`, `xsub`, `webvtt`, with libass for rendering. **`dvb_teletext` is
missing**: it needs `--enable-libzvbi`, which MPVKit does not pass. On a Turkish
provider carrying DVB-sourced feeds that is a real gap, and it is a build change
rather than a redesign since we already vendor a patched build.

## Variant failover

The provider carries one logical channel several times (`↺TRT 1 HEVC`,
`TRT 1 RAW`, `TRT 1 4K`, plus a QHD category), and they share **no identifier**:
`epg_channel_id` is empty on 91% and `custom_sid` is null on 100%. There is no
convention being missed; the market answer is normalisation plus a curated
identity list plus a user override, and it should be copied rather than improved
on.

Normalisation, in order: NFKC, then strip Unicode categories `So`, `No`, `Lm`
and `Sk` but deliberately not `Sm`, which handles `↺`, the `✦●✦` separator rows
and superscript `ᴿᴬᵂ` in one rule while keeping `+` so `Disney+` stays distinct.
Then drop a leading country-code prefix from a curated list only. Then
**extract** quality, codec, resolution and tier into a variant record rather
than discarding them, because they are the preference key. Do not strip bare
`East` / `West` / `Central` / `Atlantic`, or `Comedy Central` truncates. Match
the residue against `iptv-org/database`'s `channels.csv` `name` and `alt_names`;
on no match, group by exact residue **scoped to a category**, never globally,
because providers reuse names across categories.

One caution worth settling before grouping: iptv-org lists `TRT 4K` as
`TRT4K.tr`, a separate channel from `TRT1.tr`, not a feed of it. Whether the
provider's `TRT 1 4K` is a UHD re-encode of TRT 1 or the separate channel has to
be answered by opening it.

Model it as data rather than a rule: a channel row, an ordered variant join
carrying the extracted `{quality, codec, tier}`, and an override table that
survives a catalogue refresh.

### The ladder

Read **one** node, `demuxer-cache-state` as `MPV_FORMAT_NODE`. Not
`demuxer-cache-duration`, which mpv's own docs call "very unreliable, and often
the property will not be available at all", and which the lapsed-token
measurement showed **freezes** rather than falls. And not `cache-speed`
alongside it: `input.rst:2483` at v0.41.0 says "This is the same as
``demuxer-cache-state/raw-input-rate``", so the pair this section used to
prescribe was one read twice.

The candidate predicate is **`time-pos` not advancing while `pause` is false**,
with the node's `underrun` and `idle` saying why. Three reasons it beats
`fw-bytes`: the mini player needs `time-pos` anyway, so it costs no extra field;
it is what actually stopped in the measured lapse, since `cache-end` and
`reader-pts` both froze and their difference held at 15.68 s; and `fw-bytes`
**cannot** carry the signal, measured twice over. On a healthy continuous stream
it sits at a steady 80 KB rather than growing, so "not advancing" is its normal
state, and `demuxer-cache-idle` is "the demuxer cache is filled to the requested
amount, and is currently not reading more data" (`input.rst:2495`) while
`--demuxer-hysteresis-secs` makes the demuxer wait until "there is only 10
seconds of content left" before reading again (`options.rst:4290`).

### Three ways a frozen clock happens, and what tells them apart

All three measured. This is the table the detector is written against, because
two of the three rows are not faults and one of them is indistinguishable from
the fault by every field the tick carries.

| Shape | `time-pos` | `underrun` | `demuxerIdle` | `fw-bytes` | Recovers |
|---|---|---|---|---|---|
| Idle display or screensaver | frozen | **false** | **true** | grows to the cap | on wake |
| Live window starvation | frozen | true | false | 0 | yes, about 8 s |
| Lapsed provider token | frozen | true | false | 0 | **never** |

**The display case is distinguishable and must be excluded.** `gpu-next`
presents through the display link, so an idle display stops playback entirely:
`time-pos` froze at 0.08 across 106 ticks in the Flutter example and the
standalone harness reported `moving picture in the layer: no`, on both delivery
paths, with and without `hwdec`, until `caffeinate -u -d` was held and the same
channel reported 24.2% of pixels differing. `underrun` false with a full buffer
is the signature, and on a TV a screensaver reaches the same state, so this is a
product case rather than a testing nuisance.

**The other two rows are identical in every field, so duration is the only
discriminator.** A three segment live window means a healthy client drains
everything advertised and waits: measured at about eight seconds in every
twenty four against the mock, recovering cleanly with `time-pos` continuing from
where it stopped. A lapsed token presents the same way and never recovers. So
tier 1's threshold has to **exceed the longest legitimate starvation**, which
rules out the three seconds this table used to say, and the ladder needs the
recovery to cancel it rather than a single sample to trigger it.

Whether a real panel starves the same way is unmeasured; the mock's window size
is a fixture choice.

**Two things do survive as reliable**, because they are about the core rather
than the clock. `core-idle` reads `no` through an entire lapse and flips only
*after* `END_FILE`, so there is no event-driven fast path and the tick is the
detector. And `playlist_entry_id` is populated on `END_FILE`, so it works as the
session token that stops the ladder acting on the previous variant's event.

**Measure playback under `caffeinate`, or measure a stopped clock.** Two
harnesses produced a frozen `time-pos` for two different reasons on the same
day: one because `vo=null, ao=null` has no clock at all, the other because the
display had idled. Both read exactly like a provider fault.

| Tier | Signal | Threshold | Action | Verified |
|---|---|---|---|---|
| 0 | `end-file` reason in {EOF 0, ERROR 4}, or open failure | immediate | switch | yes |
| 1 | `time-pos` not advancing and not user-paused | 3 s | switch | no, harness had no clock |
| 2 | 10 s mean `raw-input-rate` below the stream bitrate | 10 s | switch | no |

Tier 0 includes **EOF**, which the first version of this table excluded by
triggering on `ERROR` alone: the measured token lapse ends as `reason=0` when it
ends at all, so an `ERROR`-only tier 0 misses the fault it exists for. Exclude
`MPV_END_FILE_REASON_REDIRECT` (5) explicitly, because `client.h:1489` sends it
for a playlist expansion and then "playback continues with the playlist
contents": a ladder that treats it as a fault steps on a healthy open. It does
not fire on the measured `.m3u8` because lavf is probed ahead of mpv's own
playlist demuxer, but an `#EXTM3U` body without `#EXT-X-` tags is expanded, and
that shape has not been opened yet.

A `paused-for-cache` tier is **deleted rather than reordered**. The property is
"whether playback is paused because of waiting for the cache"
(`input.rst:2598`), `--cache-pause` controls "whether the player should
automatically pause when the cache runs out of data" (`options.rst:5437`), and
`MpvEngine` ships `cache-pause: no`, so it can never become true. Dropping the
option to revive the tier is a product decision, not a tuning one: it changes
what the viewer sees from artefacts to a freeze and rebuffer.

Four guards: a variant that ran stably for 30 s earns one same-variant retry
before the ladder moves on, while one that stalled immediately does not; a
60 second cooldown before wrapping back to the top; a cap of about 10 switches
per session, reset after a stable period; and a longer grace before the first
byte than after, because opening is slower than running. Gate every tier on the
user not having paused, since `cache-speed` goes to zero on a pause and would
otherwise switch variants under a paused viewer.

What the user sees, given warm failover is impossible: the last frame holds,
because nothing clears the `CAMetalLayer`. So the seam is a freeze rather than
black, which reads as buffering rather than as broken. Put a Flutter overlay
over it naming the variant being tried, reapply the fast buffer profile for the
reopen, and order the ladder most-compatible-first rather than
highest-quality-first, which here means the H.264 variant ahead of the HEVC one.

**Grouping errors are worse than no grouping**: folding two genuinely different
channels sends a viewer to the wrong programme, which is more visible than a
freeze. Require an identity match or an exact in-category residue match for
automatic folding, never a similarity score alone, and let the user split a
group.

### The decisions, and one that overturned part of this plan

Settled with the owner on 2026-09-09:

- **Fold the variants into one channel** with a quality ladder, rather than
  trusting iptv-org's identity split. Measurement vindicates the call, and see
  below for why.
- **Variant order is a fixed user-editable list, with a bandwidth step-down.**
  Most compatible first, and drop a rung if the read rate falls under the stream
  bitrate. On this account the step-down never fires, and that is fine: it is
  there for a user who is actually constrained.
- **All three stall thresholds are user-exposed**, not just tier 2. Clamp them
  to sane floors in code rather than trusting the input, because a threshold set
  to a second produces a player that switches variants continuously.
- **The seam is the held frame plus an overlay naming the variant being tried.**
  Not black, not a spinner: nothing clears the `CAMetalLayer`, so the last frame
  stays, and a freeze with an explanation reads as waiting while a black screen
  reads as broken.

**The channel names lie about quality, and that invalidates a step above.** The
grouping plan says to extract quality from the name and use it as the preference
key. Probed:

| Variant | Video | Audio |
|---|---|---|
| `TRT 1 RAW` | h264 Main, 1920x1080 | HE-AAC stereo |
| `↺TRT 1 HEVC` | hevc Main, 1920x1080 | AAC LC **mono** |
| `TRT 1 4K` | hevc **Main 10**, 1920x1080, 50 fps | **mp2** stereo |

`TRT 1 4K` is 1080p. Every variant is 1080p. So the name's quality token is a
hint and never evidence: the preference key has to come from the probed stream,
or from a fixed codec preference, and a "4K" label must not promote a variant
above another. It does confirm the fold, since all three really are encodings of
one 1080p channel and iptv-org's separate `TRT4K.tr` is a different thing from
this provider's mislabelled entry.

Two smaller notes from the same probe. `Main 10` is 10-bit HEVC, a different
hardware decode path worth watching on weaker targets. And the audio differs
across variants (mono AAC, stereo HE-AAC, stereo MP2), so a variant switch
changes the audio layout mid-channel and the engine has to reapply the track
preference after every `loadfile`.
