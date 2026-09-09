# Wisdom

## Wave 1

1. **[REMEDIATION] `decodeBody` alone could not read seven of the ten actions.** Step 2's
   Description named "an already-decoded `Map` or a raw `String`", but the three category
   actions, the series list, the two stream lists and the EPG table all answer with a JSON
   **array** (`tool/xtream-mock/server.mjs:255-280`). A `Map?`-returning reader returns null for
   every one of them, so step 4 would have had no sanctioned decode path for the bulk of the
   protocol and would have reached for a bare `jsonDecode`, losing the `text/html` hedge that is
   the whole reason the reader exists. Added `decodeEntries` beside it in the file that owns
   decoding, with six tests including the empty-array case, which is distinct from unreadable
   because an unknown action and an empty category both legitimately return `[]`.

   **Correction, from step 4 and verified at source.** The split is **six arrays and four
   objects**, not the "seven including the EPG table" this item first said. Arrays: the three
   category actions, `get_series`, `get_live_streams`, `get_vod_streams`. Objects: the handshake,
   `get_vod_info`, and **both EPG actions**, which wrap their array in an envelope,
   `{ epg_listings: [...] }` (`server.mjs:322`, `:331-338`). So an EPG answer is
   `decodeEntries(decodeBody(body)?['epg_listings'])`, and a step that took the first version of
   this item literally would have read `null` for every EPG response. Step 8's short-EPG pass is
   the consumer that would have hit it.

2. **[REMEDIATION] A pasted `http://user:pass@host:8080` put a password inside `baseUrl`.**
   `XtreamCredentials.toString()` prints `baseUrl` in full, and the first draft's rejection used
   `ArgumentError.value(normalised, ...)`, which interpolates the very string that may carry the
   secret. Both paths violated step 1's own `Must NOT`. The constructor now rejects a non-empty
   `userInfo` outright (Xtream sends the credential as query parameters, so an authority
   credential is malformed input rather than a supported shape) and neither rejection message
   interpolates the value.

3. **magic resolves dio 5.9.2, not the 5.11.1 the plan cited.** All three links of the
   header-case evidence chain hold at the resolved version; only `options.dart` moved from `:152`
   to `:151`. Re-verify a pub-cache line number against the version the target repository
   actually locks, not against the newest one on disk: six dio versions are cached here.

4. **The header-case requirement is unmeetable on web by construction.** `preserveHeaderCase` is
   forwarded only by dio's IO adapter (`io_adapter.dart:109`, present in every cached version).
   The web adapter writes headers through `xhr.setRequestHeader`, a browser API with no
   case-preservation hook at all. So `User-Agent` survives on macOS, iOS, Android, Windows and
   Linux, and cannot on web. That is a platform limitation rather than a magic gap, and it does
   not widen PR #151.

5. **Two instruments and two frictions worth carrying forward.** An `HttpHeaders`-based
   assertion cannot prove header case, because the receiving side lowercases on parse regardless
   of what went on the wire; only a raw socket read can, which is what
   `magic/test/network/preserve_header_case_test.dart` does. And every `flutter test` run
   re-triggers `pub get`, which rewrites `pubspec.lock` with 7 `source: path` entries and
   regenerates `macos/Flutter/GeneratedPluginRegistrant.swift`: both need restoring at every
   wave barrier, which is exactly the failure `CLAUDE.md` records going green through a whole
   pipeline. The file-scope hook also accepts only literal paths, so a directory entry in
   `wave_files` does not authorise a new file inside it.

## Wave 2

6. **[REMEDIATION] Step 9 had to run in wave 2 rather than wave 4.** `provider_notice.dart:81`'s
   `switch` on `ProviderFault` is exhaustive by design, and its own comment says so, so the moment
   step 5 added `evicted` the repository stopped compiling: `test/ui/components/provider_notice_test.dart`,
   `test/config/app_config_test.dart` and `test/ui/preview_catalogue_test.dart` all failed to load,
   the last two because they transitively register the preview catalogue. The plan's Dependency
   Notes recorded "step 9 needs step 5" and then placed them two waves apart, which is a dependency
   in the wrong direction: an enum member and its exhaustive consumer have to land in the same
   barrier or every wave between them commits a tree that does not build.

7. **[REMEDIATION] Steps 5 and 9 contradicted each other over one sentence.** Step 5 narrowed
   `throttled`'s enum doc to hand the connection case to `evicted`, while step 9's `Must NOT` said
   not to change what `throttled` renders, and what it rendered was exactly that story
   ("Aboneliğiniz başka bir cihazda açık olabilir"). Leaving both intact would have shipped two
   faults telling the user the same thing, making the split invisible on screen and pointless.
   Resolved by scoping the exception to `throttled`'s body copy alone: icon, title, verb, disc and
   position untouched.

8. **[REMEDIATION] `atConnectionLimit` read an absent limit as a reached one.** `maxConnections`
   defaults to `0` on a drifted or missing `max_connections`, and `activeConnections >= maxConnections`
   then made `0 >= 0` true, routing a **healthy** account to `evicted`, whose panel blames a device
   that may not exist and whose retry is deliberately withheld. Guarded on `maxConnections > 0`.
   The rule this generalises to: when two classifications differ in whether their remedy is safe,
   ignorance resolves toward the safe one.

9. **A fake that removes the mechanism under test turns a security assertion green for the wrong
   reason.** `Auth.fake()` installs a `FakeAuthManager` whose guard is `_FakeGuard` rather than a
   `BaseGuard`, so `cachedToken` never exists and `AuthInterceptor` would find nothing to attach:
   the "no `Authorization` header reaches the panel" test would have passed against a driver that
   leaks. Step 4 used a real `BearerTokenGuard` over `Vault.fake()` and asserted `cachedToken`
   inside the seeding helper so the seam cannot silently go dead. It then added the control that
   actually makes the gate meaningful: the same request through a driver that **does** carry
   `AuthInterceptor`, asserting the token IS on the wire. A negative assertion with no positive
   control beside it cannot distinguish "secure" from "rig broken".

10. **`Http.fake()` fakes the `network` key only, and `FakeNetworkDriver` runs no interceptors at
    all.** It builds its `MagicRequest` records from its own arguments, so every header assertion
    against it reflects what the caller passed rather than what would go on the wire. Split the
    questions: wire behaviour (a header's presence, its case, a followed redirect) needs a loopback
    `ServerSocket`; request shape (query keys, an absent `action`, an absent pagination parameter)
    is what the fake is genuinely good for. Separately, `./bin/fsa previews:refresh` writes
    `lib/_previews.g.dart` in a shape `dart format --output=none --set-exit-if-changed lib test`
    rejects, so running the generator breaks step 14's format gate until the file is re-formatted;
    the content is identical once it is.
