# Magic's Http facade against a per-user base URL (ac:explore)

**Headline, verified independently in `verification-log.md`: no deviation from the `Http` facade
mandate is needed.** An absolute URL passes straight through Dio and bypasses the driver's
`base_url`, so a per-user panel host is just a full URL at the call site.

Paths in `/Users/anilcan/Code/fluttersdk/magic`.

## The six questions

**1. Runtime driver registration.** Possible but not needed. `lib/src/facades/http.dart:23`
resolves `Magic.make<NetworkDriver>('network')` from the container, and
`Magic.app.setInstance('network', driver)` replaces it (`http.dart:140`).
`network_service_provider.dart:12-22` registers the singleton in `register()`, reading `base_url`
from config at bootstrap only. `dio_network_driver.dart:18-31` takes `baseUrl` in the constructor
with **no setter**, so a single driver cannot be reconfigured after construction; you replace the
instance instead.

**2. Absolute URL per request.** `dio_network_driver.dart:182-196` passes `url` straight to
`_dio.get(url, ...)`. Dio treats an `http(s)://` prefix as absolute. Works with no special API.

**3. Per-request headers, case preserved.** Every method takes `Map<String, String>? headers`
(`http.dart:80-112`), applied as `Options(headers: headers)`
(`dio_network_driver.dart:191`). The interceptor round-trips them through
`Map<String, dynamic>.from(options.headers)` and `options.headers.addAll(...)`
(`:42`, `:53`) without lowercasing. So exactly `User-Agent` survives the magic layer. Whether
`dart:io` preserves it on the wire is the librarian's question, not answered here.

**4. Redirects.** No `followRedirects`, `maxRedirects` or `validateStatus` anywhere in
`dio_network_driver.dart`. The interceptor's `onResponse` sees the **final** response, not the
intermediate 302. To observe a redirect you would need `configureDriver()` to reach the raw Dio
instance. The "5 redirects by default" figure is uncited: see `verification-log.md`.

**5. Timeout and retry.** `dio_network_driver.dart:18-30` takes one `timeout`, applied to both
`connectTimeout` and `receiveTimeout`; the provider passes 10000 ms
(`network_service_provider.dart:19`). **No per-request override.** No built-in retry;
`magic_network_interceptor.dart:34-37` lets `onError` return a `MagicResponse` to resolve as
success, which is the seam an exponential backoff would use.

**6. Transport failure versus HTTP status.** `MagicResponse` **never throws**
(`lib/src/http/request.dart:51-160`). `_handleError`
(`dio_network_driver.dart:371-380`) returns `MagicResponse(statusCode: e.response?.statusCode ?? 0)`,
so a transport failure is `statusCode: 0` with the reason in `.message`, and `.successful`,
`.failed`, `.serverError` are the query surface.

That last point matters more than it looks: this protocol carries failure in a **200 body**, and
magic already hands back a non-throwing response object. So fault classification reads a status
code and a body rather than catching an exception, which suits the three-way `ProviderFault` split.

## The three real gaps

1. **No per-driver base URL setter.** Replacing the instance on provider change works. A
   `setBaseUrl()` on the driver would be cleaner and is a sibling change. Moot for this plan
   because of the absolute-URL answer.
2. **No redirect interception.** Only matters if the plan needs to observe the 302 rather than
   follow it. For the catalogue it does not; for stream URLs the player already follows it natively.
3. **No per-request timeout.** All provider calls share the driver's timeout. A catalogue fetch of
   38,247 titles and a handshake probably want different ones, which makes this the gap most
   likely to bite.
