# Controller and consumer integration surface (ac:explore)

The client's output shape is fixed by these readers. Paths are repo-relative.

## The two controllers

Both are `SimpleMagicController` and both notify through `refreshUI()`.

**`lib/app/controllers/guide_controller.dart`**

- State: injected clock (`:67`), `channels` from `FixtureScale` (`:110`), then mode / group /
  query / selected channel / selected programme (`:112-116`), plus **four internal caches**
  (`:140-143`: match, scheduled, section, rail).
- Read surface: getters `mode`, `group`, `query`, `channel`, `programme` (`:146-158`), `matches`
  with cache logic (`:161-186`), `sections` / `scheduled` / `withoutSchedule` / `noGuideNote` /
  `groups` (`:193-227`), `rails` (`:258-313`), `countLabel` (`:322-326`).
- Mutations: `showMode`, `selectGroup`, `search`, `selectChannel`, `selectProgramme`,
  `toggleFavourite` (`:352-394`). Each invalidates caches and calls `refreshUI()`.
- Lifecycle: `_onTick()` calls `refreshUI()` (`:123-127`); `onClose()` disposes the clock if owned
  (`:130-134`).

**`lib/app/controllers/library_controller.dart`**

- State: `titles` from `FixtureScale` (`:36`), scope / category / query / selected / season
  (`:38-42`), four caches (`:46-49`).
- Read surface: getters (`:52-65`), `matches` (`:67-106`), `sections` coalesced by category
  (`:110-123`), `continueWatching` (`:132`), `countLabel` / `noArtworkNote` / `categories`
  (`:136-152`).
- Mutations: `showScope`, `selectCategory`, `search`, `select`, `openDetail`, `selectSeason`,
  `toggleFavourite` (`:160-224`).

**Neither uses `MagicStateMixin`**, which magic provides for loading / success / error / empty
tracking (`magic/lib/src/http/magic_controller.dart:140`). Adopting it is how a controller gains a
place to hold a `ProviderFault`, and it is an interview decision.

## The fixture seam the client replaces

| Function | Returns |
|---|---|
| `lib/app/support/fixture_scale.dart:58` | `FixtureScale.channels` → `List<Channel>` |
| `:74-75` | `channelList`, generated or hand-written |
| `:78` | `groupList` → `List<String>` |
| `:81-82` | `titleList` |
| `:85` | `categoryList` → `List<String>` |
| `lib/app/support/guide_fixture.dart:25`, `:30` | `guideGroups` → `List<String>`, `guideFixture` → `List<Channel>` |
| `lib/app/support/vod_fixture.dart:23`, `:48` | `vodCategories`, `vodFixture` → `List<TitleItem>` |
| `lib/app/support/scale_fixture.dart:120-223` | `ScaleFixture.groups/categories/channels/titles(count, ...)` |

So the swap is mechanical **if** the client returns `List<Channel>` and `List<TitleItem>`. That is
the argument for mapping to the existing value types rather than introducing wire types upward.

## Stored versus derived, which decides what may be persisted

**`Channel` (`lib/app/models/channel.dart:31-71`)** stores `number`, `name`, `group`, `status`,
`logoUrl`, `schedule`, `facts`, `favourite`. Derived: `hasSchedule` (`:78`), `numberLabel` (`:117`),
and the methods `programmeAt(int)` (`:93`) and `nextAfter(int)` (`:108`).

Note `status` is **stored**, not derived from the schedule and a clock. If the client persists it,
it persists a value that goes stale; that is an interview decision.

**`Programme` (`programme.dart:11-75`)** stores `startMinute`, `endMinute`, `title`, `subtitle`,
`description`, `imageUrl`, `episode`. Derived: `durationMinutes` (`:46`), `contains()` (`:49`),
`progressAt()` (`:58`), `startLabel` (`:65`), `endLabel` (`:68`). The minute unit is "minutes since
the schedule's midnight, never wrapped" per `CLAUDE.md`, so the client's EPG mapping owes that
convention rather than a wall clock.

**`TitleItem` (`title_item.dart:133-293`)** stores `kind`, `name`, `category`, `year`, `posterUrl`,
`backdropUrl`, `minutes`, `rating`, `genres`, `synopsis`, `facts`, `cast`, `episodes`, `progress`,
`favourite`. Derived: `isSeries` (`:207`), `seasons` (`:210`), `episodesOf()` (`:217`), `upNext`
(`:224`), `inProgress` (`:239`), `unwatchedCount` (`:253`), `lengthLabel` (`:262`), `ratingLabel`
(`:273`). `Episode` (`:24-77`) stores `season`, `number`, `title`, `synopsis`, `minutes`,
`imageUrl`, `progress`; derives `code` (`:60`), `inProgress` (`:68`), `runtimeLabel` (`:76`).

`progress` and `favourite` are **user state**, not provider state. They must survive a catalogue
refresh, which is a schema consequence.

## Where a fault renders

Three of four layouts branch in the same slot, the `flex-1` body under the pinned toolbar:

- `lib/ui/layouts/now_layout.dart:79-98` — `controller.matches.isEmpty ? _emptyBody() : CustomScrollView(...)`, where `_emptyBody()` is `GuideEmpty` (`:116`).
- `lib/ui/layouts/time_layout.dart:146-149` — `controller.matches.isEmpty ? GuideEmpty(controller: controller) : _grid(context)`.
- `lib/ui/layouts/showcase_layout.dart:66-86` — same shape, `LibraryEmpty` at `:98`.
- `lib/ui/layouts/curtain_layout.dart:40-71` — **no empty branch at all**; always renders
  `controller.selected`. So the title screen needs a new arm rather than a third one, which
  contradicts `CLAUDE.md`'s "one arm of an existing conditional per surface".

`ProviderNotice`'s own doc (`lib/ui/components/provider_notice/provider_notice.dart:28-32`) says it
goes "where `GuideEmpty` goes: inside the body branch, under the pinned toolbar".

## Where a client gets bound

- `lib/app/providers/app_service_provider.dart:15-28` — `register()` calls `Magic.put(GuideController())`
  and `Magic.put(LibraryController())`. Eager singletons, bound before `Magic.init()` completes so
  the router can pre-build views.
- `lib/app/providers/route_service_provider.dart:24-54` — `boot()` calls `registerAppRoutes()` and,
  outside release, `MagicPreview.register(previewEntries())` + `registerRoutes()`. `boot()` because
  it runs before `MaterialApp` reads `routerConfig`, which locks the route table.

A client that performs I/O cannot be constructed eagerly in `register()` without doing I/O during
init, so where it binds and when it first fetches is an interview decision.
