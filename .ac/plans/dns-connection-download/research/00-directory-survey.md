# Directory survey

Topic: make the connection fastest, make downloading fastest, and give the user real control over
DNS. The request is `hepsini` against the ten-angle research reported on 2026-09-11.

## Top-level structure

Flutter app at the root, Laravel in `backend/`, one in-repo Flutter plugin in
`packages/watchools_player/` (macOS only: a `macos/` directory and nothing else).

```
lib/app/{commands,controllers,middleware,models,playback,protocol/xtream,provider,providers,support}
lib/{config,resources/views,routes,ui/{components,layouts,layouts/support}}
packages/watchools_player/{lib,macos/watchools_player/Sources/watchools_player,test,example}
test/{app/{controllers,middleware,models,playback,protocol/xtream,provider,support},config,support,ui}
tool/{dev,dusk,web,xtream-mock}
```

Tests mirror the source path exactly.

## Language and stack markers

- `pubspec.yaml`: Flutter 3.47 / Dart 3.13, `magic: ^0.0.10`, `fluttersdk_wind: ^1.5.3`,
  `watchools_player` as a path dependency under `packages/`.
- `pubspec_overrides.yaml` (gitignored, copied into this worktree): resolves the ecosystem siblings
  from `/Users/anilcan/Code/fluttersdk/`.
- `CLAUDE.md`: the project contract. Wind owns styling, magic owns everything below the widget,
  no linter suppression, no fallback catch that swallows, no speculative abstraction.
- `.claude/rules/workflow.md`: worktree plus branch plus PR per task, sibling changes go to the
  sibling repository, review rounds capped at three.
- `.ac/` is **tracked** in this project (74 files), unlike the skill's default assumption. The
  gitignore guard is therefore skipped deliberately.

## Sub-projects

`packages/watchools_player/` is the only one with its own pubspec and its own test suite. It is
ours, in-repo, and not published, so a change there needs no sibling release. `backend/` is a
separate PHP project and is out of scope for this topic.

## External research already in hand

Ten `ac:librarian` briefs ran on exactly this topic immediately before this plan, and their
load-bearing claims were verified against source by the main thread. They are archived at
`external-findings.md` in this directory rather than re-spawned. Re-running them would spend a
second cohort to re-read what is already verified, against the standing rule that a near-miss
already in hand beats a fresh search.

## Provisional research angles

1. What existing code already resolves, caches, or rewrites a URL, and what the app uses for
   timeouts. Reuse map input.
2. How an option reaches libmpv today: the Dart `load` call, the method channel, and
   `MpvEngine.start`'s option dictionary. This is where `http_multiple`, `seekable` and a `Host`
   header would land.
3. Where the stream `Uri` is built and who hands it to the engine. Address pinning has to happen
   between those two points.
4. How a provider-scoped setting is stored and rendered today, with the per-provider User-Agent as
   the worked example, including the `Gelişmiş` disclosure in the settings form.
5. The test patterns covering the engine, the protocol layer and the settings screen, plus the
   existing fakes and what they can and cannot reach.
6. The telemetry path: which `PlayerTick` fields exist, how `StallDetector` reads them, and where a
   throughput verdict would attach without inventing a second health vocabulary.
