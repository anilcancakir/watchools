# watchools_player

A spike, not the player. It answers one question, and the answer is yes:

**libmpv renders into a `CAMetalLayer` inside a Flutter `AppKitView`, and
Flutter composites its own widgets above it.**

```sh
node ../../tool/xtream-mock/server.mjs        # from the repo root
cd example && flutter run -d macos
```

The example autoplays the mock panel's H.264 channel and writes what it sees to
its sandbox container.

## What was measured

From inside the running Flutter app, reported over the channel:

```json
{"running":true,"videoOutput":"gpu-next","width":640,"height":360,"hasPicture":true}
```

`videoOutput` is empty until mpv's video output configures, so `gpu-next` there
is the renderer coming up inside the platform view rather than merely a demuxer
opening a URL. The mock's own log shows segments being fetched continuously
alongside it.

And MoltenVK's own log, which needs no capture permission and names the class:

```
[mvk-info] Created 3 swapchain images with size (1600, 1056) and contents scale 2.0
           in layer CAMetalLayer: watchools_player.WatchoolsPlayerView on screen Main Screen.
```

That is the whole claim in one line: mpv's swapchain is built against **this
package's platform view layer**, at the backing-store resolution rather than the
logical one (1600x1056 for an 800x528 view, so `syncDrawableSize` is doing its
job), and on screen rather than off it.

A window capture measured **21,648 of 155,570 sampled bytes changing** over
0.6 s, with the written PNG showing Flutter chrome, the video letterboxed inside
the platform view, and a Flutter overlay on top of it. Treat that as a
measurement taken once rather than a gate you can re-run: capture entitlement
follows the **responsible** process, not the app, so the same bundle returns a
uniform white image of the correct size when launched through LaunchServices
instead of from an entitled terminal. `SelfCapture` now detects the uniform case
and reports an error, because it previously read as `changed: 0` with
`wrotePng: true`, which is indistinguishable from a video that is not playing.

The capture also showed the Flutter UI frozen on a stale frame while the video's
own timecode advanced, because `SelfCapture` spins the run loop on the platform
thread. That is a wart in the affordance rather than in the architecture, and it
happens to demonstrate the point: mpv drives its layer independently of
Flutter's paint loop.

### With the redirect in the way

Re-run against the mock's tokenised redirect rather than a direct URL, because
the first measurement was taken against a stale checkout whose mock did not
redirect at all. Same result, `videoOutput: gpu-next` and 21,963 of 155,570
sampled bytes moving, and the mock logged **seven requests to the tokenised
path**, so libmpv follows the 302 from inside the platform view unaided.

The request split is the interesting part: two requests to the panel URL and
seven to the tokenised one. **mpv keeps the post-redirect URL as the playlist
URL and refreshes that**, so it never goes back through the panel. When a token
lapses there is nothing in mpv that re-resolves, which is why
`reconnect_on_http_error` only buys time and the real recovery has to be ours:
ask the API for a fresh URL and `loadfile` it.

## What this taught, beyond the answer

- **`gpu-context=moltenvk`, not upstream's `macvk`.** Upstream mpv reads `WinID`
  in four files and no macOS file is among them, so `--wid` is a no-op there.
  This works only because MPVKit carries a patch whose context casts `WinID` to
  a `CAMetalLayer`.
- **A sandboxed macOS app needs `com.apple.security.network.client`.** The
  Flutter scaffold ships `network.server` and not the client, so libmpv reached
  nothing at all and the failure looked like a rendering problem for a while.
  The main app already has it; a freshly generated example does not.
- **A sandboxed app cannot write to `/tmp`.** The first attempt at the state
  file produced nothing and said nothing. It goes in the container.
- **Window capture entitlement follows the responsible process, not the app.** A
  helper binary outside the process found the window, printed its size, and then
  got nil from the capture with no error, so the capture moved inside the
  plugin. That was written up as "an app may always capture its own window",
  which is wrong: launched through LaunchServices the same bundle gets a uniform
  white image of the correct size, and launched from an entitled terminal it
  gets the real one. Both cases return success.
- **MPVKit resolves through SPM into a Flutter plugin with no Podfile.** Flutter
  3.47 has Swift Package Manager on by default and this repository is already
  migrated, so the dependency is three lines in `Package.swift`.

## The option set, verified rather than assumed

`--stream-lavf-o` is a key/value list whose values mpv escape-interprets, and
FFmpeg silently ignores AVOptions it does not recognise, so a wrong spelling is
lost twice over with nothing reporting it.

- **The comma has to be bracketed: `reconnect_on_http_error=[4xx,5xx]`.** mpv's
  `read_subparam` accepts `"..."`, `[...]` and `%n%`, and has **no backslash
  escape**. Read back as a `MPV_FORMAT_NODE_MAP`, the two forms are:

  | Written | Parsed keys |
  |---|---|
  | `...on_http_error=4xx\,5xx,reconnect_max_retries=3` | `reconnect_on_http_error` = `4xx\`, and a garbage key `5xx,reconnect_max_retries` = `3` |
  | `...on_http_error=[4xx,5xx],reconnect_max_retries=3` | `reconnect_on_http_error` = `4xx,5xx`, `reconnect_max_retries` = `3` |

  A **string** readback cannot see this, which is why an earlier round of this
  file claimed the escape worked: `print_keyvalue_list` joins pairs with a bare
  comma and no quoting, so a mis-split value prints back byte for byte
  identical to the input. Only the key set shows the split. The escaped form
  also *appears* to set cleanly (`rc = 0`) purely because the trailing
  `reconnect_max_retries=3` donates the `=` the mis-split token needs; drop it
  and the same string returns `-7`.

- **`800MiB` is accepted** and reads back as `838860800`, exactly 800 MiB.
- **`cache-pause=no` with `cache-pause-wait=0` is not a contradiction.** Both
  set, and the wait is simply inert while pausing is off, which is the intent.
- **`cache-secs=180` is a reduction.** mpv's default reads back as
  `3600000.000000`, and its manual says so: "The default value is set to
  something very high, so the actually achieved readahead will usually be
  limited by the value of the `--demuxer-max-bytes` option." `MpvEngine` sets
  no `demuxer-readahead-secs` because with the cache on mpv takes **the maximum
  of the two**, so anything under 180 there is inert and anything over it
  silently defeats the cap.

### No reconnect option survives a lapsed token

The earlier claim here was that `reconnect_on_http_error` was "the difference
between playback ending and surviving it". That A/B introduced two options at
once (`reconnect_streamed=1` as well) and read survival off a 40 s deadline with
mpv's full default cache in front of it. Redone one variable at a time, with the
cache starved (`cache-secs=2`, `demuxer-readahead-secs=1`,
`demuxer-max-bytes=8MiB`) so a 509 bites promptly, against the mock's `expiring`
account and a 75 s deadline:

| Arm | Outcome |
|---|---|
| mpv defaults only | ended after 23.7 s, `reason=0` |
| `reconnect_streamed` alone | alive at 75 s, demuxer read **7.0 s** of content |
| `on_http_error` alone, bracketed | alive at 75 s, demuxer read **3.0 s** of content |
| both, bracketed, `max_retries=3` | ended after 29.6 s, `reason=0` |

Surviving the deadline is not playing. The two middle arms are retrying a dead
token forever: the core is up, `state()` still reports `gpu-next` and a picture,
and 3 to 7 seconds of content arrive in 75 seconds. For a viewer that is worse
than ending, because nothing anywhere reports a fault.

So `reconnect_max_retries=3` is in the option set **because it restores a
bounded failure**, not as a safety margin. There is nothing for FFmpeg to
reconnect *to*: mpv keeps the post-redirect URL as the playlist URL and never
goes back through the panel, so a lapsed token cannot be renewed at that layer.
Real recovery is ours: detect the stall, re-resolve through the API, `loadfile`.

Note what mpv calls the end: **`reason=0`, which is EOF, not an error.** A token
lapse arrives as a clean end of file, so a client watching for error codes sees a
normal finish. That is a fourth silent shape alongside the ones already in
`.ac/research/player-layer.md`.

### Where the fault is actually visible, measured in the Flutter app

The isolation above starved the cache to make the failure prompt. With the
plugin's real option set in front of it, the same lapsing account behaves worse
and the event channel is what shows it. One 75 s run against
`live/expiring/expiring/10001.m3u8`:

- mpv fetched **three segments**, then the token lapsed.
- From then on it re-requested **only the playlist**, took a 509 **twelve
  times**, and never asked for another segment.
- **No `endFile` arrived.** `state()` kept reporting `videoOutput: gpu-next`,
  `hasPicture: true`, and `cacheSeconds: 15.68` frozen at the value it held
  when the token died. `demuxer-cache-duration` does not fall to zero here, it
  stops moving, which is why the variant ladder must read
  `demuxer-cache-state` and `cache-speed` instead of it.
- The reconnects **are** visible, at `warn`, with the backoff in the text:

  ```
  warn   http: Will reconnect at 0 in 1 second(s), error=End of file.
  warn   http: Will reconnect at 0 in 3 second(s), error=End of file.
  error  http: Error reading HTTP response: End of file
  ```

  FFmpeg reports the 509 as `End of file`, the same silent shape as `reason=0`.

So the log stream is the earliest signal for this fault and the only one that
names it, which is the argument for `mpv_request_log_messages("warn")` over
`terminal=yes`: the same lines, delivered where Dart can act on them instead of
to a stdout no release build reads. Thirteen events reached Dart in that run,
`log` and `videoReconfig` both, so the channel is wired end to end.

## What is deliberately absent

No `PlaybackEngine`. That interface belongs in Dart with buffer, live offset,
position, telemetry and fault as first-class members, and it gets written now
that this question is settled. `play`, `state`, `stop` and `captureSelf` are the
smallest surface that could answer it.

No resize handling beyond keeping `drawableSize` honest. The patched `moltenvk`
context answers every VOCTRL with `VO_NOTIMPL`, so mpv is never told the layer
resized and only a video reconfig re-reads the drawable. Measured: growing the
layer leaves the swapchain at the old size, and forcing a reconfig through the
client API does not fix it. The fix is a patch to `moltenvk_control` that we
write and offer upstream; this view is already shaped so that lands without
further change here.

No gestures. Flutter's arena does not hand gestures to a macOS platform view, so
every control belongs in Flutter above the view, which is where they want to be
anyway for one design across touch, mouse and D-pad.

The buffer options in `MpvEngine` are the ones the measurements chose: zap on the
real provider's channel was 3040 ms on mpv's defaults and 1658 ms on this shape,
with an 18 s mean buffer and zero stalls across 135 s. See
`.ac/research/player-layer.md`.
