# Architecture pressure-test (ac:oracle)

Its own confidence: **low**, because three of the premises I briefed it with came back REFUTED.
The recommendation rests on quoted source throughout; the tag reflects that my frame did not
survive. I verified the three refutations myself before letting them move anything.

## The three premises that failed, all verified by me

**1. "The screens virtualise nothing." REFUTED.** I had carried `CLAUDE.md`'s note about *wind's*
gap into a claim about the *app*. The app already routed around it, deliberately:
`lib/ui/components/rail/rail.dart:11-15` — "A `ListView.builder` rather than a Wind
`overflow-x-auto`, and this is not a preference either: Wind's overflow utilities compose a
`SingleChildScrollView`, which builds every child." And `now_layout.dart:87` plus
`showcase_layout.dart:75` are both `SliverList.builder`. Checked; both read as quoted.

So catalogue size does not threaten the render path, which removes the main argument for a query
layer.

**2. "Classification belongs to whatever makes the HTTP call." REFUTED.**
`tool/xtream-mock/README.md:126-129`, checked verbatim: throttling "can only be inferred from a
parse failure, and that same shape is what a blocked address, a blocked user agent, an HTML error
page and an expired stream request all produce. **It cannot on its own tell throttled from blocked
from expired.**"

So a single response is not classifiable. Classification needs the response **plus** a session
context holding the last handshake, which is the oracle's argument for putting it on a session
object rather than in the client.

**3. "A fourth case is known: connection-limit eviction." REFUTED as new.**
`lib/app/models/provider_fault.dart:39-45` already assigns it: "A shared subscription being used
on another device is the everyday cause." The vocabulary already covers it.

The oracle nonetheless argues for splitting it out; see recommendation 4 below, which is a
different claim from mine.

Also corrected: `DB.statement` and `DB.select` are **synchronous** (`db.dart:105`, `:86`) and `DB`
exposes no `prepare`, so every raw write blocks the calling isolate and re-prepares its SQL.
`DB.transaction` (`:183`) wraps a **sync** BEGIN/COMMIT around an **async** callback.

## Bottom line

**Two layers, not three, and neither is a query layer.** The controllers already do every filter,
search and section in Dart over an in-memory `List<Channel>`
(`guide_controller.dart:161-227`), and the query builder could not express those filters anyway
(no `like`, no `whereIn`). So SQLite's only job is cold start and offline, and `Channel` should
stay a value type rather than becoming the `Model` its own doc at `channel.dart:29` promises.

## The CRITICAL gate

**Nothing measures whether a `player_api.php` call consumes a connection slot.** The measured
eviction (`player-layer.md:226-230`) had `.ts` requests on both sides. If an API call also evicts,
then a catalogue refresh during playback is illegal, the catalogue becomes a launch-time-only
fetch, and recommendation 5's blocking write lands at the worst moment. One controlled test
settles it: start a stream, fire `get_live_streams` at t=4 s, see whether the stream survives.

## The recommendations

1. Run that eviction control before writing code.
2. `lib/app/protocol/xtream/` with five files and **no interface**: `xtream_credentials.dart`,
   `xtream_client.dart` (one method per action, `Http.get(absoluteUrl, query:, headers:)`),
   `xtream_json.dart` (the coercion helpers), `xtream_account.dart` (`maxConnections`,
   `activeConnections`, `allowedOutputFormats`, `bool get active` as the disjunction),
   `xtream_fault.dart`. Then `Channel.fromXtream` and `TitleItem.fromXtream` as **factories on the
   existing models**, not a mapper layer, per `CLAUDE.md`'s "No new file where an edit to an
   existing one would do".
3. `lib/app/provider/` with `provider_session.dart` and `catalogue_store.dart`. `ProviderSession`
   owns classification because it is the only object holding both credentials and the last
   handshake, so it alone can answer "why did playback just die" by re-probing.
4. **Add a fourth `ProviderFault` member, `evicted`.** Not cosmetic: for `throttled` a retry is
   safe, and for `evicted` **the retry itself evicts the other device**. No shared member can
   express that. Message, no automatic retry, user-initiated only.
5. Write the store through a **prepared statement**, not `DB.statement`: reach
   `Magic.make<DatabaseManager>('db').connection` (a `CommonDatabase`, `prepare` at
   `sqlite3/lib/src/database.dart:158`) and run one prepared insert per table inside one
   BEGIN/COMMIT. Time it on the slowest target first: the path is synchronous, so its cost is a
   frozen UI for exactly that long.
6. Add `WATCHOOLS_TITLE_SCALE`. `fixture_scale.dart:68` is `titles => channels ~/ 2` and `:58`
   clamps channels at 50,000, so the real **12.9:1** title-to-channel ratio is unreachable and the
   library screen has never been measured above 2,500 titles. The channel side is measured at
   5,000; VOD is not measured at all.
7. File two magic reports. **Defect**: `network_service_provider.dart:15` hardcodes
   `Config.get('network.drivers.api')` and is the only reader, so the config's `'default'` key,
   `drivers` map and per-driver `'driver': 'dio'` promise a multi-driver surface that does not
   exist. **Gap**: no per-request timeout, and the 10 s `receiveTimeout` is per-byte-event
   (`dio/options.dart:403-409`), not total, applying unchangeably to a 38,247-row fetch.

## Three hazards worth carrying into the plan

- **The catalogue looks healthy while nothing plays.** A non-active account still lists its whole
  catalogue and fails only at the stream. A client treating a successful catalogue fetch as a
  healthy provider shows a full line-up for a dead subscription. Classify from the handshake on
  every session start, never from whether the lists parsed.
- **The `api` driver sends `Content-Type: application/json` on every GET**
  (`lib/config/network.dart:15`), and a panel answering `text/html` skips dio's JSON fast path
  entirely, returning a `String` the parser must decode itself. Handle both a decoded map and a
  raw string in one place.
- **An `await` inside `DB.transaction` runs with the transaction open**, so chunking a large insert
  across event-loop turns to keep frames alive lets any other query join that transaction. Keep
  the refresh write synchronous and uninterrupted, behind an explicit progress state.

## Where it argues with my scoping

- **Series belong in v1, but only for the ID space.** `get_series` returns `series_id` from a
  different space than `stream_id`, and `title_sections.dart:30-100` plus
  `library_controller.dart:100` already read `title.seasons`. A movies-only v1 fixes `/baslik/:id`
  to one space, so the retrofit is a route change **plus a store migration**. Fetch the series
  list in v1, leave `get_series_info` lazy. This is the one omission it says costs an interface
  change later.
- **Catch-up out of v1: agrees, with one column.** `tv_archive` is set on 20 of 2,976 channels
  (0.7%), so URL derivation across five conventions buys almost nothing. But carry `tv_archive`
  and `tv_archive_duration` as columns from day one so `ChannelStatus.catchup` is computable and
  no migration follows.
- **Favourites out of v1: agrees reluctantly.** `channel.dart:57` calls them "the only thing that
  makes a ten thousand channel line-up usable", and `toggleFavourite` currently mutates a list a
  restart discards. Nobody notices against 23 fixture channels; everybody notices against 2,976.

## Escalation triggers it set

- An API call evicts a stream → re-plan before writing code.
- The measured write exceeds ~2 s on the slowest target → a synchronous SQLite write that long is
  not survivable behind a progress state on a TV, and the answer becomes a background isolate with
  its own connection, which magic's web arm cannot provide.

## Two leads for later

- `magic/CLAUDE.md:92` says "Web = in-memory SQLite" while `connection_factory_web.dart:41` opens
  an `IndexedDbFileSystem`-backed database, and `web/sqlite3.wasm` is present in this repo. The
  sibling doc is probably stale; worth one probe before designing web around either claim.
- The mock's `epg_channel_id` is null on 1 of 8 against **91% empty in reality**
  (`player-layer.md:286`). Only ~268 of 2,976 channels can carry EPG at all, which shrinks the EPG
  volume question far below the catalogue one.
