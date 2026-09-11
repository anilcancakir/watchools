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

## Wave 2

- **Both shipped DoH endpoints return CNAME records inside `Answer`.** Measured by the worker against
  `www.wikipedia.org` on Cloudflare and Google alike: a `type: 5` record whose `data` is a hostname,
  not an address. A parser taking `Answer[0].data` would hand `dyna.wikimedia.org.` to the caller as
  an address. Records are filtered to `type == 1` and the resolver additionally refuses anything that
  does not parse as an IP literal, so the leak is closed twice. A test covers the shape.
- **`flutter build web` is the only gate on the conditional-export seam.** CI never builds web, and
  `flutter analyze` does not see a platform-library violation, so a bare `dart:io` import in `lib/`
  would have shipped silently. The worker ran the web build itself and it passed. Any later wave that
  touches `lib/app/network/` has to run it again.
- **[REMEDIATION] A doc block claimed a wider range than its code checked.** `_isBlackhole` said
  `0.0.0.0/8 unspecified` while the code matched only the single address `0.0.0.0`. Corrected the
  comment rather than widening the code, because widening is a behaviour change no test covers, and
  recorded why in the comment itself.
- **magic gap, read at source before filing**: `magic/lib/src/auth/auth_interceptor.dart:17-33` sets
  `request.headers[header] = '$prefix $token'` for any request whenever `guard.cachedToken` is
  non-empty, with no host, scheme or origin test. So any third-party call through the `Http` facade
  ships our own user's bearer token to that third party. Local opt-out here is a plain `HttpClient`
  for the DoH rung. The fix in magic is an origin allowlist on the interceptor, or at minimum
  attaching only when the request URI's origin matches the configured API base. Report this in the
  pull request per `CLAUDE.md`'s ecosystem rule.
