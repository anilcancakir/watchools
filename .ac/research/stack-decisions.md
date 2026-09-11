# Watchools: stack research and architecture decisions

Research date: 2026-09-07, second pass. Product: an IPTV client where the user brings their own provider subscription. We supply no streams and never carry video.

Targets: web, iOS, Android, Android TV, Apple TV, Samsung Tizen, Windows, macOS, Linux. Built on Anılcan's own Flutter ecosystem at `~/Code/fluttersdk` (`magic`, `wind` and their plugins), with a Laravel backend.

Every claim is anchored to a source or a `file:line`. Claims listed as unverified were not confirmed and must not drive a decision without checking first.

## Verdict

Flutter plus Laravel is right, and the ecosystem at `~/Code/fluttersdk` carries more of this product than expected: the billing rails are already built, the HTTP layer already has the hook the provider requirement needs, and the styling layer already knows about focus states.

Two corrections to the premise. "Single codebase" is true for state, business logic, styling and routing, and false for the video player, which needs six implementations behind one interface. And Apple TV is now reachable from Flutter, which was not true eighteen months ago.

Laravel does no video. It is a metadata service.

## 1. The player layer

**Superseded by `.ac/research/player-layer.md`**, which measured this against
Anılcan's own provider on 2026-09-09 and reversed the engine split: libmpv is
primary everywhere and AVFoundation is a capability-selected second engine, not
the HLS default. The table below is kept because its individual claims are still
accurate; what it gets wrong is the conclusion. Three specific corrections are
marked inline in the sections that follow.

| Platform | Engine | Reason |
|---|---|---|
| Android, Android TV | `video_player` (Media3 1.9.2) | Plays MPEG-TS natively as progressive and as HLS container. Best-tested on TV hardware. |
| iOS, HLS | `video_player` (AVPlayer) | Hardware decode, AirPlay for free. |
| iOS, raw MPEG-TS | `media_kit` | AVPlayer refuses raw TS over HTTP, documented failing with `AVFoundationErrorDomain Code=-11850` on [Apple forums thread 710481](https://developer.apple.com/forums/thread/710481), unanswered. Xtream panels serve extensionless and `.ts` live endpoints routinely. |
| Web | Own `HtmlElementView` over current hls.js, plus [mpegts.js](https://github.com/xqq/mpegts.js) | `video_player_web` is a bare `<video>` with direct `src` assignment. No MSE, no HLS. |
| Samsung Tizen | `video_player_avplay` | Samsung's fork over MMPlayer and PlusPlayer. Deliberately not API-compatible with `video_player`. |
| Apple TV | `video_player_tvos` for HLS, native TS engine behind a federated plugin | See section 4. |
| Windows, macOS, Linux | `media_kit` with vendored libmpv, see below | `video_player` has no Windows or Linux support at all. |

### The interface is mandatory before the first playback screen

`video_player_avplay`'s README says it outright: "video_player_avplay is not compatible with the original video_player plugin. If you're writing a cross-platform app for Tizen and other platforms, it is recommended to create two separate source files."

One `PlaybackEngine` abstraction, six implementations. The channel list, EPG grid, controls and state layer stay shared. Retrofitting this means rewriting every screen that touches playback.

### media_kit is the fallback engine, not the primary one

It plays anything FFmpeg can demux and is the only candidate exposing every mpv buffering property, which is what you tune for fast channel zapping. The blockers are current and specific:

- [media-kit#1445](https://github.com/media-kit/media-kit/issues/1445), open, filed 2026-08-27. Android live non-seekable streams render once then go permanently black while audio continues. Reproduced against a commercial Xtream panel and against Apple's own bipbop test stream, with hardware and software decode, under Impeller.
- [media-kit#1391](https://github.com/media-kit/media-kit/issues/1391), open since 2026-03-08. Android leaks about 25 file descriptors per second during HLS playback, crashing with `Too many open files` within minutes.
- [media-kit#1094](https://github.com/media-kit/media-kit/issues/1094), open since 2025-01-30, no maintainer reply. No DRM, and none is possible: libmpv has no CDM integration.
- One unfunded maintainer, 346 open issues, and a commit cadence that fell to 2 in August 2026.

### The desktop libmpv problem, and why we vendor

Verified against the pub.dev API on 2026-09-07:

| Package | Latest on pub.dev | Published |
|---|---|---|
| `media_kit_libs_macos_video` | 1.1.4 | **2023-09-27** |
| `media_kit_libs_windows_video` | 1.0.11 | 2025-03-24 (2023 libmpv core) |
| `media_kit_libs_linux` | 1.2.1 | 2025-03-24 |
| `media_kit` | 1.2.6 | 2025-12-13 |

Git `main` has moved ahead on both Windows and macOS, but those versions were never published. So a `pub get` today gets a libmpv from September 2023 on both desktop platforms.

The consequence is filed and reproduced: [media-kit#1441](https://github.com/media-kit/media-kit/issues/1441), open with zero maintainer response. The 2023 FFmpeg HLS demuxer locks onto subtitle renditions in master playlists carrying `#EXT-X-MEDIA:TYPE=SUBTITLES`, fetches `.webvtt` segments in a loop, never requests a video segment, and ends with "No video or audio streams selected". The reporter verified that swapping in a 2026 libmpv fixes it. Multi-subtitle HLS masters are the normal shape of an IPTV playlist, so this fails on a subset of channels and looks like a provider fault.

Linux bundles nothing and uses the distro's libmpv, so Linux is the only platform that gets a current core for free and the only one where we do not control it.

**Decision: vendor a current libmpv ourselves on Windows and macOS.** Fork or shadow the libs packages and pin a 2026 build. This is bounded work we control.

### Why not fvp, despite the evidence for it

[easy_tv_live](https://github.com/aiyakuaile/easy_tv_live) (1,140 stars), the one Flutter IPTV desktop client with real traction, chose `fvp` over media_kit and gets a 19 MB Windows build with selectable D3D11/NVDEC decoders and a `lowLatency` option. That is a genuine argument and it deserves to be recorded.

It loses on one thing. `fvp`'s engine is `libmdk`, a closed-source binary with a licence key. From [its README](https://github.com/wang-bin/mdk-sdk/blob/c3ca899c53d2369b7149aba8410576482d42e973/README.md#L197-L203): "Other users without a key: make sure your sdk is updated, otherwise you may see an QR image in the last frame." [fvp#330](https://github.com/wang-bin/fvp/issues/330) shows that watermark firing on end-user devices, printing a PayPal link over the video, with the author explaining the SDK expires if not updated for 40 days and key detection fails outright on Android 6.

The distinction that decides it: the media_kit staleness is a problem we can fix by shipping our own DLL. The libmdk watermark is a third party's dead-man switch over our paying customers' screens, and no amount of our own work removes it. If we later want fvp's performance, the prerequisite is written legal comfort on that README grant, not a benchmark.

### media_kit licensing is fine

The Dart package is MIT. The shipped libmpv binaries are built in LGPL mode, verified at source: the Windows build config sets `-Dgpl=false` and the macOS build script does the same. libmpv ships as dynamic frameworks, satisfying the LGPL relinking clause the ordinary way.

**Correction, and it does not carry over to the base we chose.** The dynamic-framework claim is true of the binaries media_kit consumes. MPVKit's, which `player-layer.md` adopts, are static: `file` reports `current ar archive` on the macOS, iOS and tvOS slices alike. Either build dynamic frameworks ourselves or prepare the relinkable-object route, and decide before the first submission rather than after. Our app code stays closed. Ship the LGPL text and a notice that libmpv and FFmpeg are LGPL and replaceable, and never switch to a GPL-enabled build for encoding.

On the Mac App Store tension specifically, the received wisdom is out of date. Apple's current [Licensed Application EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) carries an explicit carve-out: the no-modification restriction applies "except as and only to the extent that any foregoing restriction is prohibited by applicable law or to the extent as may be permitted by the licensing terms governing use of any open-sourced components included with the Licensed Application". VLC's removal was a GPL case, and VideoLAN relicensed libVLC to LGPL in 2012 specifically to unblock app stores. No LGPL rejection is on record.

### DRM

Not first-party today. [flutter/packages#11115](https://github.com/flutter/packages/pull/11115) adds Widevine and FairPlay to `video_player`, design signed off, still open and unmerged as of 2026-09-03.

Survivable because most BYO-credential streams are clear. Parse and store `#KODIPROP:inputstream.adaptive.license_key` as structured data now, wire it when the PR lands. On Tizen, PlayReady works through `video_player_videohole` but the `drmplay` privilege needs a partner-level certificate, confirmed by a Samsung engineer in [flutter-tizen#588](https://github.com/flutter-tizen/flutter-tizen/issues/588).

### Gaps to budget

- Chromecast has no maintained Flutter plugin. `flutter_cast_framework` last published 2022-07-31. Native work.
- Picture in picture missing from both leading candidates on mobile. On desktop it is a resize of the main window, not a second window, because [media-kit#1341](https://github.com/media-kit/media-kit/issues/1341) breaks focus on Windows with `desktop_multi_window`.
- Embedded subtitle tracks unimplemented in `video_player` ([flutter/flutter#79079](https://github.com/flutter/flutter/issues/79079)). Audio and video track selection did ship, in 2.11.0 and 2.14.0.

## 2. Custom headers and custom DNS

This is a hard product requirement from real provider experience, and the answer differs sharply between the two halves.

### Headers: table stakes, and achievable everywhere except web

| Target | Custom headers | User-Agent | Referer | Mechanism |
|---|---|---|---|---|
| Android, Android TV | Yes, every request | Yes, overrides the map entry | Yes | `DefaultHttpDataSource.Factory.setDefaultRequestProperties` |
| iOS | Only on a private key | **Yes, supported** | Yes, private key | `AVURLAssetHTTPUserAgentKey` is public since iOS 16; arbitrary headers still need `AVURLAssetHTTPHeaderFieldsKey`, which Apple says not to use |
| macOS, Windows, Linux | Yes | Yes | Yes | mpv `http-header-fields` |
| Web | **No** | **No** | **No** | Chrome silently drops `User-Agent`; `Referer` is a forbidden header; CORS preflight fails anyway |
| Samsung Tizen | **Cookie and User-Agent only** | Yes | **No** | Plugin README line 158, verified |
| Apple TV | Unverified | Unverified | Unverified | Fork territory, re-verify independently |

Two traps that will cost real debugging time:

**The Android User-Agent key is case-sensitive.** Verified at `video_player_android/lib/src/android_video_player.dart:134-135`:

```dart
const defaultUserAgent = 'ExoPlayer';
return httpHeaders[userAgentKey] ?? defaultUserAgent;
```

with `userAgentKey = 'User-Agent'`. A provider config storing `user-agent` misses the lookup and silently ships `User-Agent: ExoPlayer`. Worse, ExoPlayer's `DefaultHttpDataSource` writes its explicit `userAgent` field *after* the loop over `defaultRequestProperties`, so it overwrites a map entry too. Normalise header keys to exactly `User-Agent` in the provider model or the bug stays invisible until a panel 403s.

**Tizen cannot send `Referer` at all.** [video_player_avplay README line 158](https://github.com/flutter-tizen/plugins/blob/main/packages/video_player_avplay/README.md), verified: "The `httpHeaders` option of `VideoPlayerController.network` only support `Cookie` and `User-Agent`." The maintainer's reason in [flutter-tizen/plugins#749](https://github.com/flutter-tizen/plugins/issues/749) is that no public Tizen native API exists. Design the provider model so `Referer` is optional, not required.

On iOS the only working mechanism for **arbitrary** headers is an unsupported private key. Apple staff, [forum thread 20421](https://developer.apple.com/forums/thread/20421): "`AVURLAssetHTTPHeaderFieldsKey` is not a supported API, so you should not use it." The supported route, `AVAssetResourceLoaderDelegate`, cannot attach a header to a `.ts` segment fetch: it only accepts a redirect response, failing otherwise with `CoreMediaErrorDomain Code=-12881`. The private key is absent from the SDK headers entirely, so a plugin using it is reaching past the SDK.

**Correction for the User-Agent specifically, which is the header this product actually needs.** A supported key exists and this file predates it: `AVURLAssetHTTPUserAgentKey`, `AVAsset.h:609`, `API_AVAILABLE(macos(13.0), ios(16.0), tvos(16.0))`. Verified in the macOS 26.5 SDK. Alongside it, `AVURLAssetOverrideMIMETypeKey` (`AVAsset.h:553`, `macos(14.0) ios(17.0) tvos(17.0)`) makes AVFoundation ignore both the path extension and the server's `Content-Type`, which is the fix for a panel that mislabels a playable stream. Both matter only on an AVFoundation path; see `.ac/research/player-layer.md`.

### DNS: not our problem to solve in the app

No player exposes a resolver hook. ExoPlayer, AVPlayer, libmpv and hls.js each resolve independently. The full mpv option manual has no `dns` or `resolve` option, and `--http-proxy` is not used for https URLs. The hook is genuinely missing, but the conclusion drawn from it does not follow: pinning an address does not need a hook, only a caller that reaches the request before it goes out. `HttpOverrides` reaches every request this app makes over its own HTTP client, and that is as far as an in-app resolver decision goes. It does not reach libmpv's byte fetch, which resolves and connects inside FFmpeg on its own: the panel answers a `302` to a different origin (`.ac/research/player-layer.md:26-28`), so the redirect target is what a resolver decision has to apply to rather than the host the user typed, and `libavformat/http.c:487-509` replaces `s->location` and jumps to `redo` on that redirect while `s->headers` survives untouched, with no point in the loop where a Dart-side override is consulted.

**OwnTV ships an in-app custom DNS setting**, so this is not an untried category. README line 94: "App-wide custom DNS, System, Google, Cloudflare, Quad9, custom DNS or DNS-over-HTTPS; the selected resolver persists across restarts", on an Android TV, libmpv-based client. How it wires the resolver into mpv's byte fetch is not visible in its public tree. The "Multi DNS" feature XCIPTV and IBO Player advertise is portal-address failover, not name resolution: vendor marketing is not evidence here.

Android cannot set Private DNS programmatically at all. The only route is `VpnService`, and [Play policy](https://support.google.com/googleplay/android-developer/answer/12564964) permits it only for apps "with core VPN functionality or those requiring a remote server for essential features". A media player is not on that list.

**Decision: `HttpOverrides` covers the app's own HTTP, and that is the whole reach of an in-app resolver.** libmpv's byte fetch follows the panel's own redirect inside FFmpeg, where no Dart-side override is consulted; a setup screen per platform still carries the case neither mechanism reaches.

### The local loopback proxy

One mechanism solves headers and DNS together: a small HTTP proxy inside the app. It resolves through our own DoH resolver, connects with correct SNI, injects headers, rewrites playlist URLs, and hands the player `http://127.0.0.1:PORT/...`. Precedent exists ([AVPlayer-HTTP-Headers-Example](https://github.com/kevinjameshunt/AVPlayer-HTTP-Headers-Example), `shelf_proxy`).

Worth building for iOS, where it replaces an unsupported private API with something App Review cannot object to. Costs: rewriting both master and media playlists plus `#EXT-X-KEY` URIs, terminating TLS ourselves, proxying range requests faithfully, and a background mode on iOS. It does not work on web, and whether Tizen's AVPlay will play from loopback is unverified.

One landmine if we build it. The Dart SDK's `HttpClient.connectionFactory` **skips the TLS branch entirely**, verified in [http_impl.dart](https://github.com/dart-lang/sdk/blob/938322ce3d83e55b4ad39c807608510d30152983/sdk/lib/_http/http_impl.dart#L2684-L2701). A factory returning a plain socket sends cleartext to port 443 and every https source fails. The factory must return an already-secured socket, upgraded with the original hostname so SNI and certificate validation both use the name rather than the IP.

## 3. Building on the fluttersdk ecosystem

### Wind: the foundation is there, the trigger is missing

What already works and is worth reusing: `focus:` is a first-class class variant (`wind/lib/src/parser/wind_parser.dart:459`), focus state broadcasts down the tree through `WindAnchorStateProvider`, so `focus:ring-4 focus:scale-105` on a channel tile works the moment something focuses it. The class string is parsed once per unique (className, breakpoint, brightness, platform, states) tuple and cached (`wind_parser.dart:83`), so 200 identical tiles cost one parse. `WindRecipe` and the alias expander give a semantic token layer for free.

Four gaps, all of which land in Wind rather than in the app:

1. **D-pad activation does not exist.** `wind/lib/src/widgets/w_anchor.dart:192-215` is `Focus` plus `GestureDetector` with no `onKeyEvent` and no `Actions`. A grep of `wind/lib` for `onKeyEvent`, `ActivateIntent`, `CallbackAction`, `FocusableActionDetector`, `Shortcuts(` and `Actions(` returns zero source matches. Every button in the ecosystem is dead to a remote. Smallest fix, highest value: `FocusableActionDetector` with `ActivateIntent` inside `WAnchor`.
2. **No focus traversal control.** Zero `FocusTraversalGroup` or `FocusTraversalPolicy`. Flutter's geometric default is exactly what fails on TV layouts: focus escapes carousels, jumps between sidebar and content, and forgets position on return.
3. **No virtualized list.** `overflow-*` renders a `SingleChildScrollView` (`w_div.dart:1549-1585`). The only `ListView.builder` in the package is inside `WSelect`'s dropdown at `w_select.dart:894`. A 10,000-channel grid builds every row.
4. **No TV form factor.** `WindContext` carries width, height, platform and `isMobile`, nothing else. `platform_service.dart:41` maps Android TV to `android` and Apple TV to `ios`, so a 1080p TV and a 1080p monitor are the same context object. Needs a `tv:` variant and an `isTv` axis, which touches the cache key.

Also worth noting: `hover:` is the ecosystem's interaction idiom and every one of those classes is inert on a TV. The design vocabulary has to be re-pointed at `focus:`.

Wind itself is clean for every target. Its only `dart:io` is one conditional-import `FileImage` arm, and it has no platform channels, so Tizen and desktop are unblocked at the styling layer.

### Magic: billing is a direct hit, the catalogue layer is not

**Reuse without reservation:**

- `magic_payments` is the multi-rail entitlement design this product needs, already built. `BillingService` (five reads, every platform), `WebBillingService` (Stripe checkout, swap, cancel, portal), `StoreBillingService` (RevenueCat), and a 14-field rail-neutral `BillingEntitlement` that is what we gate playback on. The Laravel half is production-shaped: Stripe webhooks extend Cashier's controller with insert-then-handle idempotency, and the RevenueCat webhook verifies `hash_hmac('sha256', "{signedAt}.{raw}", secret)` with `hash_equals`, refuses stale signatures, and treats the webhook as a signal while re-reading truth from RevenueCat's API. There is a scheduled `billing:reconcile` drift sweep.
- `dio_network_driver.dart:123` exposes `configureDriver(void Function(Dio dio))`, documented for "certificate pinning, custom adapters". This is exactly the hook the custom User-Agent and DoH resolver need.
- Per-request `headers` already work on every `NetworkDriver` method.
- `MagicVaultService` over `flutter_secure_storage` is where the provider password goes, with `PlatformException` translated rather than swallowed.
- `telescope` is unexpectedly high value here. Provider quirks are HTTP quirks, and it makes every Xtream call inspectable without instrumenting them.

**Two shipped bugs found and verified:**

- `magic_payments/lib/src/drivers/billing_service_factory.dart:5` selects the web arm with `if (dart.library.html)`, while magic's own DB connector uses `if (dart.library.js_interop)` (`connection_factory.dart:32`). Under dart2wasm neither `html` nor `io` is true, so the build resolves `BillingServiceStub` and every billing read throws `UnsupportedPlatformException`. One-line fix.
- `BillingEntitlement.aiAnalysisTrialsRemaining` is both `required` and `int?` (lines 56 and 134) and the backend never sends it. Leaked from another product; every construction site pays for it.

**The catalogue layer needs work.** The ORM is production-shaped for CRUD and a sketch at 20,000 rows:

- `Blueprint` has no `index()` and there is no `CREATE INDEX` anywhere in the schema layer.
- The query builder has no `whereIn`, `like`, `join`, `groupBy` or `orWhere`, so "channels in category X matching Y" cannot be expressed.
- `insertAll` is a loop over `insert`, and each `insert` does a schema `PRAGMA` lookup plus a separate `SELECT last_insert_rowid()`.
- `get()` materialises the whole result set; nothing streams.
- Relations are JSON-hydration only, not SQL relations.

`DB.statement`, `DB.select` and `DB.transaction` are the escape hatch and we will live in them. The better answer, given the stated goal of advancing these packages: contribute `index()`, `whereIn`, `like` and a real batched `insertAll` back to magic. That is a second Wind-shaped contribution.

Also: web persistence needs measuring before it is designed around. `connection_factory_web.dart:41` uses `WasmSqlite3` with `IndexedDbFileSystem` (needing a hand-placed `web/sqlite3.wasm`), while `magic/CLAUDE.md:92` still says web is in-memory. One of the two is stale.

**Two things are entirely greenfield across all nine packages:** RFC 8628 device-code sign-in (zero matches) and D-pad focus navigation (the only `FocusNode` usages are two text inputs).

### App conventions to follow

From `depools` and `uptizm`, both real apps on this stack: `lib/{config,app/{controllers,models,providers},resources/views,routes,ui/{components,layouts}}`. Controllers resolved via `Magic.findOrPut`, views as `MagicStatefulView<XController>`, notification only through `refreshUI()`, HTTP only through the `Http` facade, lists through `MagicPaginator`. Atomic component folders with a recipe and a preview file. Token-only styling, with raw `Color(0x` failing a CI job. Every user-visible string through `trans()`. Tests use `MagicApp.reset()` plus `Http.fake` with `assertSent`.

One doctrine has to bend. Both apps state "adapt to WIDTH, never to platform". A TV is the case that breaks it, because the distinguishing input is the remote, not the width.

## 4. Platform reach

| Rank | Platform | Reuse | Effort |
|---|---|---|---|
| 1 | Android TV, Google TV | Same app | Manifest work, focus system, App Bundle, 64-bit plus 16 KB pages by 1 Aug 2026 |
| 2 | Fire TV, legacy Android | Same APK | Near zero on top of rank 1, but a dead end |
| 3 | Windows | Same app, media_kit backend | ~15 to 22 days, and 55% of demonstrated desktop demand |
| 4 | Samsung Tizen | Same app, Tizen playback layer | Separate toolchain, three TPKs for OS 6.0 to 10.0, 4+ week certification, Partner Group outside the US |
| 5 | macOS, Linux | Same app | ~12 to 18 and ~8 to 14 days respectively |
| 6 | Apple TV | Same app via `flutter-tvos`, plus a native TS engine | See below |
| 7 | LG webOS | Same app, webOS plugins | Official as of 2026 but webOS 26 Re:New and later only. Revisit in 2028. |
| 8 | Roku | None | 28% US share, zero reuse, BrightScript rewrite |

### Apple TV is reachable now, and this reverses the first pass

Verified on 2026-09-07: [`fluttertv/flutter-tvos`](https://github.com/fluttertv/flutter-tvos) (42 stars, BSD-3-Clause, created 2026-04-15) released `v3.47.2-tvos.1.10.0` on 2026-09-04. Flutter stable is `3.47.2`, released 2026-08-27. Eight days behind, on the exact current stable.

You do not build the engine. `fluttertv/engine-artifacts` publishes six prebuilt assets per release with real download counts. There is a 24-package federated `_tvos` plugin index, and `video_player_tvos` is on pub.dev under publisher `fluttertv.dev` with `platforms: [tvos]`. Its README claims 14 of 14 integration tests passing on physical Apple TV hardware. Five real Flutter apps are already on this path, the largest being [plezy](https://github.com/edde746/plezy) at 3,397 stars.

The architecture is identical to `flutter-tizen`, which we need anyway, so this is a second instance of a discipline we are already building rather than a new one.

Three cautions:

- **Raw MPEG-TS hits the same wall.** `video_player_tvos` wraps AVPlayer. media_kit's Darwin builds target iOS, simulator and macOS only, with no tvOS planned. ~~The fix is native work: wrap TVVLCKit (LGPL-2.1) or AetherEngine (LGPL-3.0 with an explicit App Store exception) behind a federated `*_tvos` plugin.~~ **Correction: no second native engine is needed.** media_kit is not the only route to libmpv. MPVKit 1.0.0's `Libmpv.xcframework` carries real `tvos-arm64_arm64e` and `tvos-arm64_x86_64-simulator` slices, shipping `client.h`, `render.h`, `render_gl.h` and `stream_cb.h` at API version 2.5, the same as every other slice. Downloaded and inspected; see `.ac/research/player-layer.md`.
- **Unsupported plugins are silently skipped**, not errored on. The build goes green and throws `MissingPluginException` at runtime. Every `_tvos` package is `0.0.x` and `video_player_tvos` has not been updated since May 2026.
- **Bus factor is one.** The org is five months old and nearly every commit is from one person. BSD-3 is the insurance, but forking means inheriting the engine build.

Also correcting the first pass: the claim that tvOS review is a softer gate does not survive scrutiny. Three sources say the opposite, and tvOS adds guideline 2.4.3 (usable with the Siri Remote alone), focus traps, Menu button behaviour and Top Shelf art on top of the same review team.

**AirPlay is the cheap interim and it fails quietly.** AirPlay video routing is an AVPlayer feature (`allowsExternalPlayback`). If the iOS app plays raw TS through VLCKit or mpv because AVPlayer refused it, the AirPlay video route is gone too and it degrades to screen mirroring: the phone decodes and re-encodes the frame buffer, latency and quality drop, battery drains, and the Siri Remote controls nothing. So AirPlay is a genuine 80% answer only for providers serving HLS. That fraction is measurable against our own subscription and nobody publishes it.

### Android TV is where the work actually is

Flutter's own umbrella issue [#180542](https://github.com/flutter/flutter/issues/180542) is honest: "Flutter Android apps can be run as generic Android TV apps, but there's gaps in tooling, I/O, navigation, focus, core design language, documentation, samples, and tests." Labelled P3. Sub-issues open and old: focus loss ([#49783](https://github.com/flutter/flutter/issues/49783), 2020), crash on IR remote Select ([#65233](https://github.com/flutter/flutter/issues/65233)), broken D-pad on TextField ([#147772](https://github.com/flutter/flutter/issues/147772)). That is exactly our surface.

Manifest trap: permissions imply hardware requirements. `ACCESS_WIFI_STATE` implies `android.hardware.wifi`, and some TVs are ethernet only. A plugin pulling one in transitively drops us off Android TV with no error. Declare `leanback`, `touchscreen`, `faketouch`, `telephony`, `microphone` and `wifi` as `required="false"`.

### Tizen is viable, and the costs are commercial

`flutter-tizen` released `3.47.1-tizen.1.0.0` on 2026-08-28, one day after upstream stable and one patch behind. Sponsored by Samsung Research; Tizen 10's TV home screen runs on it. Six years of continuous tracking makes it the strongest evidence that the third-party-embedder model is sustainable.

Costs: 4+ week store review per submission, Partner Group registration outside the US, a partner-level certificate for DRM, and QA who must be able to test every feature, which means procuring a legitimately licensed demo subscription. Samsung moved from GCC 9.2.0 to GCC 14.2.0 for 2026 products, so Flutter apps must use the 2026 SDK.

### Desktop is a real market, and it is Windows-shaped

Aggregated installer downloads across all 36 [iptvnator](https://github.com/4gray/iptvnator) releases: Windows 414,101 (55%), Linux 204,745 (27%), macOS 128,083 (17%), total 746,929. One OSS project, GitHub Releases only, no store presence. Corroborated by open-tv showing the same Windows dominance, and by 20+ Microsoft Store IPTV listings with hundreds of ratings each.

What desktop users want that mobile does not give: an EPG grid, multi-view, catchup, playlist management across many sources, external-player handoff, keyboard shortcuts. VLC does none of these. That is the gap.

**Ship Windows through the Microsoft Store.** Microsoft's [own comparison](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options) makes it decisive: Store MSIX is free, Microsoft re-signs, and there are no SmartScreen warnings. Direct download costs $150 to $300 a year for an OV certificate (with the key on a hardware token since June 2023) and still eats warnings until reputation accrues. EV lost its instant SmartScreen bypass in 2024. The cheap Azure Artifact Signing route is unavailable to individual developers outside the USA and Canada, so it is closed to us.

macOS: direct download with a $99/yr Developer ID and notarization. Native Mac App Store IPTV listings exist and all have zero ratings, so the Mac audience is being served by the iOS build.

Linux: `.deb` plus AppImage from GitHub Releases. Put `libmpv2 | libmpv1` in the `Depends:` line ourselves, because [Kazumi ships a `.deb` that does not](https://github.com/Predidit/Kazumi/blob/main/.github/workflows/release.yaml) and throws at first playback on a clean machine. Flatpak means building mpv inside the manifest; skip it initially.

Rough total for all three desktops: 35 to 60 engineer-days, plus 20 to 30 days a year of maintenance. Windows alone is 15 to 22 days for 55% of the demand.

### Fire TV is a dead end

Amazon confirmed in October 2025 that all future Fire TV Sticks run Vega, a Linux OS whose apps are React Native. No Flutter path. Amazon will also block sideloaded apps identified by the Alliance for Creativity and Entertainment, starting in Germany and France. Content neutrality does not exempt us from a list we cannot see or appeal.

## 5. The protocol layer

Kodi's `pvr.iptvsimple` is the de facto specification, because it is what providers test against.

Launch scope: Xtream Codes API plus M3U and XMLTV. Both come from the same account, since an Xtream panel also exposes `get.php` and `xmltv.php`.

Defer Stalker and Ministra. They need stateful 60-minute tokens, per-tune `create_link` resolution because stream URLs expire in seconds, MAC provisioning, four-candidate endpoint discovery, and error classification for plain-text bodies returned with HTTP 200. iptvnator needed a 1,752-line architecture document for it.

### Parser traps

- **Never split `#EXTINF` on the first comma.** `group-title="USA, News"` is everywhere. Tokenise `key="value"` pairs tracking quote state, then take the name after the last comma outside quotes.
- **`group-title` is semicolon-separated** for multiple groups, and `#EXTGRP` is a begin directive that applies until reset.
- **`tvg-id` is not unique.** HD, SD and FHD variants share it, so EPG mapping must be one-to-many or every sibling row renders empty.
- **XMLTV offsets arrive without the space the DTD mandates.** A parser expecting `20260611120000 +0100` silently treats `20260611120000+0100` as UTC and shifts the whole guide.
- **Bad credentials return HTTP 200**, usually `{"user_info":{"auth":0}}`. Plan for 200 with an empty body, 200 with the bare word `blocked`, 200 with HTML, and only occasionally a real 401.
- **`exp_date` is nullable** (null means lifetime), `is_trial` is a quoted string, `port` is a string.
- **Send a player-style User-Agent.** Panels behind Cloudflare challenge generic clients while allowlisting VLC and IPTV player signatures.

### Catch-up

Five conventions: `default`, `append`, `shift`, `flussonic`, `xc`. Resolution: explicit `catchup-source` wins, else derive by declared mode, else if Xtream and `tv_archive=1` derive the `xc` form, else no catch-up. The Xtream form puts duration in minutes and makes `/live/` optional. Clock offset comes from `server_info.timestamp_now` minus our own, because the timeshift endpoint interprets start time in server local time.

### No maintained Dart packages

`m3u` is Dart 3 incompatible and last released 2019. `muxa_xtream` has 18 downloads and its README calls it an AI-assisted experiment. Write both parsers ourselves, roughly 200 lines, on a background isolate. For XMLTV use the `xml` package's `XmlEventDecoder` in streaming mode.

PHP side: `gemorroj/m3u-parser` is maintained but LGPL-3.0. For XMLTV use native `XMLReader` over a `gzopen()` stream. No maintained PHP Xtream client exists; it is about 150 lines of Guzzle.

## 6. The backend

### Never proxy video

Settled by the maintainers of the most-starred OSS IPTV proxy in [iptv-proxy#28](https://github.com/pierre-emmanuelJ/iptv-proxy/issues/28): providers cap by connection count, not by IP, so proxying buys no concurrency. It makes us a restreamer under every provider AUP, means one abusive user gets our server IP banned for everyone on that provider, and a single 1080p stream is 4 to 8 Mbit/s, so 100 concurrent viewers is 400 to 800 Mbit/s sustained.

The in-app loopback proxy of section 2 is a different thing entirely: it runs on the user's device, carries their own single connection, and never touches our infrastructure.

### Where the backend earns its place

XMLTV above all. Real feeds decompress to hundreds of megabytes; parsing that on device costs over a gigabyte of peak memory and OOM-kills TV boxes. Parse once server-side with a streaming parser, serve per-channel windowed JSON.

Also: catalogue normalisation, deduplication across users sharing a provider, favourites and continue-watching sync, metadata enrichment, and a per-account cache of provider quirks (which timeshift format answered, which output format actually plays, which User-Agent got through).

### Credential custody

The user hands us a third-party password that is replayable, unrotatable, sent as a plain query parameter on every call, and echoed back in the auth response. Treat it as a password they have reused.

Default to device-only custody: the client authenticates to the provider itself and uploads only the derived catalogue. Server-side envelope-encrypted storage becomes an opt-in for background sync. That is the only version with a clean GDPR and KVKK story, because it makes credential storage consent-based and severable. `Vault` is the client-side home.

What device-only costs: no nightly server refresh, no server-side EPG ingest for that user, no expiry notification, no catalogue on a device that has never talked to the provider.

### Auth: build the device flow on Sanctum, not Passport

This reverses the first pass. Passport 13 ships RFC 8628 device authorization first-party, which is the textbook answer. But `magic-starter-laravel` is built on Sanctum, and adopting Passport means either running two auth stacks or migrating the starter's entire auth surface.

The device-code flow is a small, fully specified addition: a `device_codes` table, an endpoint issuing `device_code` plus `user_code`, a browser page where a signed-in user enters the code, and a polling token endpoint honouring `authorization_pending` and `slow_down`. Roughly 200 lines on top of Sanctum, against a migration of everything that already works. Build it on Sanctum and, if it proves general, contribute it to `magic-starter-laravel`.

Sanctum has no refresh tokens, so use short-lived tokens plus explicit re-pairing on a TV, and lean on the device-info columns the starter already adds to `personal_access_tokens` plus its `GET sessions` / `DELETE sessions/{token}` routes for per-device revocation. Turn on the `sessions` feature flag; it is off by default.

### Other decisions

| Area | Choice | Why |
|---|---|---|
| Database | PostgreSQL | Range-partition `epg_programmes` by start time, so guide expiry is a partition drop. `ON CONFLICT` targets the precision the upsert pattern needs. |
| Queues | Horizon, separate supervisors per queue | Needs `ext-pcntl` and `ext-posix`, which rules out serverless. Guard provider calls with `WithoutOverlapping` keyed on the provider, `RateLimited` per provider, `ThrottlesExceptions` for a provider that is down. |
| Sync | Chunked upsert with an explicit non-clobber allowlist | The allowlist is the only reason a nightly sync does not wipe a user's renamed channel. Deduplicate within the batch first, because Postgres `ON CONFLICT` errors when one statement hits the same target twice. |
| Billing | `magic_payments` plus its Laravel half | Already built, HMAC-verified webhooks, drift reconciliation. Fix the `dart.library.html` guard first. |
| Real-time | Polling plus a foreground pull at launch | Continue-watching is a debounced heartbeat, not chat. If Reverb comes later, install `ext-uv` on day one: `stream_select` caps at 1,024 connections without it. |
| API | REST plus API Resources, versioned at `/v1/` from the first commit | Access patterns are few and fixed. A Samsung TV cannot be force-updated, so the version prefix is not optional. Cursor pagination, and a `?since=` delta endpoint. |

### Metadata licensing

TMDB prohibits caching longer than six months and requires the logo plus the "not endorsed" notice, so a permanent mirror is out and a `last_metadata_fetch_at` refresh sweep is in. TheTVDB publishes open tiers: free under $50k revenue, $1,000/yr to $250k, $10,000/yr to $1M. Fanart.tv needs written consent and prohibits embedding its API in our own.

Title matching: strip provider prefixes and bracket tags, remove technical tokens, extract the year and pass it as a filter rather than part of the query. That last point is the biggest accuracy lever. Cache by normalised title hash so a title shared across 200 providers costs one call.

## 7. Business constraints

### App Store

The binding clause is 5.2.3, and it covers streaming: "Streaming of audio/video content may also violate Terms of Use, so be sure to check before your app accesses those services. Authorization must be provided upon request."

The compliance recipe is in Apple's own rejection letter, quoted in [PeerTube#6966](https://github.com/Chocobozzz/PeerTube/issues/6966): "your app provides potentially unauthorized access to third-party audio or video streaming, **catalogs, and discovery services**." Apple objects to browsing and finding, not only playback. So: no bundled playlist, no default portal, no demo stream, no search across sources. Search within the user's own loaded playlist is defensible.

Guideline 4.7 does not apply to us. 4.2.2 does, so real product depth is also legal armour.

### Being clean gets you approved. It does not keep you approved.

Perfect Player, over a million downloads and content-neutral, removed from Play on a pay-TV complaint. Televizo markets itself as 5.2-compliant by name and was still swept up when JioStar had 36 IPTV apps with 26 million combined downloads removed from both stores in March 2026 under a Delhi High Court dynamic injunction. IPTV Smarters was pulled three times and restored each time in about 10 days, because the developer had lawyers and a rehearsed counter-notice. Apple's 2025 transparency report: of 26,305 removal appeals, 423 resulted in restoration.

**A store removal must not brick a paying customer's app.** Entitlement lives on our backend, not in a store receipt check that fails when the listing disappears.

### Desktop stores are friendlier

Both Microsoft and Apple demonstrably approve BYO-playlist players on desktop. [MyIPTV Player](https://apps.microsoft.com/detail/9pjj2nmbf0tr) (355 ratings) carries the compliance pattern in its own listing: "No IPTV channels or streaming URLs are provided. We are not affiliated to any IPTV operators." Microsoft Store Policy 10.2 is a generic IP clause with no equivalent of 5.2.3.

### Payments

Paddle is out. Verified on 2026-09-07 against [its AUP](https://www.paddle.com/help/start/intro-to-paddle/what-am-i-not-allowed-to-sell-on-paddle), prohibited category 4: "Illicit streaming services, streaming downloaders, content copying and IPTV". The word appears verbatim; page last updated 13 April 2026.

Stripe is arguable but not safe: its restricted list prohibits anything that "facilitate[s] infringement". In-app purchase on mobile sidesteps the processor question. For web and desktop we need an honest conversation with a processor up front.

Guideline 3.1.3(b) helps: a web subscription may unlock the iOS app, provided the same items are also offered as in-app purchases.

### Web is a safer channel and a more dangerous architecture

Browsers block cross-origin HLS, providers will not set CORS headers for our origin, and neither `User-Agent` nor `Referer` can be sent. The workaround is a server-side proxy, which puts us in the delivery path of every stream and destroys the passive-player posture the legal defence rests on. Either accept that a meaningful share of provider URLs will not play in a browser, or take the legal question to a lawyer first.

## 8. Competitive position

**Samsung and LG is the opportunity.** None of TiViMate, Televizo, OTT Navigator, Sparkle or XMPlayer ships there. The entire market is MAC-bound one-off activations at 5 to 10 euros: Smart IPTV 5.49, Flix IPTV 7.99, IBO Player around 7 to 10. IBO's own FAQ states "the app didn't have an EPG system integrated", and its homepage lists eighteen partner apps all pointing at one dev company.

**The wedge narrowed while we researched.** IPTV Smarters Player Expert v11 shipped days ago with one account syncing sources, favourites and playback progress across iPhone, iPad, Mac and Apple TV. Apple only. XMPlayer is a browser-first cloud player with cloud DVR and cross-play resume, with no TV platform at all.

So sync alone is not the differentiator. **The unclaimed position is the intersection: web, iOS, Android, Android TV, Apple TV, Tizen and desktop, one account, one subscription.** Nobody spans it, and with `flutter-tvos` and `flutter-tizen` both healthy, we can.

Second differentiator, cheap and visible: a licence bound to the account rather than the TV's MAC address. IBO's FAQ admits a TV has two MAC addresses and switching from wifi to ethernet can consume a second activation.

Cheap wins the incumbents leave: timeshift (TiViMate still has none), reliable scheduled recording, search scoped to the user's own groups rather than 40,000 channels, and a purchase flow that does not need a companion app.

## 9. Sequencing

1. **Playback spike before any product code.** Build the `PlaybackEngine` interface and prove five things against Anılcan's real Xtream account: raw MPEG-TS on iOS, live HLS holding four hours on Android, the same on Windows with a vendored libmpv, custom User-Agent reaching the segment requests, and channel zap time. Also measure what fraction of the provider's channels serve HLS versus raw TS, because that number decides how good AirPlay is on Apple TV.
2. **Wind TV contribution.** `FocusableActionDetector` plus `ActivateIntent` in `WAnchor`, a focus traversal policy with memory, a virtualized list widget, and a `tv:` variant with an `isTv` axis in `WindContext`. This unblocks every TV target at once and improves the package.
3. **Protocol layer.** Xtream client, M3U parser, XMLTV streaming parser, catch-up resolution. Server side, with iptvnator's mock panel borrowed for tests.
4. **Mobile on iOS and Android**, device-only credential custody, `magic_payments` wired with the wasm guard fixed.
5. **Android TV**, exercising the Wind focus work.
6. **Windows**, through the Microsoft Store.
7. **Apple TV and Tizen**, once the native TS engine plugin and the certification logistics are understood.
8. **Web and the remaining desktops.**

## Open questions

Only Anılcan can settle these, and each reorders the list above.

- **Target geography.** The US is Roku and Tizen first with weak Android TV. Turkey and Europe weight very differently.
- **Credential custody default.** Device-only with opt-in sync is the clean privacy story and costs background features.
- **Pricing model.** Account-bound subscription is the differentiator against MAC-bound one-offs, but the Smart TV market anchors at 5 to 10 euros one-off.
- **How much of this goes back into the ecosystem.** The Wind focus work and the magic query-builder work are both genuine package contributions, but they slow the product down.

## Unverified

- Global TV OS market share. Sources contradict each other by 10 to 15 points. The US figures (Roku 28%, Tizen 23%, Parks Associates) are usable.
- Apple's current commission on US external purchase links, and Google's link-out fee percentage. Both are live litigation with no primary page stating the rate in force.
- TMDB commercial pricing and rate limits. Forum posts, not the terms document.
- Real XMLTV file sizes. The 100 to 500 MB range is one audit's estimate.
- Whether the libmpv build media_kit ships propagates `http-header-fields` to HLS segment sub-requests. [mpv#4155](https://github.com/mpv-player/mpv/issues/4155) is 2017-era and may be fixed. Smoke test first on desktop.
- Whether Tizen's AVPlay will play from a `127.0.0.1` loopback proxy.
- Header behaviour on the tvOS fork. Re-verify independently.
- Raw MPEG-TS support on Tizen through `video_player_avplay`. Needs a device test.
- The exact upstream mpv version inside `libmpv-darwin-build` v0.6.0. Build date confirmed as 2023-09-24, version string not extractable.
- Whether magic's web SQLite persists via IndexedDB or is in-memory. The connector and `magic/CLAUDE.md:92` disagree.
- The 10-to-16-week native tvOS estimate and the 35-to-60-day desktop estimate are extrapolations from repo file counts, not cited figures.
