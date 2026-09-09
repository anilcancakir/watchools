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
