# Interview log

Plan: `xtream-codes-protocol-layer-watchools`. Auto mode: false.

## Stage 1-2 synthesis

**Codebase state**: `disciplined`. Consistent style, configs present, 90% coverage floor enforced
in CI, doc blocks carry rationale rather than restating signatures. Match patterns strictly.

**What exists today**

| Need | Status |
|---|---|
| HTTP with a per-user base URL | Exists. `Http.get(absoluteUrl, ...)` bypasses `base_url`, verified at `dio_network_driver.dart:181-196` |
| HTTP test double | Exists, first-party. `Http.fake()` at `magic/lib/src/facades/http.dart:138` |
| Secret storage | Exists. `Vault.put/get/delete/flush`, strings only, all five platforms including web |
| Bulk write | Exists but sharp. `DB.statement(sql, params)` binds and is **synchronous**; `insertAll` is two statements per row |
| Pagination | `MagicPaginator` exists but is **not needed**: the protocol has no pagination |
| Retry | Contract only (`MagicNetworkInterceptor.onError`), no implementation |
| ORM headless under `flutter test` | Proven: `magic/test/database/query_builder_test.dart` passes 12/12 |
| Xtream parsers, wire-to-model mapping | **Absent. This is the delta.** |

**The delta**: the Xtream client, the type-drift coercion, the fault classification, the mapping to
`Channel` / `TitleItem`, a catalogue store, and the controller swap.

**Codebase fit**: High. Every piece of infrastructure is present and the consumers already expect
`List<Channel>` and `List<TitleItem>`, so the fixture swap is mechanical.

**Effort**: Large. Cross-module: a new protocol package, a session object, a store, two controllers,
four layouts, plus a sibling PR.

## Risks research produced

1. **`magic` ships `user-agent`, not `User-Agent`.** Verified chain in `verification-log.md`. The
   app's own requirement is exact-case and the failure is silent on Android. Not fixable at the
   call site.
2. **Unmeasured**: whether a `player_api.php` call consumes a connection slot. Decides whether a
   catalogue refresh during playback is legal.
3. **A synchronous 38,247-row write freezes the UI for its whole duration**, and an `await` inside
   `DB.transaction` lets other queries join the open transaction.
4. **A dead subscription still lists its whole catalogue.** Classify from the handshake, never from
   whether the lists parsed.
5. **A single response is not classifiable**: `mock README:126-129`, the 200-plus-non-JSON shape is
   shared by throttled, blocked address, blocked user agent, an HTML error page and an expired
   stream request.
6. **Web / native number typing diverges.** Decode every numeric as `num`.
7. **No read timeout in `dart:io`**, and no per-request timeout through magic's facade.
8. Four real-panel behaviours our mock cannot produce: non-base64 EPG text, `exp_date` as `0`, the
   `get_simple_date_table` typo action, and a panel that refuses a bare handshake.

## Decisions

Four questions were put to the user with a recommended option each, grounded in the research
above. No answer arrived within the wait, so each is **locked on its recommended option and
recorded as a default rather than an answer**. All four are listed in the plan's
`## Risks Accepted` so a later reader can see which were chosen and which were merely not
contradicted.

### D1. The header-case defect → parallel sibling PR, plan proceeds

magic never sets Dio's `preserveHeaderCase`, so the `Http` facade ships `user-agent`. Verified
chain in `verification-log.md`. Not fixable at the call site.

**Locked**: open a PR against magic setting `preserveHeaderCase: true`, and let this plan proceed
in parallel. The client's test asserts exactly `User-Agent` from the start, so the requirement is
in code and goes red until the sibling lands rather than being remembered later.

**Why this over blocking**: `.claude/rules/workflow.md` makes a sibling change a publish plus a
constraint bump, so blocking costs a release cycle for a defect that affects one platform.
macOS and iOS do not read the header case; only ExoPlayer on Android does.

**Why this over accepting the risk**: the failure is silent, which is the shape this project has
been burned by repeatedly.

### D2. The connection-slot gate → assume the worst, do not measure

Unmeasured: whether a `player_api.php` call consumes a connection slot. The measured eviction had
`.ts` on both sides (`player-layer.md:226-230`).

**Locked**: gate every catalogue refresh on "not currently playing". No real-provider requests
spent.

**Why**: it cannot break playback, it costs nothing today, and loosening a restriction later after
one measurement is easy while discovering the opposite in production is not. The user's standing
constraint on real-provider requests (few, logged, never repeated) also argues for not spending
two on a question a conservative default answers.

**What would change it**: the controlled test the oracle specified, which stays in
`## Deferred Ideas`.

### D3. Layering → two layers plus a cold-start cache

**Locked**: `lib/app/protocol/xtream/` (client, coercion, account) and `lib/app/provider/`
(session, store). `Channel.fromXtream` and `TitleItem.fromXtream` as factories on the existing
models rather than a mapper layer. No `CatalogueSource` interface: one implementation, and
`CLAUDE.md`'s rule is the third concrete caller.

**Why**: the controllers already filter, search and section in Dart over an in-memory list
(`guide_controller.dart:161-227`), and the query builder cannot express those filters anyway. So a
repository would hand SQL results to code that loads everything into memory regardless. SQLite's
only job is cold start and offline, which is also why the ORM's missing `index()` stops mattering:
there are no queries to index.

### D4. v1 scope → series list, catch-up columns, favourites; EPG deferred

**In**: the `get_series` list (so `/baslik/:id` knows both ID spaces from the start, the one
omission the oracle says costs an interface change later, with `get_series_info` left lazy);
`tv_archive` and `tv_archive_duration` as columns with no URL derivation; persistent favourites.

**Out of v1**: the EPG import. Deferred rather than dropped, and it is the item most likely to be
pulled forward, since the two live layouts are built around a schedule and currently read one from
a fixture. Note the volume is small: 91% of real channels have no `epg_channel_id`
(`player-layer.md:286`), so only ~268 of 2,976 can carry a guide at all.

**Also locked**: a fourth `ProviderFault` member, `evicted`, split from `throttled`. Not cosmetic:
for `throttled` a retry is safe, and for `evicted` the retry itself evicts the other device.

## Stage 3.5 Oracle Sanity Check

Triggers 1 (security-critical surface: credential storage, untrusted input reaching SQL) and 4
(a refresh that replaces the previous catalogue contents, no rollback path) fired. Trigger 2 did
not: no composable framework chain was adopted from librarian research. Trigger 3 did not: the one
conflicting signal, header case between `package:http` and Dio, I resolved myself against source.

One focused oracle spawned on those two surfaces only, with the locked shape given to it for
review rather than for redesign.

**Outcome: two CRITICAL findings, both verified by me against source, both folded into the plan.**

1. **magic's `AuthInterceptor` attaches the caller's bearer token to every request with no host
   test** (`auth_interceptor.dart:20-30`) and sits on the single `'network'` driver that `Http`
   resolves (`auth_service_provider.dart:85`). This app registers both providers today
   (`lib/config/app.dart:27`, `:31`). So the plan's original step 4, calling `Http.get` on an
   absolute panel URL, would have shipped the user's watchools token to a third-party host over
   plaintext HTTP; and `auth_interceptor.dart:40-73` treats a 401 from that host as a refresh
   signal, attaches the **new** token and replays, with a failed refresh calling `Auth.logout()`.
   Latent only because no login exists yet. Step 4 now registers a dedicated interceptor-free
   `provider_network` driver, was escalated to `senior` with `rule-5-criticality`, and carries the
   no-`Authorization` assertion as its load-bearing test. This refutes the earlier conclusion that
   no deviation from the `Http` facade was needed: the deviation is required, just not for the
   reason first thought.
2. **A zero-params `DB.statement` runs stacked SQL.**
   `sqlite3-3.5.2/lib/src/implementation/database.dart:287-310`, verified: an empty params list
   routes to `sqlite3_exec`, whose own comment says it "can run multiple statements at once", while
   a non-empty list goes to `prepare(sql, checkNoTail: true)` which rejects a trailing statement.
   So passing params is itself the anti-stacking defence, independent of quoting, and the
   38,247-row multi-row `INSERT` is exactly the pressure that tempts string building. Step 7's
   `Must NOT` list now says so with the citation, and requires chunking on a computed placeholder
   budget.

Two premises of mine were refuted in the process: the credential does **not** reach
`MagicResponse.message` or Dio's exception strings, but **does** reach telescope through the
response body because `user_info` echoes the password back; and web Vault is **localStorage** with
the AES key stored beside the ciphertext, not IndexedDB, with no app-side way to set `wrapKey`.

## Stage 5.5 Review

One advisory pass over the written plan by a fresh-context reviewer. **Ten CRITICAL and fifteen
IMPORTANT findings.** Coverage 4/4 objectives. I verified the four sharpest myself; all four held,
including two file paths I had wrong.

Fixed before delivery:

- `ProviderFault.evicted` was needed in wave 2 but added in wave 4, so wave 2 could not compile.
  The member moved into step 5 with its classifier; step 9 now only renders it.
- Step 9 omitted `provider_notice.recipe.dart`, whose `variants['fault']` map is keyed by member
  name, and named `provider_notice_preview.dart` when the real file is `provider_notice.preview.dart`
  (`previews:refresh` discovers only the dotted form). Both corrected.
- Step 9's `Done when` contradicted its own Description on the retry affordance. Resolved against
  the component as built: it renders exactly one required-callback button, so `evicted` keeps the
  button and the label carries the consequence.
- Nothing bound or started `ProviderSession`. Step 8 now edits `app_service_provider.dart`,
  binding in `register()` and starting in `boot()`.
- Step 13 ran a scale test no step created. Added to step 7's `Files`.
- Step 7's anti-injection grep could not fail: anchored to `statement('`, it missed `'''`-quoted
  SQL and any pre-built `sql` variable, which is how the SQL will actually be written. Replaced
  with the round-trip test plus a non-empty-params assertion.
- Step 7 used `package:sqlite3`, a transitive dependency only, which `depend_on_referenced_packages`
  would fail under `--fatal-infos`. `pubspec.yaml` added to its `Files`.
- Step 4's `User-Agent` test was to be left **red** while step 14 demands a green suite, which made
  the plan unfinishable by its own gate. Now `skip:`ped with the reason, unskipped alongside the
  constraint bump.
- **The sharpest finding**: step 10 replaced the guide controller's channels wholesale while step 6
  asserts an empty schedule, so `Şimdi` and `Zaman` would have rendered no programmes, no now line
  and no progress. A minimum now/next EPG came into v1 in step 8: `get_short_epg` for on-screen
  channels only, skipping the 91% with no `epg_channel_id`. The full XMLTV import stays deferred.
- `late Channel _channel = channels.first` and `late TitleItem _selected = titles.first` throw on
  an empty provider catalogue, which a fixture never is. Guard added to step 10.
- Six unfalsifiable `Done when` criteria replaced with test assertions, three `grep -c … returns 0`
  rewritten as `! grep -q` so a correct outcome does not exit non-zero, one unobservable check
  count dropped, and a `Dependency Notes` section added.

Also corrected from the Notes: `Http.get` is at `:80` not `:23`; the symbol is
`FixtureScale.channelList`; `MagicStateMixin` cannot apply to a `SimpleMagicController`; the
"no barrel exports" convention has a UI-component exception; and step 4's title said nine actions
while enumerating ten methods.

Deferred rather than fixed: the onboarding screen and the `/saglayici` route, which is why
objective 1 is now explicit that credentials arrive already in `Vault` and there is no user-facing
entry point after this plan.
