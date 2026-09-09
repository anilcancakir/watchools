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
