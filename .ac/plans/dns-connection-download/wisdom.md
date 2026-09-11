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

## Wave 3

- **The mock's request log carries no timestamp, which step 9's evidence criterion assumes.**
  `tool/xtream-mock/server.mjs:954` prints `console.log(`${request.method} ${path}${url.search}`)` and
  nothing else, so the log shows the ORDER of segment requests and not whether two overlapped. Two
  sequential requests and two concurrent ones produce an identical line sequence. Step 9 must
  timestamp the capture from outside rather than trusting the log as it stands, and the mock itself is
  in no step's `Files` so editing it would be out of scope. The workable shape: pipe the mock's stdout
  through a timestamper on receipt and read the CADENCE rather than looking for an explicit overlap
  marker. With `http_multiple` applied the segment requests arrive roughly one per segment duration;
  with it ignored FFmpeg opens the next segment while still reading the current one, so they arrive in
  pairs. The pairing is the observable, and the control run is what makes it legible.
- **The `HttpOverrides` route is verified at dio's source, and it has a timing condition.**
  `dio-5.9.2/lib/src/adapters/io_adapter.dart:246` constructs `HttpClient()` with no arguments when no
  `createHttpClient` was supplied, and that factory reads `HttpOverrides.current`
  (`dart-sdk/lib/_http/http.dart:1348-1354`), so the override genuinely reaches dio's provider
  traffic. But `:226` caches the client (`_cachedHttpClient ??= _createHttpClient()`), so
  `HttpOverrides.global` has to be assigned BEFORE the first request through that driver. Assigning it
  during `AppServiceProvider` registration satisfies that, because `Magic.init()` completes before
  `runApp()`; assigning it lazily on first use would not, and the failure would be silent, one dead
  feature and no error.
- **Step 5's premise was refuted before it ran, and the step is dropped.** It said the
  `provider_network` driver carries no timeout. magic's `DioNetworkDriver` constructor
  (`magic/lib/src/network/drivers/dio_network_driver.dart:18-27`) declares `this.timeout = 10000` and
  builds `BaseOptions(connectTimeout: ..., receiveTimeout: ...)` from it, and
  `app_service_provider.dart:119` constructs the driver without passing one, so BOTH timeouts are
  already 10000 ms. The Stage 1 explore reached the wrong conclusion honestly: it read the
  `configureDriver` closure, saw only `followRedirects`, and never opened the constructor. The
  objective the step existed for is already met, so writing the line would restate a default and its
  test would be green before the edit. Surfaced to the user as a plan-spec question; no answer inside
  the wait, so it takes the recommended option. The lesson is narrower than "check the constructor":
  a report that says a thing is ABSENT is the claim most worth opening the file over, because absence
  is what a reader concludes from not having looked in the right place.
- **The TLS fixture depends on OpenSSL 3.x rather than on whatever `openssl` a Mac ships.**
  `resolving_http_overrides_test.dart` generates its certificate with `-addext
  subjectAltName=DNS:...` and signs it with `-copy_extensions copy`, and that second flag does not
  exist in LibreSSL, which is what bare macOS puts on `PATH`. Here it resolves to Homebrew's
  `/opt/homebrew/bin/openssl` 3.6.2 and CI runs `ubuntu-latest` with OpenSSL 3, so both pass; a
  contributor on a Mac without Homebrew openssl would see the SAN silently dropped and the handshake
  fail with `CERTIFICATE_VERIFY_FAILED`, which reads as a bug in the code under test rather than in
  the fixture. The SAN itself is not optional: BoringSSL, which `dart:io` verifies with, ignores the
  common name entirely.
- **[REMEDIATION] `signOut()` kept the address resolved for the panel being left.** Every other line
  in that method drops a piece of the departed account's state, including `_inFlight` with a comment
  explaining why it matters even though nothing signed out will refresh. The resolver cache was the
  one piece left behind. Behaviourally it was already closed, because `providerResolution` goes null
  and the override then pins nothing, but the entry survived as a live address for a panel the user
  no longer has. One line, `_pushResolverSetting()`, plus a test proved to discriminate: with the
  line removed the test returns `203.0.113.5` from the cache instead of null.
- **The TLS discrimination test the QA asked for was written and it works.** A certificate is
  accepted against the NAME and refused against the ADDRESS, which is the whole content of the
  `host:` argument on `SecureSocket.secure`. That was the hardest requirement in the plan and the
  reason this wave took as long as it did.
- **`_defaultConnect` reproduces the SDK's own path and was checked against it line by line.**
  `dart-sdk/lib/_http/http_impl.dart:2684-2703` is
  `isSecure && proxy.isDirect ? SecureSocket.startConnect(host, port, context:, onBadCertificate:, keyLog:) : Socket.startConnect(host, port)`.
  The override reproduces all three branches and deliberately drops the two TLS hooks; a repo-wide
  grep confirms nothing in this app or in magic sets either, so the omission is safe TODAY. It is
  worth knowing that installing a `connectionFactory` disables both process-wide, because the next
  contributor who reaches for `badCertificateCallback` will find it silently ignored.
