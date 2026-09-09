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
protocol whose bytes we serve in-process, with our own read and seek callbacks:
our resolver, our per-provider User-Agent, our prefetch policy, no port, no TLS
termination of our own, and the `connectionFactory` branch never reached. Build
the proxy only if AVFoundation becomes a second engine that needs it.

## Connection budget, and what it kills

`max_connections` is **1** on this account. The panel also serves VOD and live
from the same budget on at least one real backend, so the two compete.

- Parallel segment fetching was already out: ExoPlayer declined it
  (`google/ExoPlayer#565`, "we have no plans to support parallel loading") and
  Shaka declined preconnect (`shaka-player#2081`, will-not-implement).
- **A pre-warmed second `mpv_handle` on the predicted next channel is also out**,
  which reverses the obvious answer to "make zapping fast". The second
  connection drops the first stream. Zap speed has to come from buffer tuning
  and connection reuse alone.
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
