# Execution report

Plan: `dns-connection-download`
Branch: `worktree-network-resolver`, off `origin/master` at `5e96472`
Steps: 9 of 9 resolved, seven waves
Outcome: delivered, gates green, one proof deliberately not claimed and one step dropped

## What now exists

A resolver the user picks, which applies to every request the app makes over its own HTTP client,
and two libmpv option corrections.

| Layer | Files |
|---|---|
| The setting, parsed and validated | `lib/app/network/resolver_setting.dart` |
| The ladder | `lib/app/network/host_resolver.dart`, `host_lookup_io.dart`, `host_lookup_web.dart` |
| The install | `lib/app/network/resolving_http_overrides{,_io,_web}.dart`, `app_service_provider.dart` |
| Storage and the push | `xtream_credentials.dart`, `provider_session.dart` |
| The screen | `provider_settings_layout.dart`, `provider_setup_controller.dart` |
| The engine | `MpvEngine.swift` |

## Gates at delivery

| Gate | Result |
|---|---|
| `flutter analyze --fatal-infos --fatal-warnings` | clean |
| `flutter test` | 648 pass, 1 deliberate skip |
| Coverage, CI's own inline block | 2896/3013 = 96.1%, floor 90% |
| `dart format lib test` | clean |
| `flutter build macos --debug` | exit 0, run manually because CI compiles no Swift |
| `flutter build web --no-pub` | green, the only gate on the conditional-export seam |
| Running-app walk | `/saglayici`, the picker, the custom field, a real `unreachable` classification, zero exceptions |

## The three things this plan got wrong on the way, and what corrected each

**The scope was refuted at planning time.** The original plan pinned a resolved address into the
stream URL. It cannot work: `.ac/research/player-layer.md:26-28` records the panel answering a `302`
to a different origin, and `libavformat/http.c:487-509` shows the redirect loop carrying the caller's
headers to that origin untouched. So the pin would have covered the wrong connection and the forced
`Host` header would have broken the right one. Caught by the Stage 3.5 oracle, verified at both
sources, and the stream half left scope before a line was written.

**The reason I then gave for it was also wrong.** Having dropped the stream half, the plan and then
the settings copy said the resolver misses playback because of that redirect. The Phase 3 oracle
refuted that too: a stream URL is built on the panel's OWN host, so playback's first request already
goes to the name the user configured and libmpv resolves it before any redirect exists. The redirect
widens the gap; it does not cause it. The screen now tells the user the consequence instead of the
mechanism, and `CLAUDE.md` and `stack-decisions.md` were corrected a second time.

**A step's premise was refuted mid-execution.** Step 5 was to bound the provider driver's timeouts.
magic's `DioNetworkDriver` constructor already sets both from a `timeout` defaulting to 10000, and
the registration takes that default, so there was nothing to write. The Stage 1 explore had read the
`configureDriver` closure and reported the timeout absent without opening the constructor. Dropped,
with the reasoning in the plan beside the step.

## What the reviews found in the code

Three CRITICAL, all fixed, each proved by breaking the source.

**A typed custom resolver was silently discarded.** Found by the reviewer in the running app: the
field is written by `onSaved`, `Form.save()` skips an unmounted field, and the custom input unmounts
with the disclosure. Pick `Özel sunucu`, type an address, close the disclosure, save, and the system
resolver is submitted with no error. The step's briefing was written against exactly this class and
guarded the picker; the field came through the other door. Fixed on `onChanged` plus a submit-time
refusal, because the validator cannot run on a field that is not mounted.

**The DoH parser had never executed.** `host_lookup_io.dart` was 2 of 47 lines covered. The code that
reads an untrusted body, checks the DNS status, filters CNAME records and picks a TTL had no test,
while a wisdom line claimed one existed and pointed at a test driving a scripted rung instead. Eight
tests now run it against a loopback server. 40 of 49 lines.

**Unbounded reentrancy.** A custom DoH endpoint on the panel's own host made the DoH rung's client
re-enter the override, calling `resolve` once per level forever. Guarded, with a test that does not
fail without the guard but hangs, which is the defect stated exactly.

## The proof that did not land

Step 9's runtime demonstration that FFmpeg accepts `http_multiple=0` was attempted in full and
failed to discriminate. `evidence/09-http-multiple-inconclusive.txt` carries it. Two findings came
out of the attempt:

- **The app ignores the per-channel format list, and this paragraph first said something stronger
  and wrong.** `Channel` carries no formats and `streamUrlFor` passes no `channelFormats`, so the
  ACCOUNT's `allowed_output_formats` decides alone: an empty `served` admits everything
  (`xtream_stream_url.dart:96-98`). What that costs is a channel whose catalogue entry says
  `formats: ['m3u8']` being requested as `.ts` on an account that also allows `ts`, which a real
  panel may refuse. What it does NOT mean, which the first version of this claimed, is that the app
  cannot reach the HLS demuxer at all: on an account whose formats exclude `ts`, m3u8 is selected
  today and step 1's option is live rather than latent. The evidence for the correction was already
  in this plan, since the way the runtime attempt reached real HLS was by narrowing the mock's
  account with no app change at all. **On the one real subscription this project has measured, that
  condition does not hold**: it reports `allowed_output_formats: ["m3u8", "ts"]`
  (`.ac/plans/playback-layer-watchools-playbackengine-interface/research/explore-existing-player-research.md:83`),
  so `ts` wins for that account and step 1 stays latent there until the per-channel plumbing lands.
  The option is live for an m3u8-only account and latent for the account we can actually observe,
  which is the honest shape of it.
- **The instrument was too coarse.** With the mock narrowed to an m3u8-only account, real HLS flowed,
  but concurrent TCP connections fluctuate between one and two in BOTH states, because a playlist
  reload and a segment fetch briefly coexist regardless. The mock serves segments in milliseconds, so
  the window the option governs sits far below a two second sample.

Both follow-ups are in the plan's Deferred Ideas, with what would settle the second.

## Reported out of the ecosystem

- **magic's `AuthInterceptor` attaches the bearer token to every request with no origin test**
  (`magic/lib/src/auth/auth_interceptor.dart:17-33`), so any third-party call through the `Http`
  facade ships our own user's token to that third party. The local opt-out is a plain `HttpClient`
  for the DoH rung. The fix is an origin allowlist on the interceptor.
- **magic's `NetworkDriver` has no seam for a connection factory.** `configureDriver` hands over a
  `Dio` whose type this app may not name, so installing one would mean importing dio, which
  `CLAUDE.md` forbids. Routed around with `HttpOverrides`, which is a first-party mechanism rather
  than a workaround, so nothing was blocked. Filed as an improvement.
- **wind's `WSelect` emits three nested button semantics nodes for one picker**, so a screen reader
  announces three controls and a D-pad traversal would stop three times.

## Recorded rather than fixed

`redact` does not cover a custom resolver's query string, which may carry a token, and
`XtreamCredentials.toString()` prints the resolver verbatim. `Magic.put(hostResolver)` has no reader.
There is no in-flight deduplication, so N concurrent cold connections each run the full ladder, and a
failed resolve is not cached. `_RawPanel` and `_ScriptedLookup` now exist in three copies each and
belong in `test/support/`. `AppServiceProvider.register()` replaces `HttpOverrides.global`
unconditionally, which the first widget test to boot the real provider will notice. And the TLS
fixture needs OpenSSL 3.x for `-copy_extensions`, which bare macOS does not ship.

## One process failure, mine

I verified and committed wave 3 while its worker was still running, because its files had gone quiet
and its tests were green. The worker caught my edit mid-flight and asked whether the step had been
spawned twice. Nothing was lost and the end state is coherent, but the worker was in the middle of
its own break-proof runs, removing and restoring fixes one at a time, and an edit from outside could
have made one of those runs prove the opposite of what it claimed. Files going quiet is not a worker
finishing; the report is.
