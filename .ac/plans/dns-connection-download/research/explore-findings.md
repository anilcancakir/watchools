# Internal findings

Six `ac:explore` briefs, one per angle. Every anchor below was returned by an agent; the ones marked
VERIFIED were re-opened by the main thread before they were allowed to move a decision.

## The option path, Dart to libmpv

Nine hops, with `userAgent` as the only value that travels the whole way:

| Hop | Anchor |
|---|---|
| origin value | `lib/app/provider/provider_session.dart:220` (`playbackUserAgent`) |
| call site | `lib/app/controllers/playback_controller.dart:369` |
| interface | `lib/app/playback/playback_engine.dart:191` |
| implementation | `lib/app/playback/mpv_playback_engine.dart:236` |
| plugin Dart | `packages/watchools_player/lib/watchools_player.dart:28-34` |
| channel | `WatchoolsPlayerPlugin.swift:23` (`watchools_player`), handler at `:31-45` |
| native entry | `MpvEngine.swift:83` |
| applied | `MpvEngine.swift:105` (`mpv_set_option_string(handle, "user-agent", ...)`) |

**VERIFIED: the engine-wide option set is a static dictionary.** `MpvEngine.swift:36-72` defines
`private static let liveOptions: [String: String]`, iterated once per `start()` at `:107-111`. An
engine-wide option is one entry here and needs no Dart-side change at all.

**There is no per-load option mechanism.** `userAgent` is a named parameter threaded through every
hop by hand. A per-load value (a `Host` header) needs the same treatment at all nine hops.

The only test over the argument map is `test/app/playback/mpv_playback_engine_test.dart:163-180`,
which asserts the exact map `{'viewId': 3, 'url': ..., 'userAgent': 'watchools/test'}`. A new key
has to be added there. `packages/watchools_player/example/macos/RunnerTests/RunnerTests.swift` is
dead plugin-template scaffold that does not compile against the real initialiser, so there is no
Swift-side test to extend.

## The stream URL

**VERIFIED: one construction point.** `lib/app/protocol/xtream/xtream_stream_url.dart:113-122`
builds the `Uri` field by field from `Uri.parse(credentials.baseUrl)`, deliberately rather than
through `Uri.replace`, so a stray query on the configured base cannot ride along. That is the exact
shape a host rewrite needs, and the precedent to follow rather than duplicate.

**VERIFIED: the scheme is whatever the user typed.** `:117` copies `base.scheme`, and
`xtream_credentials.dart:405` admits both `http` and `https`. So an https panel is a real case, not
a hypothetical, and the pinning ceiling in `external-findings.md` binds for real users.

**VERIFIED: `ts` leads the container preference.** `xtream_stream_url.dart:39` is
`<String>['ts', 'm3u8']`, so the HLS demuxer is off the path for most channels. It is reachable:
`tool/xtream-mock/catalogue.mjs:267` declares a channel whose `formats` is `['m3u8']` alone, which
is the fixture the second-connection defect can be observed against.

The credential rides in the path (`xtream_stream_url.dart:83`), redaction is
`XtreamCredentials.redact` (`xtream_credentials.dart:241`) and it operates on log text rather than
on a `Uri`. Nothing in Dart sees the `302`; libmpv follows it alone.

The last point holding a structured `Uri` is `mpv_playback_engine.dart:236`, where `source.toString()`
is called. A rewrite has to happen at or before that line.

## The settings path

| Hop | Anchor |
|---|---|
| model field | `xtream_credentials.dart:78`, constructor `:88` |
| form field | `provider_settings_layout.dart:112`, `:233-245` |
| disclosure | `provider_settings_layout.dart:278-301`, state `bool _advancedOpen` at `:107` |
| submit | `provider_settings_layout.dart:443-448` |
| facade | `provider_setup_controller.dart:43-48`, construction `:251-254` |
| persistence | `provider_session.dart:343-344` then `xtream_credentials.dart:92` |
| read back | `xtream_credentials.dart:159-176`, use at `provider_session.dart:220` |

**VERIFIED, and this is the trap the plan is written around.** The whole credential is ONE JSON blob
under one key (`vaultKey = 'xtream_credentials'`, `:29`), and `load()` reads every field through
`_requireString` (`:419-426`), which throws `FormatException` when a key is missing. `ProviderSession`
catches exactly that and turns it into `ProviderFault.expired` (`provider_session.dart:429-433`),
which sends the user to `/saglayici` as though the panel had rejected their subscription.

So a new field added the way `user_agent` was added would break every credential already stored, and
would break it by lying about the cause. **The new field is read nullable, with a default, and a test
proves a blob written by the previous version still loads.**

Wind ships no accordion, so the disclosure is a hand-built `WAnchor` plus an icon flip. Closing it
clears the field deliberately (`:290`) so a typed-then-hidden value is not resubmitted, and
`provider_settings_layout_test.dart:301-335` is the test that holds that behaviour.

## Reuse map

| Need | Verdict |
|---|---|
| URL rewrite | REUSE the shape at `xtream_stream_url.dart:113` |
| Base URL validation | REUSE `xtream_credentials.dart:401` (`_normaliseBaseUrl`) |
| Failure classification | REUSE `ProviderFault` (`provider_fault.dart:28`) and `classifyProviderFault` (`xtream_account.dart:210`) |
| Named predicate over the enum | REUSE the pattern at `provider_fault.dart:93` |
| TTL cache | **Nothing exists.** The nearest is a day-boundary recompute at `provider_session.dart:828`, a different invalidation rule |
| Async timeout | **Nothing exists for provider traffic.** `lib/config/network.dart:14` sets 10 s on the `api` driver only; the `provider_network` driver at `app_service_provider.dart:118` sets none |
| Retry with backoff | **Nothing exists.** `xtream_client.dart:132` is a single alternate-spelling fallback, not backoff |

## Telemetry

`PlayerTick` carries nine fields (`watchools_player.dart:190-232`). **`inputRate` is already sampled
end to end**: `MpvEngine.swift:436` reads `raw-input-rate` out of the one `demuxer-cache-state` node,
it survives the restamp (`mpv_playback_engine.dart:455`), and
`mpv_playback_engine_test.dart:347-378` asserts every counter passes through.

**But `StallDetector` never reads it** (`stall_detector.dart:91-138`), no test exercises it
(`stall_detector_test.dart:30` passes null), and **nothing in the repository carries a reference
bitrate to compare it against**. `PlaybackHealth` has six members, all produced from position
movement plus `underrun` and `demuxerIdle`.

`.ac/research/player-layer.md:623-627` already proposes a throughput tier for the variant ladder and
marks it unverified. That vocabulary was designed for a different consumer (a variant switch) than
`PlaybackHealth` (a line of copy), which is the distinction a throughput verdict has to settle
before it is built.

## Test infrastructure

- Whole screen: `pumpScreen` (`test/support/screen.dart:44`). Leaf: `wrapWithTheme`
  (`test/support/wind_test_app.dart:34`). `setUp(WindParser.clearCache)` is mandatory.
- Container tests need `MagicApp.reset(); Magic.flush();`, plus `MagicTest.init()` and
  `Vault.fake()` where a vault or database is touched.
- HTTP is faked by binding `FakeNetworkDriver` under `XtreamClient.driverKey` (`_bindFakeDriver`,
  `xtream_client_test.dart:60-66`). Below the interceptor there is `_RawPanel`
  (`xtream_client_test.dart:98-134`), a real loopback `ServerSocket` used when only wire bytes are
  evidence.
- The native boundary is tested by mocking `MethodChannel('watchools_player')` through
  `TestDefaultBinaryMessengerBinding` (`mpv_playback_engine_test.dart:77-98`).
- **No test fakes DNS or a socket connect.** Confirmed by grep across `test/` and `lib/`. A resolver
  test is new infrastructure this plan designs rather than reuses.
- Coverage: CI sums `LF`/`LH` from `coverage/lcov.info`, excluding `lib/resources/views/`,
  `lib/app/providers/`, `lib/app/kernel.dart` and `lib/routes/app.dart`, and fails under 90.

## mpv option routing, which the plan must not get wrong

Read at `v0.41.0` `DOCS/man/options.rst`:

- `:3992` `--demuxer-lavf-o=<key>=<value>` "Pass AVOptions to libavformat demuxer."
- `:8031` `--stream-lavf-o=opt1=value1,...` "Set AVOptions on streams opened with libavformat.
  **Unknown or misspelled options are silently ignored.**"

`http_multiple` is declared in `libavformat/hls.c`, the HLS **demuxer**, so it travels on
`demuxer-lavf-o`. `seekable` is declared in `libavformat/http.c`, the **protocol**, so it travels on
`stream-lavf-o` beside the reconnect settings already there. Putting either on the wrong one is not
an error: it is silence, which is exactly the failure mode `MpvEngine.swift:59-60` already warns
about in its own comment. **A step that sets one of these has to prove it took effect rather than
assume it.**
