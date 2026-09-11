# Dart HTTP hazards for this shape (ac:librarian)

Every claim below carries a source. The agent named its own coverage gap rather than filling it,
which is why item 5 is a negative rather than a list.

## 1. Header case: the hazard is real, and it lands on us

`dart:io` lowercased every header name until Dart 2.16 added `preserveHeaderCase`
(`dart-lang/sdk#33501`, approved in `#39657`, follow-up `#41628`). The maintainer explicitly
declined to preserve the case of *received* headers, so the flag only governs what is sent.

`package:http`'s `IOClient` sets it unconditionally
(`io_client.dart:119-120`, `ioRequest.headers.set(name, value, preserveHeaderCase: true)`).

**But magic wraps Dio, not `package:http`**, so that guarantee does not transfer. I chased the
chain myself and it is a defect: see `verification-log.md`, "magic's Http driver lowercases every
header on the wire". Dio's flag defaults to `false` and magic never sets it.

## 2. Cross-origin redirect: one doc and one closed issue disagree

- `followRedirects` defaults to **true** and applies to GET/HEAD
  (`api.dart.dev/dart-io/HttpClientRequest/followRedirects.html`). All request headers are copied
  to the redirect target **except** `Authorization`, `WWW-Authenticate`, `Cookie`, `Cookie2`,
  which are dropped unless the target is an exact or subdomain match.
- That exclusion list exists because of `GHSA-c8mh-jj22-xg5h`: before Dart 2.16 those headers
  leaked cross-origin unconditionally.
- `User-Agent` is **not** on the sensitive list, so the current docs say it survives the hop.
  **But `dart-lang/http#268`, "Custom User-Agent lost after redirect", closed "by design"**, says
  a per-request UA is lost and the workaround is the client-wide `HttpClient.userAgent`. That
  issue predates the 2.16 redirect rewrite and the agent could not confirm whether it still holds.

**Treat as an open test case, not a settled fact.** Our panel redirects to a different origin and
the UA is a product requirement, so this needs an integration test against a real 302 rather than
trust in either source. The mock already produces exactly that redirect.

To observe rather than follow: `request.followRedirects = false`, then read `response.isRedirect`
and `Location`. Not reachable through magic's facade (see `explore-http-facade.md`, gap 2).

## 3. JSON numbers diverge between web and native, and this one is concrete

On native, `int` is a real 64-bit integer distinct from `double`. On web both share one 64-bit
float, so `1.0.runtimeType` is `int` on web and `double` on native, and every whole number answers
`true` to both `is int` and `is double`
(`dart.dev/resources/language/number-representation`). `jsonDecode` parses via `num.parse` on both
platforms with no documented int/double contract (`dart-lang/sdk#46882`, `#46683`).

**The rule this produces, and it is a hard convention for every decode in this layer:**

> Decode every numeric field as `num`, never `as int` or `as double`, and convert at the point of
> use: `(json['bitrate'] as num).toInt()`.

A field cast `as int` throws on web the moment a provider sends a fractional value; a field cast
`as double` throws on native the moment it sends a bare integer. This protocol sends
`rating` as a quoted string beside `rating_5based` as a bare number, so both directions are live.

## 4. Timeouts: there is no read timeout

- `connectionTimeout` bounds only the TCP handshake to a new host; `null` defers to the OS.
- `idleTimeout` (default 15 s) closes idle **keep-alive** connections only.
- **An active response that stalls mid-stream has no built-in timeout.** Wrap the response future
  or stream in your own `.timeout()`.

Cancellation: `HttpClientRequest.abort()` exists at the `dart:io` layer. At the `package:http`
layer it arrived in **http 1.5.0** via `AbortableRequest` + `abortTrigger`
(`dart-lang/http#424`). Which concrete client magic's Dio adapter ends up on decides whether abort
is reachable, and it matters here because the measured account allows **one connection** and a
stray request evicts a playing stream.

## 5. No sourced Flutter 3.47 / Dart 3.13 HTTP regression

The agent read the 3.47.0 release notes directly: zero mentions of `HttpClient`, `dart:io`,
`sqflite`, redirects or timeouts. The one adjacent report (`flutter/flutter#183257`, iOS requests
failing in Debug since 3.35) is closed unconfirmed and Debug-only.

Stated as a genuine coverage gap rather than an absence of risk.
