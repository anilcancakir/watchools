
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

### Code review (structural, ran against `540d185` and re-verified there)

Compliance 21 of 22, the missing one being step 9's `http_multiple` runtime proof, which the plan
already records as unmet. Must NOT clean on every step. Scope fidelity clean. Three CRITICAL, all
fixed before Phase 4, and every fix proved to discriminate by breaking the source.

**CRITICAL 1, and it was mine again.** The oracle's refutation reached the screen copy and stopped
there: `CLAUDE.md:184` and `.ac/research/stack-decisions.md` still blamed the `302` for why the
resolver misses playback, which step 8 had written from the old reason and `540d185` had refuted
without going back to the documents. Both rewritten, and both now say the reason is that playback
resolves every address itself, the panel's included.

**CRITICAL 2, a user-facing data loss found in the running app.** A typed custom resolver was written
only by the field's `onSaved`, and `Form.save()` skips a field that has unmounted, so picking
`Özel sunucu`, typing an address, closing the disclosure and saving submitted the SYSTEM resolver
with no error at all. This is the same class the step 6 briefing was written against, arriving
through the door the briefing did not name: the briefing guarded the picker and the field slipped
through. Fixed two ways, because one was not enough. The value is written on `onChanged` so it
survives the unmount, and `_submit` refuses a custom choice whose literal does not parse, because the
validator cannot run on a field that is not mounted. Two tests, both proved: with `onSaved` the value
arrives null, and without the submit guard the refusal never renders.

**CRITICAL 3, the security-relevant parser had never executed.** `host_lookup_io.dart` was 2 of 47
lines covered. `DohHostLookup._readAnswer`, which reads an untrusted body, checks the DNS status,
filters CNAME records and picks a TTL, had no test at all; the wave-2 wisdom line claiming "a test
covers the shape" pointed at a test driving a scripted rung rather than the parser. Eight tests now
run it against a real loopback server serving canned bodies, covering the valid answer, the CNAME
drop, NXDOMAIN, a non-object body, a non-200, an empty answer section, a negative TTL and a
pre-existing query on a custom endpoint. Coverage on that file: 40 of 49.

**One IMPORTANT fixed alongside**: the DoH rung caught three exception types, so `HttpException`,
`CertificateException` and a bare `TlsException` escaped both it and `HostResolver._ask`, failing the
panel request outright instead of moving to the next rung. It catches `IOException` now, with the
three named shapes kept ahead of it for their own messages.

**Recorded rather than fixed**, in the report: `redact` does not cover a custom resolver's query
string, which may carry a token; `Magic.put(hostResolver)` has no reader; no in-flight deduplication,
so N concurrent cold connections each run the full ladder; a failed resolve is not cached; two test
doubles (`_RawPanel`, `_ScriptedLookup`) now exist in three copies each and belong in `test/support/`;
and `WSelect` emits three nested button semantics nodes for one picker, which is a wind observation
for the pull request.

Gates after the remediation: analyze clean, 648 tests, coverage 2896/3013 = 96.1%, web build green.
