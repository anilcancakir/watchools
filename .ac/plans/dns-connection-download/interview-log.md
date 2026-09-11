# Interview log

Plan: `dns-connection-download`. Auto mode: true.
Worktree `network-resolver`, branch `worktree-network-resolver`, off `origin/master` at `5e96472`.

## Deviations from the skill's default procedure, and why

**The gitignore guard is skipped.** The skill appends `.ac/` to `.gitignore`; this project tracks it
deliberately, 74 files under `.ac/` are in the index, and `CLAUDE.md` cites `.ac/research/*.md` as
committed reading. Ignoring it would break an established convention.

**The slug is not the mechanical one.** The argument string carries only an instruction
(`hepsini ... planla yap uygula ... full auto mode`), so the seven-step derivation produces
`hepsini-oalbilecek-halde-planla-yap`: five tokens, none about the work. The subject lives in the
conversation that preceded the command. Named for the subject instead, since downstream agents read
this file as a spec.

**No `ac:librarian` was spawned.** The counts policy asks for two to three. Ten ran on exactly this
topic immediately before this plan, across ten angles, and their load-bearing claims were verified
at source by the main thread. They are archived at `research/external-findings.md`. Re-spawning a
second cohort to re-read verified findings would spend tokens against the standing rule that a
near-miss already in hand beats a fresh search.

Six `ac:explore` briefs did run, all internal, archived at `research/explore-findings.md`.

## Stage 1-2 synthesis

**Codebase state**: `disciplined`. Consistent style, a 90 percent coverage floor enforced in CI over
a denominator that excludes only the generated scaffold, doc blocks that carry the contract and the
measurement rather than restating the signature. Match patterns strictly.

**Conventions**, for the plan's `## Codebase Conventions`:

1. `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` members; tests mirror the
   source path exactly.
2. No fallback catch that swallows. `provider_session.dart:429-433` is the house shape: catch the
   specific exception, map it into a vocabulary the UI renders, and say in the doc block that this
   is deliberate.
3. Doc blocks everywhere, carrying the contract, the failure mode, the unit, and the measurement
   that decided a number. A doc block restating the parameter list is a defect here.
4. Strict explicit types; `dynamic` only where a wire boundary forces it.
5. Nested by role under `lib/app/`, no barrel exports there. A UI component folder is the exception
   with `index.dart` plus dotted `*.recipe.dart` and `*.preview.dart`.
6. Relative imports within `lib/`, no path aliases.
7. Generated and never edited: `lib/config/wind_theme.g.dart`, `lib/app/_plugins.g.dart`,
   `lib/_previews.g.dart`, and every platform plugin registrant.
8. LSP false positives: none recorded for this surface.
9. Test mount discipline: `pumpScreen` for a screen, `wrapWithTheme` for a leaf,
   `setUp(WindParser.clearCache)` mandatory, `MagicApp.reset(); Magic.flush();` for container tests,
   `.env` overridden rather than defaulted.
10. **TDD yes.** `TEST_INFRA_PRESENT = true`, `TEST_FRAMEWORK = flutter_test`,
    `TEST_COMMAND = flutter test --coverage`. And the house rule beyond TDD: a test is not written
    until it has been proved to fail with the fix removed.

**What exists today**

| Need | Status |
|---|---|
| A place to put an engine-wide mpv option | Exists, `MpvEngine.swift:36-72` |
| A URL rewrite shape to copy | Exists, `xtream_stream_url.dart:113-122` |
| A fault vocabulary to classify into | Exists, five `ProviderFault` members |
| A settings path to extend | Exists, the `userAgent` chain end to end |
| `raw-input-rate` sampled | Exists, and is inert: nothing reads it |
| A per-load option mechanism | **Absent.** `userAgent` is threaded by hand at nine hops |
| A TTL cache | **Absent** |
| An async timeout on provider traffic | **Absent** |
| A DNS or socket test double | **Absent anywhere in the suite** |
| A reference bitrate to compare a rate against | **Absent anywhere in the repository** |
| VOD URL derivation, the prerequisite for download | **Absent**, and it needs a store migration |

**Effort**: Large. Cross-module, plus native Swift, plus new test infrastructure.

## Risks research produced

1. **A new required credential field breaks every stored credential**, and lies about why:
   `_requireString` throws, `provider_session.dart:431` renders that as `ProviderFault.expired`, and
   the user is sent to the form as though the panel rejected them. VERIFIED at source.
2. **mpv silently ignores an option sent on the wrong passthrough.** `http_multiple` is a demuxer
   option, `seekable` is a protocol option, and `options.rst:8032` states unknown keys are dropped
   without an error. A step that sets one must prove it took effect.
3. **Pinning an address on https drops SNI and hostname verification together**, silently.
   VERIFIED at `tls.c:66-68` and `tls_openssl.c:869-880`.
4. **The scheme is whatever the user typed**, so https panels are a real population rather than a
   hypothetical.
5. **A throughput verdict has no reference bitrate to compare against**, and no recovery action
   attached to it. A `PlaybackHealth` member that names a condition nothing acts on is the promise
   `CLAUDE.md` warns about.
6. **Download's prerequisite does not exist.** `container_extension` is consumed at parse into an
   uppercased display fact, so a VOD URL cannot be derived from cached state at all.
7. **DoH is slower than the resolver it would replace** on the healthy path, 71 to 108 ms cold
   against 13 ms. Measured on the owner's own line, which he then flagged as unrepresentative:
   1 Gbit TurkNet with AdGuard on OpenWRT. The general audience is a plain TTNet subscriber.

## Decisions put to the user

Four, all preference or scope rather than answerable from code. Recorded as they resolve.

## Stage 3 outcome: four defaults, not four answers

The four questions went out with a recommended option each, grounded in the Stage 1 research and the
Stage 2 deep read. **No answer arrived within the 600 s wait**, which is consistent with the user's
own statement that he is away from the machine. Each is locked on its recommendation and recorded as
a **default rather than a choice**. All four are listed in the plan's `## Risks Accepted` so a later
reader can see which were chosen and which were merely not contradicted. Any of them is cheap to
revisit before execution.

### D1. Scope: the network layer and its setting. Download and the throughput verdict are out.

**Why download is out.** Its prerequisite does not exist. `container_extension` is consumed at parse
into an uppercased display fact inside `StreamFacts`, so a VOD URL cannot be derived from cached
state at all; recovering one means lowercasing display data back into a path, which is the wrong
direction. VOD needs a real field on `TitleItem` and a column in the store, which is a protocol-layer
change plus a migration. Building a downloader before there is a URL to download is building on air.

What this plan does carry forward instead: the two findings that are already settled and would
otherwise be re-researched. **Apple TV is a platform stop for download**, not a later task, because
Apple's own guide caps local persistent storage at 500 KB with everything else purgeable. And
**multi-connection download is forbidden by the account rather than by the server**, which answers
the "make it fastest" half before the work starts.

**Why the throughput verdict is out.** `inputRate` is sampled and inert, and two things it would need
are missing: a reference bitrate to compare against, which exists nowhere in the repository, and a
recovery action to attach to the verdict, which is the variant ladder and is unbuilt. A
`PlaybackHealth` member naming a condition nothing acts on is exactly the promise `CLAUDE.md` warns
about. `.ac/research/player-layer.md:623-627` already holds the design for it, marked unverified,
and that is where it belongs until the ladder is built.

### D2. The resolver setting lives in the credential record, read nullable.

**Why**: the first request any user makes is the onboarding handshake, and that handshake is exactly
the one that fails when the ISP resolver cannot answer. A setting the user can only reach after a
successful handshake cannot fix a failing handshake. The form already carries both fields on screen
at once, so submitting carries the resolver choice into the same request that validates it.

It also reuses a path that is proven end to end, at the cost of one property: signing out forgets
the resolver choice. Accepted, because sign-out forgetting everything is the behaviour a user
expects from sign-out.

**The read is nullable and this is load-bearing.** A required field would make `load()` throw on
every credential written by the previous version, and `provider_session.dart:431` would render that
`FormatException` as `ProviderFault.expired`, sending the user to the form as though their
subscription had lapsed. A test proving an old-shape blob still loads is part of the step.

### D3. On https: resolve for the catalogue, do not pin the stream, say so on screen.

**Why**: the two halves have different ceilings and pretending otherwise is what makes a setting
lie. In Dart we control the TLS handshake, so `SecureSocket.secure(socket, host: originalHost)`
keeps SNI and certificate validation correct against the real name while connecting to an address we
chose. In libmpv we do not: an IP in an https URL sets `numerichost` and silently drops both.

So the catalogue gets the user's resolver and the stream does not, and the screen states that rather
than leaving the user to discover it. A setting that silently applies to half of what the user
thinks it applies to is worse than one that applies to none of it.

### D4. System resolver first, DoH on failure or timeout.

**Why**: measured on the owner's own line, a cold DoH query costs 71 to 108 ms against 13 ms for
plain UDP. DoH as the default path would slow every healthy lookup to fix a minority's broken one.
System first with a short timeout, then the fallback, costs the healthy case nothing and still
converts an unbounded resolver hang into a bounded failure, which is the defect FFmpeg cannot fix
for us because its `getaddrinfo` call is not wired to an interrupt callback.

## Stage 3.5 trigger evaluation

**Trigger 1 fires** (security-critical surface): the stream URL carries the subscription password in
its path and the plan rewrites that URL; a user-typed resolver address becomes a socket destination;
a DoH answer is untrusted input we then connect to; and the https refusal is the only thing standing
between the design and a silent TLS downgrade.

Triggers 2, 3 and 4 do not fire: no composable framework chain is adopted, the research produced no
contradictory recommendation on the chosen path, and the credential change is additive rather than
destructive.

One `ac:oracle` spawned on trigger 1 alone.

## Stage 3.5 outcome: one REFUTED premise, two CRITICAL, three IMPORTANT

The oracle refuted the premise the largest half of the scope rested on, and the main thread verified
the refutation at both sources before acting on it.

**The refutation.** `.ac/research/player-layer.md:26-28`, our own measurement against the real
provider: "The panel is a load balancer: the API host answers `302` to a different host with a
base64 token path, so the real stream is on another origin and every header, User-Agent and DNS
decision has to apply to the redirect target rather than to the host the user typed."

And `libavformat/http.c:487-509` at `38b8833`, read directly: the redirect loop does
`s->location = s->new_location;` then `goto redo`, resetting `s->auth_state` and nothing else.
`s->headers` is untouched and re-emitted verbatim on the next request.

Two consequences, and together they kill the stream half of the design:

1. **The pin covers the wrong connection.** Rewriting the stream URL pins the host that answers the
   `302`. The host that actually serves video is named by the panel in its `Location`, and libmpv
   resolves that one through `getaddrinfo`, which is the resolver this feature exists to bypass.
2. **The forced `Host` header rides the redirect.** The new origin receives
   `Host: <original-panel-host>` while FFmpeg suppresses its own correct one at `http.c:1617`. On a
   vhost-multiplexing edge that turns a channel that plays today into a 404.

The mock cannot see this. `tool/xtream-mock` redirects to the same host, so a test written against it
would pass while the real provider broke.

**Rescoped, and the result is smaller and more honest.** The stream-URL rewrite, the `Host` header
and the nine-hop threading all leave scope together. What survives is the half that was always the
stronger one anyway: the panel API. When a Turkish ISP cannot resolve a panel domain, the failure
lands on `player_api.php` first, so onboarding fails and no catalogue ever arrives; the user never
reaches playback to care about it. Fixing the API half fixes the symptom the user actually reported.
And on that half the pin is correct on https too, because `SecureSocket.secure(socket, host:)` keeps
SNI and certificate validation against the real name while connecting to an address we chose.

D3 is therefore retired rather than answered: with no stream pinning there is no http-versus-https
split to explain, and the resolver applies to the catalogue on both schemes.

### The other findings, all accepted into the plan

**CRITICAL, the resolver setting is an exfiltration channel.** The API request carries the username
and password, the scheme may be `http`, and on http there is no certificate to catch a wrong
destination. A resolver address pasted from a forum thread would send the credential in cleartext to
a host the attacker chose, with no visible symptom, and that risk is new because today the resolver
is the ISP's and the user never picked it. A private-range refusal does not mitigate it, since an
attacker returns a public address they own. **So: a named picker (System, Cloudflare, Google,
Quad9), a custom entry validated as an IP literal or an https DoH URL and never a hostname (a
hostname would need the resolver it replaces), and the resolved address shown in settings so the
destination is inspectable.**

**IMPORTANT, a nullable read is not enough.** `json['resolver'] as String?` on a non-string value
throws `TypeError`, which passes both the `FormatException` and `MagicVaultException` catches at
`provider_session.dart:430-449`, and `start()` is awaited inside `Magic.init()` before `runApp()`,
so the app boots to nothing. An `_optionalString` sibling that mirrors `_requireString`'s `is! String`
shape check and returns null is what the step writes.

**IMPORTANT, the disclosure would silently drop the setting.** `provider_settings_layout.dart:290`
clears its field on close and the form never prefills, so a user who sets a resolver and later
reopens settings to fix a password submits with the disclosure closed and loses reachability. The
symptom would read as "changing my password broke it". The field is seeded from the stored
credential and excluded from the clear-on-close rule.

**IMPORTANT, a loopback answer is a signal rather than a refusal.** Vodafone returning `127.0.0.1`
is the documented Turkish shape. Treat it as tamper and escalate to the next rung of the ladder,
exempting a genuinely local panel.

**Accepted as risk**: a DoH fallback discloses the panel hostname to Cloudflare or Google. Not a
credential, arguably better than the ISP seeing it, and it belongs in the setting's copy.

## Stage 5.5 Review: 5 CRITICAL, 12 IMPORTANT, all acted on

The reviewer saw only the plan file. Every CRITICAL was fixed before Stage 6, and one of them was
verified further than the reviewer took it.

**CRITICAL, and the reviewer was right about all five.**

1. **Nothing wired the stored setting into the live resolver.** No step read
   `XtreamCredentials.resolver`, parsed it, or handed it to the resolver the overrides use, so
   objective 2 was not deliverable as written. Step 4 now owns the whole path and names `adopt`
   (`provider_session.dart:343-357`) as the update point, because a user who changes their resolver
   would otherwise keep resolving through the old one until the process restarted.
2. **The Quad9 endpoint was wrong, and the reviewer's own fix was wrong too.** It reported a 400 on
   port 443 and proposed port 5053. Measured here: 443 answers `400 DoH unable to decode BASE64-URL`
   as reported, and **5053 times out entirely** from this connection. So Quad9 is dropped from the
   picker rather than moved, with the measurement recorded in the step, and a `Done when` now fails
   if it reappears. Cloudflare and Google both answered 200 in the same run.
3. **The `Http` facade would have shipped our own user's bearer token to the DoH resolver.**
   `app_service_provider.dart:100-107` records that magic's `AuthInterceptor` "attaches the watchools
   bearer token to every request with no host, scheme or origin test". My Must NOT had offered the
   facade as an acceptable route. It now forbids it and says why.
4. **Step 4's criteria could not be satisfied from its own Files.** Pinning the configured panel host
   needs an accessor on `ProviderSession`, whose `_credentials` is private. The file and the
   accessor's shape are named now.
5. **Step 7 had the same defect**, reading a resolver the container never held. Step 4 registers one
   singleton and step 7 takes both construction sites.

**IMPORTANT, all applied.** `HttpOverrides.createHttpClient` returning `HttpClient()` recurses
forever, verified at `dart-sdk/lib/_http/http.dart:1348-1354`, so the step now mandates
`super.createHttpClient(context)`. The docs grep matched only one of the two files, because
`CLAUDE.md` writes "no app in this category" and `stack-decisions.md` writes "no player in this
category"; the pattern now matches the tail they share, and I had caught this one myself in the
criteria audit just before the reviewer reported it. Step 9 declared itself a verification step while
requiring a source edit, so the temporary option flip is now explicit, named to its file, and
followed by a `git status --porcelain` criterion that proves it was reverted. Step 9 also had no
command that ran the app, so the overlapping-segment observation was unreachable. The coverage
criterion named an instrument that does not exist and now cites the inline Python at
`.github/workflows/ci.yml:115-143`. The insertion point for the new fields is `:171-172`, not
`_disclosure()` itself. Three cross-step pointers a worker could not follow became paths. The
timeout work was split out of the senior override step into its own `quick` step, which is why the
plan is nine steps and seven waves rather than eight and six. Step 8's tier went from `quick` to
`junior` and its file count from four to three. Step 2's `rule-5-criticality` now escalates the tier
to `junior-high` rather than sitting inside `junior`.

**Also applied, from the reviewer's Notes rather than its findings.** Steps 6 and 7 left the Turkish
copy to the worker while every other string on that screen carries a documented rationale. All four
strings are written into the plan now. And step 3's two live-network curls moved out of `Done when`,
because an endpoint being up proves nothing about the step's own code.

A `### Dependency Notes` section now records the three couplings a worker cannot see from inside its
own step. `plan-check` is clean after the last edit: 9 steps, 0 errors, 0 warnings.
