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
