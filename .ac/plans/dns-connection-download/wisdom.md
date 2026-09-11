## Wave 1

- **[REMEDIATION] `pubspec.lock` was rewritten under the overrides and restored.** A worker running
  `flutter test` re-resolved the lock with sibling paths, exactly the trap `CLAUDE.md` records: the
  committed lock must stay the hosted-only one, and CI checks it BEFORE `pub get` because that is the
  only moment it is still the committed file. Restored with `git checkout -- pubspec.lock` at the wave
  barrier. Every later wave has to re-check it, because every worker that runs tests can do this again.
- **A line-scoped `rg` criterion cannot tell prose from code.** Step 1's fourth criterion,
  `! rg -q 'demuxer-lavf-o.*seekable'`, tripped on a COMMENT naming both option keys in one sentence,
  while the actual assignments were correct. The worker reworded the comment rather than weakening the
  check, which was the right call, but the criterion shaped the prose instead of checking the code. A
  criterion over a key/value file should anchor on the assignment, not on the line.
- **`lib/` carries zero `dart:io` imports and the web target is scaffolded.** Verified: `rg -l "import
  'dart:io'" lib/` returns nothing and `web/` exists. `HostResolver` (step 3) needs
  `InternetAddress.lookup` and `ResolvingHttpOverrides` (step 4) needs `HttpOverrides` and
  `HttpClient`, all three `dart:io`, so a bare import in either would break `flutter build web`. Both
  steps must use a conditional import with a no-op web implementation. Carried into their briefings;
  the plan did not name it.
- **Dart 3.13's `use_null_aware_elements` lint forces `'key': ?value` in a map literal.** The
  `if (x != null) 'key': x!` shape a conditional map entry would normally take is an analyzer info,
  and `--fatal-infos` makes it a failure. Worth knowing before writing the next conditional entry.
