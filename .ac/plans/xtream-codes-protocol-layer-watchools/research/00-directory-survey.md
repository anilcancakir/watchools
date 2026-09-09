# Directory survey

Main-agent survey for the Xtream protocol layer plan. Written at Stage 1a.

## Top-level structure

One repository, two halves plus tooling.

```
lib/                  Flutter app, 98 Dart files
  app/
    commands/         artisan commands
    controllers/      guide_controller.dart, library_controller.dart (SimpleMagicController)
    models/           channel.dart, programme.dart, provider_fault.dart, title_item.dart
    providers/        app_service_provider.dart, route_service_provider.dart
    support/          guide_fixture.dart, vod_fixture.dart, scale_fixture.dart,
                      fixture_scale.dart, guide_clock.dart
    kernel.dart
  config/             app, auth, broadcasting, cache, database, logging, network,
                      routing, view, wind_theme.g.dart, watchools_status_tokens.dart
  resources/views/
  routes/
  ui/
    components/       18 atomic component folders, incl. provider_notice/
    layouts/          now, time, showcase, curtain + support/page_gutter.dart
backend/              Laravel 13, PHP 8.5 (not in scope for this plan)
packages/
  watchools_player/   the plugin, merged this session: tick, event channel, StallDetector
tool/xtream-mock/     the local panel: server.mjs, catalogue.mjs, encode.mjs, verify.mjs
test/                 app/{controllers,models,support}, config, support, ui/{components,layouts}
.ac/research/         stack-decisions.md, player-layer.md, design-doctrine.md,
                      ecosystem-defects.md  (TRACKED, see conventions)
```

There is **no** `lib/app/services/`, no `lib/app/repositories/`, no `lib/app/clients/`. The
protocol layer has no existing home; where it goes is a plan decision.

## Language / stack markers

- `pubspec.yaml` — Flutter 3.47 / Dart 3.13. Ecosystem packages (`magic`, `fluttersdk_wind`,
  `magic_*`) declared **hosted**, resolved locally through the gitignored
  `pubspec_overrides.yaml`.
- `lib/config/network.dart:9` — one Http driver, `api`, `base_url` from `env('API_URL', ...)`,
  10 s timeout, JSON headers. **Static.** A provider's panel base URL is per user and decided at
  runtime, so this config shape does not obviously accommodate it. Research angle 2.
- `lib/config/database.dart:7` — SQLite, one connection, `database.sqlite`. In-memory on web.
- `lib/config/auth.dart` — present, unread; relevant only if provider credentials would be
  routed through it rather than through Vault.
- `backend/composer.json` — Laravel 13, out of scope here.
- `tool/xtream-mock/` — zero-dependency Node panel, 70 verification checks, 8 codec channels,
  9 account fault shapes. This is the development target.

## Project conventions

From `CLAUDE.md` (read in full) and `.claude/rules/workflow.md`:

- **Wind owns styling.** `className` strings and `W`-prefixed widgets only. No `Colors.*`, no raw
  `TextStyle`. Not directly in scope for a protocol layer, but the controllers' consumers are Wind.
- **Magic owns everything below the widget.** Controllers via `Magic.findOrPut`, views as
  `MagicStatefulView<XController>`, notification via `refreshUI()`, **HTTP through the `Http`
  facade**, lists through `MagicPaginator`, **secrets through `Vault`**, storage through the ORM,
  routes registered in a provider's `boot()`. Reaching for `dio`, `shared_preferences`, `sqflite`
  or a bare `Navigator` is the thing the rule exists to prevent.
- **The Magic ORM is CRUD-shaped**: no `index()` in `Blueprint`, no `whereIn` / `like` / `join` in
  the query builder, and a row-at-a-time `insertAll`. `CLAUDE.md` states the channel catalogue
  therefore goes through `DB.statement` and `DB.transaction`.
- **Ecosystem defects are our backlog**, reported in the reply and recorded in
  `.ac/research/ecosystem-defects.md`. A defect found in `magic` during this work is a sibling PR,
  per `.claude/rules/workflow.md`.
- **Provider requests**: per-provider `User-Agent`, header key normalised to exactly `User-Agent`
  (ExoPlayer's lookup is case sensitive). `Referer` optional because Tizen cannot send it. Never
  log a credential, never commit one; `.env.local` is reserved and gitignored and nothing reads it.
- **Testing**: 90% coverage floor on both halves, over a denominator excluding Magic's generated
  scaffold. `flutter test --coverage`, floor enforced in the CI step. Wind's parser cache is static
  so widget tests call `setUp(WindParser.clearCache)`. `.env` is a real asset during tests, so a
  test asserting an `env()` default passes because `.env` supplies the same string.
- **Worktree flow** (`.claude/rules/workflow.md`): `master` never written directly, one worktree
  and one PR per task, CI green before merge.
- `.gitignore:63` — "`.ac/research/` and `.ac/plans/` are deliberate project artefacts and stay
  tracked". So this plan is **committed**, and Stage 0d's default `.ac/` append was deliberately
  not applied.

No `.claude/rules/*.md` carries a `paths:` frontmatter; `workflow.md` is unscoped and applies.

## Sub-projects

- `packages/watchools_player/` — has its own `pubspec.yaml` and `example/`. CI resolves and
  analyses it separately (`.github/workflows/ci.yml`, "Analyze the packages"), and now runs its
  own tests. It is where the player-side work of this session landed and it is **not** where the
  protocol layer goes: it must not depend on the app.
- `backend/` — Laravel, its own composer project, out of scope.

## What the consumers already expect

The client's output shape is constrained by two existing readers, not by the wire:

- `lib/app/models/channel.dart:31` — `Channel` is a plain `@immutable` value type with
  `number`, `name`, `group`, `status` (`ChannelStatus.live|catchup|recording|idle`), `logoUrl`,
  `schedule` (`List<Programme>`), `facts` (`List<String>`), `favourite`. Its own doc says "It
  becomes a `Model` when the Xtream client lands", which is a plan decision rather than a given.
- `lib/app/controllers/guide_controller.dart` — `SimpleMagicController`, holds `GuideMode`,
  rails as `GuideRail`, an injected `GuideClock`, reads `fixture_scale.dart`.
- `lib/app/controllers/library_controller.dart` — the same shape for VOD.
- `lib/app/models/provider_fault.dart:24` — three members, `unreachable` / `expired` /
  `throttled`, with the doc stating nothing produces one yet and only `expired` withholds a retry.
- `lib/ui/components/provider_notice/` — renders all three, reachable only at `/preview`.

## Provisional research angles

1. **Reuse**: what in the app and in the `magic` sibling already covers HTTP, retry, credential
   storage, pagination and bulk insert, so the plan builds only the delta. (1c slot)
2. **Per-user base URL through the `Http` facade.** `lib/config/network.dart` declares drivers
   statically; a provider's panel host is per user and arrives at runtime, and the real panel
   answers `302` to a *different origin*. Does magic support a runtime driver, a per-request base
   URL, or does this need a second mechanism.
3. **`Vault`'s real shape and platform coverage**, and whether it is the right store for a
   credential pair plus a panel URL. `CLAUDE.md` mandates it; its API and its web behaviour decide
   the onboarding flow.
4. **The raw SQL path**: exact `DB.statement` / `DB.transaction` signatures, `Blueprint`'s
   limits, and what a 3,000-row insert costs when `insertAll` is row-at-a-time. The real provider
   has 2,976 live channels and 38,247 VOD titles.
5. **The controllers' integration surface**: precisely what `GuideController` and
   `LibraryController` read today, so the client's output is shaped by the consumers.
6. **Test patterns for a networked client**: how existing tests fake `Http`, what `test/support/`
   offers, and how the 90% floor is met for a layer whose failures are wire shapes.
7. **The mock's action surface**: the exact `action=` set and response field lists, to fix the
   parser's contract against something executable rather than against prose.
8. **Xtream protocol reality check** (librarian): field-type drift, pagination, `get_short_epg`
   against `xmltv.php`, and what real clients do about the undocumented corners.
9. **Dart HTTP behaviours** (librarian): cross-origin `302` handling, header-case preservation,
   keep-alive, and any package-version breakage in the pinned stack.
