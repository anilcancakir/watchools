# Wisdom

## Wave 1

1. **[REMEDIATION] A `@` in a provider password reached a log line intact, and only a paired test
   could see it.** `redact` enumerated `Uri.encodeComponent` and `Uri.encodeQueryComponent` after
   reading both in the Dart SDK source, which is careful work and still missed the encoding that
   matters: `Uri(pathSegments:)`, what `XtreamStreamUrl` actually builds with, escapes **less** than
   either, because `@`, `:` and `&` are legal in an RFC 3986 path segment. One password shows all
   three apart: `p@ss word` is `p%40ss%20word`, `p%40ss+word`, and `p@ss%20word` on the wire. Neither
   worker could catch it: step 1's own test used `a/b c`, whose path encoding coincides with
   `encodeComponent`, and step 2 never saw what the builder emits. **The fix is not a fourth
   hand-written form**, it is deriving the form from the same constructor the builder uses, so the
   two cannot drift; and the test asks the builder for the URL rather than hand-typing one, so a
   future divergence goes red. This is the cross-file consistency check earning its whole cost in one
   wave.

2. **`Uri(pathSegments:)` adds no leading separator when there is no authority.** The first fix
   stripped one anyway and ate the secret's first character, redacting `@ss%20word` and leaving
   `p***` in the log: a nine-tenths match that reads as success in a `isNot(contains(...))`
   assertion and would have passed a test written against the raw secret. `Uri` only makes a path
   absolute when an authority is present.

3. **The plan carried a stale claim from research written before the fix landed.** Step 1's `ts`-first
   rationale cited `tool/xtream-mock/README.md:52-92` for "the four HLS channels cannot play past the
   first loop wrap". That file records the DTS discontinuity as **fixed** at `:53-66` (31 of 32
   boundaries continuous, 128 s rather than 16 s, which is commit `04356f8` / #22), and there is no
   group of four HLS channels: `:29-36` lists eight channels of which seven serve both containers,
   and `:42-44` counts three container cases. The worker refused to write the wrong rationale into a
   doc block and re-cited `:247` and `:259`, where the argument does hold. A plan is a snapshot of
   research, and research ages inside the same repository that fixed the thing it describes.

4. **A `Done when` command has to be run against the state CI sees, not the working tree.** Step 3's
   resolved-Wind criterion greps `pubspec.lock` for the version, but a local `pub get` leaves that
   file naming sibling paths with no hosted version, so the command yielded an empty string and then
   `No such file or directory` rather than an answer. It also used `grep -A2` where the `version:`
   line sits six lines below the package name. Read the **staged** lock (`git show :pubspec.lock`)
   and widen the window.

5. **A `Done when` criterion cannot name a path outside its own step's `Files`.** Step 3's
   reachability check asked for a throwaway test under `test/`, which that step is not allowed to
   write, so the file-scope hook blocked it and the worker correctly reported `[BRIEFING GAP]` rather
   than working around the guard. Re-spawning could not have fixed it: the gap was in the plan. The
   criterion's substance was met by a stronger instrument anyway, `.dart_tool/package_config.json`
   naming both new packages, which is what wave 2's imports actually resolve through.

## Wave 2

1. **No Swift in this repository is ever compiled by CI.** `.github/workflows/ci.yml:23` and `:150`
   both run `ubuntu-latest` and there is no `flutter build macos` step anywhere, so the plugin's
   Swift is checked by reading and by nothing else. Step 4's whole deliverable is Swift, and it is
   the first `mpv_set_property` this plugin has ever made, so the orchestrator ran
   `flutter build macos --debug` by hand: exit 0, `Built build/macos/Build/Products/Debug/Watchools.app`.
   That is what proved `sampler.sync`'s multi-statement closure return type, the `guard let handle
   else` shorthand and the `FlutterError` mapping actually type-check. Any future step that writes
   Swift needs the same manual build, because a green CI says nothing about it.

2. **A subagent's transcript going idle is not a subagent finishing.** A monitor keyed to
   "transcript untouched for three minutes" fired while step 5 had written nothing and had not
   reported, because a long single tool call appends nothing until it returns. The transcript then
   grew from 412 KB to 454 KB. Liveness needs the file's SIZE over two samples, not its mtime, and
   completion needs the agent's own notification. Reading the tool-call names out of the transcript
   (`grep -o '"name":"[A-Za-z_]*"' | sort | uniq -c`) is a cheap, context-safe read of what a worker
   is actually doing.

3. **`.gitignore`'s `.swiftpm/` does not match what Xcode writes.** A macOS build leaves
   `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and
   `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` untracked, because the ignore
   rule at `.gitignore:12` has a leading dot and these paths do not. Left untracked and uncommitted
   here, since `.gitignore` is outside this plan's scope, but the next macOS build will surface them
   again.

4. **The best decision in the interface was to not create a boundary.** `PlaybackTick` is a
   `typedef` alias for the plugin's `PlayerTick` rather than a parallel class, and the reasoning is
   wave 1's lesson applied before the fact: a parallel class would need two field-for-field mappings
   (one at the plugin edge, one back to feed `StallDetector`), and a field forgotten in either does
   **not** fail loudly, because `underrun: null` means unknown-and-never-healthy, so a dropped field
   degrades into a fault verdict on a healthy stream. The cost is real and written down (a field
   added to `PlayerTick` is a field added to the interface) along with the exit condition: the day a
   second implementation cannot fill one of the nine, the alias becomes a class and the mapping is
   written once. Compare wave 1, where the boundary DID exist and did leak.

5. **A fake must not invent a verdict.** `FakePlaybackEngine.health` moves only when a tick is read,
   so `pause()` changes nothing until a tick arrives carrying `paused`, exactly as mpv behaves, and
   the fake feeds a real `StallDetector` rather than answering a verdict directly. Its own doc says
   why: "A fake that flipped its own state on a command would let a consumer's test pass against
   behaviour no real engine has", and asserting a verdict "would test this class and nothing else".
   That is the check-that-cannot-fail discipline applied to a test double, which is where it is
   easiest to forget.

## Wave 3

1. **The transport's session stamp repeats, and forwarding it would have been worse than useless.**
   `PlayerTick.session` is mpv's `playlist_entry_id`, and `MpvEngine.start` calls `mpv_create` per
   load while refusing a second while a core is alive (`MpvEngine.swift:84`, `:88`), so every load
   runs on a fresh core whose first entry id is 1 again. `StallDetector` resets its anchor on a stamp
   change, so a new channel starting at position 0 after one that reached 300 would read as a
   position going backwards **inside one session**: a freeze verdict on a healthy stream. The engine
   stamps its own `_generation`, which the interface's first promise explicitly permits. Step 5 left
   this as an unverified assumption and said so; step 6 settled it from source rather than inheriting
   it.

2. **[REMEDIATION] Do not touch a file a worker still owns.** Mid-run I edited
   `mpv_playback_engine.dart` to fix a `prefer_initializing_formals` info while step 6 was still
   working. The worker overwrote my edit, my scoped analyze and my full analyze then measured two
   different trees, and I briefly concluded from that that a private initializing formal was illegal
   as a named parameter. It is not: Dart spells `required this._redact` as `redact:` at the call
   site, which is what the worker independently worked out and documented. The worker also noticed
   the interference and reported it. Same rule for the test suite: a `flutter test` of mine collided
   with the worker's and both lost the startup lock. **A running worker owns its Files and the
   `flutter` lock; wait for the report.**

3. **magic's log facade silently downgrades an unknown level.** `ConsoleLoggerDriver.log` scores
   `_levels[level] ?? 7` (`~/Code/fluttersdk/magic/lib/src/logging/drivers/console_logger_driver.dart:42`),
   so `Log.log('warn', ...)` is filed as debug and printed through `_logger.d`. mpv spells its levels
   `fatal`, `error` and `warn`, so forwarding mpv's own spelling would file every FFmpeg reconnect
   warning below the level a release build prints, and that warning is the **only** signal a
   subscription token is lapsing. Worked around in app code by mapping to `Log.error` / `Log.warning`;
   the fix in the sibling is Laravel's, which throws on a level outside RFC 5424 rather than
   downgrading it, because a silent severity downgrade on a fault channel is the one direction that
   hides a fault.

4. **A test can pass under the mutation it was written to catch.** Step 6's first dispose test pushed
   a tick after `dispose()` and asserted nobody received it, which passed with `_upstream.cancel()`
   deleted, because a closed session refuses the tick on its own. It now pushes a **log line**, which
   only the subscription gates. The worker found this by deleting the line and re-running rather than
   by reading. Step 7 then did the same for each wakelock release. Mutation-checking a new test is
   cheap and it is the only thing that distinguishes an assertion from a guarantee.

5. **An out-of-scope doc edit landed in `fake_playback_engine.dart`** during wave 3, in a file no
   wave-3 step declared and which neither worker reported. Three lines, comment only: the example's
   `timePos: 10` became `10.0` with a note that nine fields are required. Kept rather than reverted,
   because the original example was a sketch containing `...` and the new one is more accurate, but
   it is recorded here because the attribution check is what found it and nothing else would have.

## Wave 4

1. **A step's `Description` can require a method the plan never gave anyone permission to write.**
   Step 8 was told to derive the URL "from `ProviderSession`'s credentials and account", and that
   class holds both as private fields with no accessor, while `provider_session.dart` was in no
   step's Files list. The worker found it, reported `[CONTRADICTION]` and wrote nothing, which is
   exactly right: the next attempt hits the same wall, so re-spawning cannot fix a gap that is in
   the plan. The resolution was a user decision between two shapes, and the one chosen keeps the
   credential inside the session: `streamUrlFor(Channel)` hands out a finished `Uri`, so the
   playback layer imports no Xtream at all and the secret's blast radius does not widen.

2. **[REMEDIATION] I wrote a redactor that redacted nothing.** Wiring the engine at the composition
   root, I produced an expression whose two branches were both identity functions. It analyzed
   clean, it would have passed every test, and it would have shipped the exact hole this plan exists
   to close: mpv's log lines reaching a diagnostic with the subscription password intact. The fix is
   `ProviderSession.redactProviderSecrets`, so the session hands out the redaction **behaviour**
   while the credential stays private, and the engine takes it as a function it cannot see behind.
   A security control that is wired rather than tested is a control that is assumed.

3. **[REMEDIATION] I wrote `// ignore: prefer_initializing_formals`.** `CLAUDE.md` forbids linter
   suppression outright, and I had spent the whole run holding workers to it. Reverted and fixed
   properly with `required this._engine`. The rule is not harder to follow than the suppression; it
   is just less immediate.

4. **Constructing a platform-touching object in `register()` breaks every test that boots the
   providers.** `MpvPlaybackEngine`'s constructor subscribes to the plugin's `EventChannel`, which
   reaches `ServicesBinding.instance`, so an eager build threw `Binding has not yet been
   initialized` in `xtream_client_test.dart`, which is the provider driver's own **security** test
   and has no widget binding by design. The controller now takes a `PlaybackEngine Function()` and
   resolves it on first use, which also moved the tick subscription out of the constructor. Two
   getters (`health`, and the stop inside `onClose`) read the **resolved** engine rather than
   forcing a build, because a getter that subscribes to a platform channel is the side effect the
   step's own Must NOT forbids.

5. **A cached health verdict is wrong for a microtask.** The engine settles its verdict when it
   accepts a tick, but `ticks` is a broadcast stream and the listener runs a microtask later, so a
   controller that cached the value reported the previous verdict to anything reading in between.
   `health` reads through to the engine and the remembered value exists only to decide whether to
   repaint. The same asymmetry is why the notification test has to drain the queue: without it the
   count measures scheduling rather than the controller.

6. **The connection gate reads `!= idle`, not `== playing`.** A paused, starving, stalled or
   not-presenting core is still an open core holding the one connection the measured account allows.
   `== playing` would let a catalogue refresh evict a viewer who had merely paused, which is the
   precise failure the injectable predicate was built to prevent.

## Wave 5

1. **`Zaman` was deliberately left reaching playback only through `Şimdi`**, which the step's own
   text permits and which I am recording rather than burying. `TimeLayout` has no hero and no empty
   play callback: it carries `selectChannel` (`:362`) and `selectProgramme` (`:507`), both of which a
   viewer uses to move around the grid. Repurposing either would take a navigation away from a
   control that has a job, and the honest alternatives (a long press, a dedicated affordance in each
   programme cell) are a design decision rather than a wiring one. The grid is one tap from `Şimdi`
   on the toolbar switch, so nothing is unreachable.

2. **A widget test cannot pop a route or resolve a container**, so two controls needed a seam.
   `MagicRouter` throws `Router not initialized` without a `MaterialApp.router` above it, and
   `pumpScreen` collects `FlutterError`s rather than swallowing them, so the back affordance failed
   its own test until `onBack` existed. `NowLayout.onPlay` is the same shape for the same reason.
   Both default to the real thing, so production wiring is unchanged; the alternative was leaving
   the one control that reaches playback as the only untested control on the screen. On a surface
   where gestures never reach the platform view, a control that silently does nothing is invisible.

3. **`/izle` carries no identifier, and the reason is sharper than `/baslik`'s.** The controller
   already holds the channel the user chose. A `streamId` in the path would make a URL that reopens
   a provider stream on a cold start, before any handshake has said the account is still active, and
   against an account whose measured connection limit is one. Playback is reached by choosing
   something, never by arriving at an address.

4. **`PlaybackFacade` lives beside the controller, not in the UI layer.** Dart has no structural
   typing, so a UI-side interface would have forced the controller to import the UI to implement it.
   I wrote "satisfies it structurally" in a doc block first, which is simply false for Dart, and the
   analyzer said so. The interface sits in the controller's own file, the controller declares
   `implements PlaybackFacade`, and the layout imports it from there, which is what the other three
   layouts already do with their controllers.

5. **The stack's order is asserted, not assumed.** A control behind the platform view is invisible
   to a tap on macOS and silent in a widget test, so the test reads `Stack.children` and asserts the
   view sits at index 0. Mutation-checked by moving a scrim above the view: red. The pause wiring was
   mutation-checked the same way.

## Wave 6

1. **The measurement found something it was not looking for, and it is the sharper result.** Step 12
   asked whether the mock re-mints a stream token per request; it does, and the two `Location`
   headers differ only in a timestamp. But the token is **base64**, and decoding it gives
   `username:password:issuedAt`. So the tokenised URL still carries the credential, and neither
   redaction path removes it: `describe(Uri)` replaces a path segment only when the segment
   **equals** a secret, and `redact(String)` looks for the raw secret plus three encodings, none of
   which is a base64 blob containing no literal secret. Reachable rather than theoretical, because
   mpv follows the redirect and FFmpeg's reconnect warning names the URL it is retrying, which is
   the one log line the design depends on and cannot switch off. Filed in `## Deferred Ideas` with
   the shape of the fix: recognise a base64-looking segment whose decoding contains either secret,
   rather than enumerate a fourth spelling.

2. **Coverage held because the fake was a deliverable, not because it was lucky.** The denominator
   moved from 2239 lines to 2486 as this plan added `lib/app/playback/` and the controller to it,
   and the ratio came out at 2387/2486 = 96.0% against a 90% floor. Decision D2 accepted the risk
   that the macOS implementation's untestable lines would count against the floor; `FakePlaybackEngine`
   is why it did not come due. Read the printed `hit/found` rather than the percentage: lcov carries
   only files the tests import, so a red run can be a moved denominator rather than a regression.

3. **A verification step's own gate can be the wrong instrument.** Step 13's lock criterion has to
   read HEAD rather than the working tree, because a local `pub get` with the overrides active
   rewrites the lock and every gate after it passes over the rewritten file rather than failing on
   it. Measured against HEAD the counts are 1 and 1, equal, which is what CI compares; measured
   against the working tree they are 8 and 1. Same command, opposite verdict, and only one of them
   is about what will be pushed.

## Review and oracle rounds

1. **The deferred idea from wave 6 turned out to be two defects, and the one it named was the
   smaller.** Wave 6 filed "recognise a base64 segment whose decoding contains a secret" as the fix
   for the tokenised URL. Implementing it found that the guard could not have worked for a real
   token anyway: a token is commonly a readable payload plus a **binary** signature, and one invalid
   UTF-8 byte made the strict `utf8.decode` throw, so the whole run was left alone with the
   credential in plain ASCII at its front. `allowMalformed: true` is the correct setting, because
   the guard that protects innocent text is the containment check rather than the decode's
   strictness. And the first version of the escape fix still leaked: `=` was in the run's character
   class, so a match reached backwards through a query parameter's `token=` and the joined run has
   invalid mid-string padding, decodes to nothing, and is returned verbatim. Padding belongs in its
   own trailing group, which is what base64 means by it.

2. **A guard on a long async sequence has to be re-read, not just entered.** `ProviderSession.refresh`
   consulted the playback gate once, at the top, and then ran a handshake, four list fetches and up
   to `epgFetchLimit` sequential EPG calls unguarded. The question "may I start" and the question
   "may I continue" are different, and only the first was being asked. Not an edge case either:
   `boot()` fires the refresh unawaited at cold start, so **every launch** puts that batch in flight
   and a user tapping a channel seconds in plays straight through it, on an account whose measured
   `max_connections` is 1. Where to re-check is decided by the transaction boundaries: between the
   two halves and between EPG round trips, never inside a `replace*`, because abandoning
   mid-transaction leaves the catalogue half written.

3. **A silence in a platform channel is a defect with three faces.** `WatchoolsPlayerPlugin.swift`
   stops the core when it prunes the attached platform view and tells Dart nothing. From that one
   silence: the second visit to the screen sent a forgotten view id, the connection gate latched
   shut for the life of the process, and the wakelock outlived its core. All three were fixed by one
   `detach()` from the view State's `dispose`, and none of them was reachable by any widget test.
   The generalisation for the five engines still to come: when the platform can tear something down
   without saying so, the consumer needs a signal at the boundary that owns the resource, and the
   interface needs to promise that a redundant teardown is safe. That promise is now written down,
   because it currently holds only by accident of mpv's nil guard.

4. **Two defects this round were visible only by looking.** A back affordance shipped stretched into
   a pill across the whole window, because a column stretches its children across the cross axis and
   `findsOneWidget` on a semantics label passes at either width. And a controller fix that kept the
   channel through a refusal bought nothing on screen, because the layout's branch replaced the
   channel name instead of adding to it. Both were found by starting the app and taking a
   screenshot. The lesson is not "write more tests": it is that a test asserts the thing you thought
   to assert, and a screenshot shows the thing you did not.

5. **A passing test is not evidence; a test proved to fail is.** Both fixes above got an assertion,
   and both assertions were then checked by removing the fix and watching them fail (40 by 40
   against 1392 by 40; one EPG request against three). This run caught vacuous tests in workers four
   times and in my own work twice, and the cheap discipline that would have caught all six is to
   break the code once on purpose before believing the green.
