
## Run 2026-09-11T03:30:00Z

### Oracle (criticality surfaces: a user-typed socket destination, and where TLS starts)

Four of its six premises CONFIRMED with source quotes, including the two that mattered most: the
hand-written `_defaultConnect` matches `http_impl.dart:2693-2701` on all three branches, and
`SecureSocket.secure(socket, host:)` is documented at `secure_socket.dart:115-117` and `:145` as
doing exactly what the override relies on. It went further than the brief and checked
`RawSecureSocket.startConnect` at `:334-347`, which turns out to be the same shape the override
uses, so the cancellation semantics are the SDK's own rather than newly invented.

**One premise REFUTED, and it was mine.** I had written, in the plan and then into the settings
copy, that the resolver misses playback because the panel answers a `302` to another origin. That is
not the reason. A stream URL is built on the panel's OWN host (`xtream_stream_url.dart:113-122`), so
playback's first request already goes to the name the user picked a resolver for, and libmpv
resolves it through `getaddrinfo` before any redirect exists. The consequence for a user is the one
that had to be told: the catalogue can start working while a channel still does not. Verified at
source, then the constant and its doc block were rewritten and the test updated to assert the new
sentence.

**One real defect: unbounded reentrancy.** A custom DoH endpoint whose host equals the panel host
makes the DoH rung's own `HttpClient` re-enter this override, calling `resolve` once per level with
a fresh client each time. Guarded now in `_addressFor`, with a test. Proved by removing the guard:
the test does not fail, it HANGS the whole run, which is the defect stated exactly.

**Fixed alongside**: two stale doc anchors in `xtream_credentials.dart` (my own `signOut` edit is
what shifted the lines they cited), and two uncovered branches in the override tests, the proxy case
and `panelHost()` returning null.

**Recorded rather than fixed**, all in the report: a pooled keep-alive connection bypasses the
factory entirely (`http_impl.dart:2661-2665`), so a resolver change leaves an already-open socket on
the old address for dio's 3 second idle window; the tamper check sees only the blackhole shape and
not a public block-page address; there is no flush on a network change; and the two shipped DoH
endpoints are hostnames bootstrapped through the very resolver the ladder exists to escape.

Gates after the remediation: analyze clean, 638 tests, `flutter build web --no-pub` green.
