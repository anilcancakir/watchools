# Wisdom

## Wave 1

1. **[REMEDIATION] `decodeBody` alone could not read seven of the ten actions.** Step 2's
   Description named "an already-decoded `Map` or a raw `String`", but the three category
   actions, the series list, the two stream lists and the EPG table all answer with a JSON
   **array** (`tool/xtream-mock/server.mjs:255-280`). A `Map?`-returning reader returns null for
   every one of them, so step 4 would have had no sanctioned decode path for the bulk of the
   protocol and would have reached for a bare `jsonDecode`, losing the `text/html` hedge that is
   the whole reason the reader exists. Added `decodeEntries` beside it in the file that owns
   decoding, with six tests including the empty-array case, which is distinct from unreadable
   because an unknown action and an empty category both legitimately return `[]`.

   **Correction, from step 4 and verified at source.** The split is **six arrays and four
   objects**, not the "seven including the EPG table" this item first said. Arrays: the three
   category actions, `get_series`, `get_live_streams`, `get_vod_streams`. Objects: the handshake,
   `get_vod_info`, and **both EPG actions**, which wrap their array in an envelope,
   `{ epg_listings: [...] }` (`server.mjs:322`, `:331-338`). So an EPG answer is
   `decodeEntries(decodeBody(body)?['epg_listings'])`, and a step that took the first version of
   this item literally would have read `null` for every EPG response. Step 8's short-EPG pass is
   the consumer that would have hit it.

2. **[REMEDIATION] A pasted `http://user:pass@host:8080` put a password inside `baseUrl`.**
   `XtreamCredentials.toString()` prints `baseUrl` in full, and the first draft's rejection used
   `ArgumentError.value(normalised, ...)`, which interpolates the very string that may carry the
   secret. Both paths violated step 1's own `Must NOT`. The constructor now rejects a non-empty
   `userInfo` outright (Xtream sends the credential as query parameters, so an authority
   credential is malformed input rather than a supported shape) and neither rejection message
   interpolates the value.

3. **magic resolves dio 5.9.2, not the 5.11.1 the plan cited.** All three links of the
   header-case evidence chain hold at the resolved version; only `options.dart` moved from `:152`
   to `:151`. Re-verify a pub-cache line number against the version the target repository
   actually locks, not against the newest one on disk: six dio versions are cached here.

4. **The header-case requirement is unmeetable on web by construction.** `preserveHeaderCase` is
   forwarded only by dio's IO adapter (`io_adapter.dart:109`, present in every cached version).
   The web adapter writes headers through `xhr.setRequestHeader`, a browser API with no
   case-preservation hook at all. So `User-Agent` survives on macOS, iOS, Android, Windows and
   Linux, and cannot on web. That is a platform limitation rather than a magic gap, and it does
   not widen PR #151.

5. **Two instruments and two frictions worth carrying forward.** An `HttpHeaders`-based
   assertion cannot prove header case, because the receiving side lowercases on parse regardless
   of what went on the wire; only a raw socket read can, which is what
   `magic/test/network/preserve_header_case_test.dart` does. And every `flutter test` run
   re-triggers `pub get`, which rewrites `pubspec.lock` with 7 `source: path` entries and
   regenerates `macos/Flutter/GeneratedPluginRegistrant.swift`: both need restoring at every
   wave barrier, which is exactly the failure `CLAUDE.md` records going green through a whole
   pipeline. The file-scope hook also accepts only literal paths, so a directory entry in
   `wave_files` does not authorise a new file inside it.

## Wave 2

6. **[REMEDIATION] Step 9 had to run in wave 2 rather than wave 4.** `provider_notice.dart:81`'s
   `switch` on `ProviderFault` is exhaustive by design, and its own comment says so, so the moment
   step 5 added `evicted` the repository stopped compiling: `test/ui/components/provider_notice_test.dart`,
   `test/config/app_config_test.dart` and `test/ui/preview_catalogue_test.dart` all failed to load,
   the last two because they transitively register the preview catalogue. The plan's Dependency
   Notes recorded "step 9 needs step 5" and then placed them two waves apart, which is a dependency
   in the wrong direction: an enum member and its exhaustive consumer have to land in the same
   barrier or every wave between them commits a tree that does not build.

7. **[REMEDIATION] Steps 5 and 9 contradicted each other over one sentence.** Step 5 narrowed
   `throttled`'s enum doc to hand the connection case to `evicted`, while step 9's `Must NOT` said
   not to change what `throttled` renders, and what it rendered was exactly that story
   ("Aboneliğiniz başka bir cihazda açık olabilir"). Leaving both intact would have shipped two
   faults telling the user the same thing, making the split invisible on screen and pointless.
   Resolved by scoping the exception to `throttled`'s body copy alone: icon, title, verb, disc and
   position untouched.

8. **[REMEDIATION] `atConnectionLimit` read an absent limit as a reached one.** `maxConnections`
   defaults to `0` on a drifted or missing `max_connections`, and `activeConnections >= maxConnections`
   then made `0 >= 0` true, routing a **healthy** account to `evicted`, whose panel blames a device
   that may not exist and whose retry is deliberately withheld. Guarded on `maxConnections > 0`.
   The rule this generalises to: when two classifications differ in whether their remedy is safe,
   ignorance resolves toward the safe one.

9. **A fake that removes the mechanism under test turns a security assertion green for the wrong
   reason.** `Auth.fake()` installs a `FakeAuthManager` whose guard is `_FakeGuard` rather than a
   `BaseGuard`, so `cachedToken` never exists and `AuthInterceptor` would find nothing to attach:
   the "no `Authorization` header reaches the panel" test would have passed against a driver that
   leaks. Step 4 used a real `BearerTokenGuard` over `Vault.fake()` and asserted `cachedToken`
   inside the seeding helper so the seam cannot silently go dead. It then added the control that
   actually makes the gate meaningful: the same request through a driver that **does** carry
   `AuthInterceptor`, asserting the token IS on the wire. A negative assertion with no positive
   control beside it cannot distinguish "secure" from "rig broken".

10. **`Http.fake()` fakes the `network` key only, and `FakeNetworkDriver` runs no interceptors at
    all.** It builds its `MagicRequest` records from its own arguments, so every header assertion
    against it reflects what the caller passed rather than what would go on the wire. Split the
    questions: wire behaviour (a header's presence, its case, a followed redirect) needs a loopback
    `ServerSocket`; request shape (query keys, an absent `action`, an absent pagination parameter)
    is what the fake is genuinely good for. Separately, `./bin/fsa previews:refresh` writes
    `lib/_previews.g.dart` in a shape `dart format --output=none --set-exit-if-changed lib test`
    rejects, so running the generator breaks step 14's format gate until the file is re-formatted;
    the content is identical once it is.

## User decisions taken during execution

**The clock, asked and answered at the wave 4 boundary.** Real EPG and the app's default clock
disagree by construction. `GuideClock.minute` is minutes since the **schedule's** midnight and the
default is `FixedGuideClock` at 20:12 (minute 1212), a fixture-relative fiction, while
`Programme.fromXtream` computes its minutes from a real reference midnight. A provider programme
airing at 14:30 is minute 870 against a clock reporting 1212, so `ChannelStatus` reads `idle` for
every channel actually on air and the grid's now line sits at 20:12 over nothing. `CLAUDE.md` says
the fixed clock "stays the default until real EPG arrives", and step 8 is that arrival.

Chosen: **a real anchored clock on the provider path, `FixedGuideClock` on the fixture path.**
`TickingGuideClock(anchor: now.difference(localMidnight).inMinutes)` with the same midnight fed to
`Programme.fromXtream`, so both halves of the unit share one frame. No new clock code: the ticking
clock was already written, already tested against virtual time, and already takes that anchor.

**The follow-up this creates, deliberately not fixed here.** A clock that moves makes
`GuideController.windowStart` teleport: it advances thirty minutes at every half-hour boundary, so
the grid shifts 180 pixels and the now line jumps back from 354 to 180 in one frame, possibly under
a viewer mid-scroll. `CLAUDE.md` records it as latent "only because the default clock does not
move", and it is no longer latent on the provider path. The cheap answer it names is a sticky
window: hold the current `windowStart` and advance it when `now` nears the far edge. Out of scope
for this plan, and it belongs in the same change as anything else that touches the grid's scroll
behaviour.

## Wave 3

11. **[REMEDIATION] Neither `Channel` nor `TitleItem` carried a provider identifier, and the plan
    never noticed.** Both types were built for a design phase that only had to render, so between
    them they had `number, name, group, status, logoUrl, schedule, facts, favourite` and
    `kind, name, category, year, posterUrl, backdropUrl, minutes, rating, genres, synopsis, facts,
    cast, episodes, progress, favourite`, and not one ID. Three things immediately downstream need
    one: the store writes columns "to rebuild a value object", `get_short_epg` is keyed on
    `stream_id`, and `/baslik/:id` needs to know **which** ID space a number came from, since
    `stream_id` and `series_id` collide numerically. Added in step 6 as `Channel.streamId` and
    `TitleItem.providerId` (the space read off the existing `kind`), both **nullable** so the
    fixture path and every hand-built test object keep compiling. Adding it one step later would
    have been a store migration.

12. **[REMEDIATION] The catch-up columns the plan asked for had nowhere to live.** Step 7's
    Description says carry `tv_archive` and `tv_archive_duration` "as columns from day one so
    `ChannelStatus.catchup` stays computable and no migration follows", but its `Files` cannot
    touch `channel.dart` and step 6's factory read neither field, having concluded the archive
    state was inaccessible. It is not: `server.mjs:214,216` put both on every `get_live_streams`
    entry. Folded into one nullable `Channel.catchupDays`, with `tv_archive` as the authority
    because a panel can send a non-zero duration beside a zero flag. One column instead of two,
    since the model is what the store rebuilds.

13. **A value type's `copyWith`-shaped method is where a new field silently disappears.**
    `Channel.toggleFavourite()` rebuilds the whole object field by field, so every field added to
    the class has to be added there too or starring a channel quietly nulls it. Both new fields are
    covered by a test that stars a channel and asserts they survive, because the failure is
    invisible: the object is still valid, just orphaned from its provider.

14. **The Magic ORM works headless under `flutter test`, now proven rather than assumed.** No test
    in this repository had ever touched it. `DatabaseManager().setConnection(sqlite3.openInMemory())`
    is magic's own seam (`database_manager.dart:75`) and reaches the system libsqlite3 with no
    plugin registrant and no `sqlite3_flutter_libs`. Resolved versions: `sqlite3` 3.5.2, libsqlite3
    3.53.4.

15. **Two SQLite facts worth not taking on faith.** The `sqlite3_exec` routing claim **holds** at
    the resolved version (`sqlite3-3.5.2/lib/src/implementation/database.dart:287`), so passing a
    non-empty params list really is the anti-stacking defence rather than a style preference. And
    the bound-variable cap is **32,766** on this build, not the 999 that most advice still repeats:
    32,767 answers "too many SQL variables", and 32,766 hits the separate SELECT column cap first.
    Measured by preparing N placeholders. That is why the store needs no chunking at all: one row
    per `execute` binds 9 or 15 variables, so the cap is unreachable and there is no row count to
    guess, which removes the exact temptation the plan's `Must NOT` was written to guard.

## Wave 4

16. **[REMEDIATION] `boot()` awaiting the network refresh would have held a blank window open for
    the whole catalogue fetch.** `AppServiceProvider.boot()` runs inside `Magic.init()`, which
    `main()` awaits before `runApp()`, so anything awaited there delays the first frame by its own
    duration. `start()` as written did the vault read, the cache restore **and** `await refresh()`,
    which is a handshake plus 2,976 channels plus 38,247 titles plus up to twenty sequential EPG
    round trips on an account whose measured `max_connections` is 1. The suite could not see it:
    the test vault is empty at boot, so `start()` returned after one read. Split into an awaited
    local `start()` and an unawaited `refresh()`, which is also what the cold-start cache exists
    for. **Thirteen tests went red on the split**, which is the proof the behaviour really changed
    rather than the shape.

17. **The playback gate's own test became unfalsifiable in the process, for a moment.** It asserted
    `assertSentCount(0)` after `await session.start()`, relying on `start()` triggering the refresh
    the gate then blocked. Once `start()` stopped refreshing, nothing tried to send and the
    assertion passed for the wrong reason. It now calls `refresh()` explicitly, with a comment
    saying why. The general shape: a gate test that depends on an implicit trigger silently retires
    the moment that trigger moves.

18. **[REMEDIATION] The plan's own locked D4 decision put the series list in v1 and no step
    implemented it.** D4 says "In: the `get_series` list (so `/baslik/:id` knows both ID spaces from
    the start, the one omission the oracle says costs an interface change later)", but step 8's
    Description only names the VOD catalogue and my briefing listed `seriesCategories()` and
    `series()` among the client's methods without ever telling the worker to call them. The worker
    correctly reported that as a briefing gap rather than inventing scope. Added a second pass over
    the series space, with a test proving a movie `stream_id` 500 and a series `series_id` 500 stay
    two distinct titles with independent favourites, which is the collision the oracle said a
    movies-only v1 would cost a store migration to undo later.

19. **A value type with no `copyWith` makes every field addition a liability twice over.**
    `TitleItem` has only `toggleFavourite`, so the session had to reconstruct the whole object
    through its public constructor to change `progress`. That is now the third place (with
    `Channel.toggleFavourite` and `TitleItem.toggleFavourite`) where adding a field and forgetting
    one line produces a valid object with silently dropped state. Worth a real `copyWith` on both
    types the next time either is touched.

## Wave 5

20. **[REMEDIATION] The real clock was half-delivered: right value, no repaint.** Step 10 wired
    `now => (_session.clock ?? clock).minute`, which reads the anchored clock correctly, but the
    controller's `_onTick` stayed subscribed to the `FixedGuideClock` it was constructed with,
    because the session's clock does not exist yet at construction time. Reading the right minute
    is not the same as being told when it changes: every progress bar, the countdown and the grid's
    now line would have sat at whatever minute some unrelated rebuild last caught. Added
    `_followSessionClock()`, called from the existing `_syncWithSession()`, which moves the
    subscription and never disposes what it detaches from (the session owns that instance and
    re-anchors it across a calendar day). Mutation-checked: removing the one call makes exactly
    that test red.

21. **[REMEDIATION, and the briefing was mine] Step 11 correctly refused to start.** Its briefing
    said the retry callback "already exists on the controller: look for the reload or refresh
    method the `GuideEmpty` / `LibraryEmpty` components already call". No such method existed on
    either controller, and both empty components render static copy with no callback at all, which
    the worker established by reading all four files. `ProviderNotice.onRetry` is required, so the
    arm could not compile. It reported a `[CONTRADICTION]`, made **no edits**, and named the two
    ways forward it was not authorised to take. That is the protocol working exactly as intended,
    and the alternative would have been either a Must-NOT violation or a layout reaching past its
    controller into `ProviderSession`. Fixed by adding `reload()` to both controllers, which is
    where it structurally belongs: the screens read their state from the controller, so a widget
    calling the session directly would give one screen two sources of truth.

22. **A nullable-ising change breaks compilation in the NEXT step's files, twice now.** Making
    `GuideController.channel` and `LibraryController.selected` nullable was required (three `late …
    .first` initialisers threw on an empty provider catalogue) and left `now_layout.dart:121`
    uncompilable, taking four test files down with it. This is the same shape as `ProviderFault.evicted`
    breaking `provider_notice.dart`'s exhaustive switch two waves earlier. The lesson for a plan
    rather than for a worker: when a step widens or nullables a type, the steps that consume it
    belong in the same wave, or every barrier in between commits a tree that does not build.

23. **`tool/dusk/perf.sh` was not run, and the substitute is weaker.** Step 10's fourth `Done when`
    asks for it, but it launches a real app through `fsa start` and `CLAUDE.md` warns that an
    `fsa` call from a worktree can silently drive the main checkout instead. The worker substituted
    a checkable proof that both scale defines still reach `FixtureScale` and said so rather than
    claiming the run. Recorded here because the harness path is exactly the thing that fails
    silently: a hand-started app carries the small fixture and every session then measures the
    wrong thing and reports it as fast.

24. **`groups` and `categories` had no defined provider-side answer.** The fixtures have a curated
    `guideGroups` list; a provider catalogue has none. Step 10 synthesised `Tümü` / `Favoriler`
    (plus `İzlemeye devam et` on the library side) followed by every distinct group in
    first-appearance order, which matches the QA's own wording and is the only shape that keeps
    `matches`'s filter and the category strip agreeing. Worth knowing it was a judgment call rather
    than a specified one, because a curated ordering is the kind of thing a product decision could
    later want.

## Wave 6

25. **The plan claimed the mock's README listed four behaviours as absent. It never did.** Step 12
    read the whole 240-line file, grepped for the phrasing, found nothing, and reported the
    discrepancy instead of quietly editing something else or claiming the criterion met. The claim
    came from the plan's own prose, which I passed through verbatim as a briefing. The criterion is
    satisfied in substance (nothing states them as absent, and all four accounts are now documented
    as present), but the general lesson is that a plan's description of a file is a claim about that
    file, and it inherits no authority from being in the plan.

26. **[REMEDIATION] The coverage gate found a security assertion nobody had written.**
    `xtream_account.dart` measured 27/51, and every one of the 24 missing lines was `==`,
    `hashCode` or `toString`. That is easy to dismiss as convention code, except the account is
    parsed from a handshake whose `user_info` **echoes the username and password back**
    (`server.mjs:151-152`), the model strips both on receipt because magic_devtools' telescope
    records the first 8 KiB of every response body, and nothing tested that the stripping worked.
    Now 51/51, with the strip asserted directly and `listEquals` on the output formats covered.
    The lesson: a low-coverage file whose gaps are all "boilerplate" is worth one look at what the
    boilerplate is adjacent to.

27. **I reported a failing gate that was a stale read.** I read step 12's evidence file while the
    worker was still writing it, saw 55 checks and a dead panel, and said the gate had not passed.
    It had: the finished file shows 77 and "All checks passed", confirmed by my own independent
    run. Two corrections follow. An evidence file is only evidence once its writer has returned,
    and an `EADDRINUSE` from a fixture that binds a fixed port usually means two runs overlapping
    rather than a leak, which I checked before filing it as a defect and which turned out to be
    exactly that: the verifier does release 3399 on a clean exit.
