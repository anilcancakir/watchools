# Verification log

Stage 2a.1. Every claim below was checked against source before it was allowed to move a decision.
A subagent report is a candidate list, not a finding.

## REFUTED, and both of these were MY claims

The oracle checked the seven premises I briefed it with. Five held. Two did not, and both were
figures I stated as provider facts. I verified both refutations myself.

### "The stream token has a 300 s TTL"

I put this in the topic and in the oracle brief as a property of the provider.

**Check**: `tool/xtream-mock/catalogue.mjs:58-68`, read verbatim.

> Seconds a stream token stays valid for an ordinary account.
> The real panel this mock is modelled on is a load balancer: the API host answers `302` to a
> tokenised path on another host, and **the token lapsed within about forty minutes when one was
> reused**. Five minutes here is the same shape at a length a test can wait for.

**Verdict: refuted.** 300 s is our fixture's own constant, chosen so a test does not have to wait.
The measured panel figure is **about forty minutes**. Anything sized against 300 s (a re-resolve
cadence, a pre-emptive refresh interval) would be tuned to a test convenience.

### "The stall detector was validated against 115 live ticks"

I have stated this repeatedly, including in the directory survey for this plan.

**Check**: `grep` for the figure across the research and the plugin. The number in the record is
**106**, at `player-layer.md:593` ("`time-pos` froze at 0.08 across 106 ticks") and
`stall_detector_test.dart:48` ("The measured idle-display shape: 106 consecutive ticks at time-pos
0.08").

**Verdict: refuted as written, on both counts.** The figure is wrong and it is attached to the
wrong scenario: 106 ticks documents the **idle-display freeze**, not a healthy-playback validation
run. A 115-tick healthy run was genuinely measured in an earlier session, but **it was never written
into the repository**, so it has no source here and cannot be cited in a plan. Either it goes into
the record with its numbers, or it stops being quoted.

The general lesson, and it is the same one I have applied to three subagents today: a number
remembered is not a number sourced, and a fixture's constant is not a measurement.

## REFUTED

### "The VOD stream path is `/vod/<user>/<pass>/<id>.mp4`"

Reported by the reuse explore under `## Absent` and again in its Notes, sourced to "test comments
and research" rather than to the mock.

**Check**: `grep -n "kind" tool/xtream-mock/server.mjs`.

### "Wind has no D-pad activation", from `CLAUDE.md` itself

The UI explore refuted this against `w_anchor.dart:123-136`. Since it contradicts the project's own
record, I checked it, and then checked the thing the explore could not see.

**Check 1**, local Wind checkout: `w_anchor.dart:132-135` binds `ActivateIntent` and
`ButtonActivateIntent` to `_activate`, and `:293` installs `Actions(actions: _actions, ...)`. Its
own comment at `:123` says `WidgetsApp` maps `enter`, `numpadEnter`, `space`, `gameButtonA` and
`select` to `ActivateIntent`, and `select` is the D-pad centre on Android TV. So activation works
**in the local checkout**.

**Check 2**, and this is the one that matters: every **published** version in the pub cache,
including `1.5.2`, has `ActivateIntent` count **0** in `w_anchor.dart`. Eighteen versions checked.
The local checkout is `version: 1.5.2` with one commit on top of the release:
`92f20f5 fix(w-anchor): make a control reachable by keyboard and remote, and cost one stop (#202)`.

**Verdict: both are true, and the distinction is the finding.** `CLAUDE.md` was correct when
written and is correct for anything CI or a release build resolves, because the app constrains
`fluttersdk_wind: ^1.5.0` and the fix is **unpublished**. A playback screen developed against the
local overrides would show working remote activation and ship without it, which is the same trap
`CLAUDE.md` records from the other direction ("CI resolves the ecosystem packages from pub.dev, so
a job that is red after a local green means a sibling has unreleased work in it"). Here a local
green would be a false green.

So remote activation for the player's overlay controls is gated on a Wind publish plus a constraint
bump, exactly like the exact-case `User-Agent` assertion is gated on `magic#151`. That is an
interview decision rather than something to assume, and it is not the same question as focus
**traversal**, which remains genuinely absent in both.

## REFUTED, continued

**Verdict: refuted.** `server.mjs:897` documents the parameter as "`live`, `movie` or `series`" and
`:904` branches on `kind === 'movie'`. The segment is **`movie`**, not `vod`, so the reported path
would 404 against the mock and against any panel the mock was built from.

This is exactly the class of claim that becomes a bug in a URL builder rather than a wrong sentence
in a report: nothing in a unit test would catch it, because the test would be written from the same
wrong assumption. The stream-URL brief was spawned to settle these shapes from the mock and is the
authority; no path in this plan comes from a report's recollection.

## CONFIRMED, and it is a security finding the plan has to carry

### An mpv log line can carry the provider password into Dart

Found while locking the interface shape, not reported by any agent. The chain:

1. A stream URL carries the credentials **in its path**:
   `{baseUrl}/live/{username}/{password}/{streamId}.{ext}`. That is why
   `XtreamCredentials.describe(Uri)` exists at all.
2. The plugin subscribes to mpv's log at warn level, `mpv_request_log_messages(handle, "warn")`
   (`MpvEngine.swift:127`), with `msg-level` set to `all=warn` (`:97`).
3. It forwards the line **verbatim**: `"text": String(cString: data.pointee.text)` (`:465`).
4. FFmpeg's reconnect warnings name the URL. The plugin's own doc quotes one:
   "`http: Will reconnect ... error=End of file`" (`watchools_player.dart:42-44`), and that log
   channel is described there as the **only** signal for a lapsing token, so it cannot simply be
   switched off.

So the one fault channel the design depends on is also the one that can print a paid subscription's
password, into a Dart event that `magic_devtools`' telescope could record and any session
transcript could show.

**Verdict: confirmed, and it constrains the interface.** The engine must redact before a log line
leaves it, exactly as the account model strips `username` and `password` on receipt rather than
trusting a downstream wrapper. `describe(Uri)` handles a `Uri`; a log line needs the same treatment
for an arbitrary string, and the redaction has to happen at or below the interface boundary rather
than at a call site, because the whole point is that no call site should have to remember.

## CONFIRMED, and it reshapes the plan

### The plugin has no playback controls at all

The native-surface explore reported no seek, no pause write, no volume, no track selection, no
duration, no speed and no live-edge offset. That is the single most consequential claim in this
plan's research, because it decides whether the `PlaybackEngine` interface can be implemented over
the plugin as it stands or needs native work first. Checked all four Swift files under
`packages/watchools_player/macos/watchools_player/Sources/watchools_player/`:

| Check | Result |
|---|---|
| `grep -n 'mpv_command'` | **One** call site, `MpvEngine.swift:157`, inside the private `load()` helper. The only command the plugin ever issues is `loadfile`. |
| `grep -n 'mpv_set_option'` | One, `MpvEngine.swift:114`, for `wid`. Everything else goes through `mpv_set_option_string` at start. |
| `grep -n '"pause"'` | One, `MpvEngine.swift:363`, and it is inside the tick's **read** loop: `for (key, name) in [("paused", "pause"), ("coreIdle", "core-idle")]`. So `pause` is sampled and never written. |
| `grep -c 'seek'` | **0** in `MpvEngine.swift`, `SelfCapture.swift`, `WatchoolsPlayerPlugin.swift` and `WatchoolsPlayerView.swift`. |

**Verdict: confirmed.** `PlayerTick.paused` reports a state nothing in the app can set, and the
method channel's five methods (`play`, `state`, `stop`, `dispose`, `captureSelf`) are the whole
control surface. A screen with a pause button cannot pause today.

### One core at a time, so a mini player and a full player cannot coexist

Reported from `WatchoolsPlayerPlugin.swift:144` (a single `MpvEngine` on the view factory) and
`MpvEngine.swift:84-85` (`start()` refuses a second call while a core is alive). This matters
because `watchools_player.dart:53-55`'s own doc anticipates exactly two consumers, "the variant
ladder and a mini player", as the reason `events` is a field rather than a getter. So the Dart
surface was designed for two readers of one core, not for two cores.

### Nothing plays, and the play button is an empty callback

Traced by the routing explore: `live_tile.dart:76` to `now_layout.dart:398` to
`guide_controller.dart:548-551`, which sets `_channel`, recomputes `_programme` and calls
`refreshUI()`. No navigation. And the hero's own play affordance at `now_layout.dart:327` is
`onTap: () {}`.

**Verdict: confirmed by the trace.** This is the concrete shape of "nothing is playable": not a
missing engine, a missing everything between the tile and the engine.

### Routes must be registered in `boot()` or they are silently absent

`route_service_provider.dart:41-44` states it and `magic_router.dart:122-126` enforces it with a
`StateError` on `addRoute` after `_isBuilt`. Confirmed against the magic checkout, so the playback
route has exactly one legal registration site.

## CONFIRMED, from my own Stage 1a reading

### The app does not depend on the plugin

`grep watchools_player pubspec.yaml pubspec_overrides.yaml` returns nothing. So the plugin is a
sibling package no app code imports, and wiring it is a step of its own rather than an assumption.

### The plugin's manifest is still the scaffold's

`packages/watchools_player/pubspec.yaml`: description "A new Flutter plugin project.", empty
`homepage:`, and `plugin.platforms` declaring **macos only**. `plugin_platform_interface: ^2.0.2`
is declared and, by `grep -rn 'PlatformInterface' packages/watchools_player/lib/`, unused.

### The plugin's own doc says the interface is a redesign

`watchools_player.dart:6-11`: "A spike, not the player. It answers one question: does libmpv render
into a `CAMetalLayer` that Flutter composites? The `PlaybackEngine` the research calls for, with
buffer, live offset, position, telemetry and fault as first-class members, gets written once that is
settled, **and it will not look like this**."

So the five members the interface should carry are already named, by the same author, and the
current surface is explicitly disowned as their shape.

### `/baslik` is still unparameterised

`lib/routes/app.dart:21` registers `/baslik` with no `:id`, and `TitleView` reads whatever
`LibraryController.selected` holds. `CLAUDE.md` said this becomes `/baslik/:id` "with the Xtream
client", and the Xtream client has now landed (`68b1868`) without it. So that is an open item this
plan inherits rather than creates.

### No full-screen affordances exist anywhere

No `SystemChrome`, no `setEnabledSystemUIMode`, no `setPreferredOrientations`, no wakelock package
in the app. Relevant beyond convenience: this project already measured that **an idle display stops
libmpv presenting and freezes `time-pos` at the first frame**, which was misdiagnosed as a code
regression and retracted. So keeping the display awake is a correctness concern for playback here,
not a nicety.
