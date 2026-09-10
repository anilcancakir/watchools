# Execution report

Plan: `playback-layer-watchools-playbackengine-interface`
Branch: `playback-layer`, 12 commits ahead of `origin/master`
Steps: 13 of 13, six waves
Outcome: delivered, gates green, one design decision referred out

## What now exists

A tapped channel plays. The chain is `NowLayout` -> `PlaybackController` ->
`PlaybackEngine` -> libmpv, with the credential never leaving
`ProviderSession` and no member of the interface carrying text at all.

| Layer | Files |
|---|---|
| URL derivation | `xtream_stream_url.dart`, `xtream_credentials.redact` |
| The contract | `playback_engine.dart`, `fake_playback_engine.dart` |
| The implementation | `mpv_playback_engine.dart` |
| The seam | `provider_session.streamUrlFor`, `playbackUserAgent`, `redactProviderSecrets` |
| The controller | `playback_controller.dart` (with `PlaybackFacade`) |
| The screen | `playback_layout.dart`, `playback_view.dart`, `/izle` |

Three absences are deliberate and documented where they bite: no seek, no
duration, no member named position, because a live window has none of the
three and an interface that offers them makes every one of the six coming
implementations lie about it.

## Gates at delivery

| Gate | Result |
|---|---|
| `flutter analyze --fatal-infos --fatal-warnings` | clean |
| `flutter test` | 477 pass, 1 deliberate skip |
| Coverage (CI's own script, scaffold excluded) | 2425/2524 = 96.1%, floor 90% |
| `dart format lib test` | clean |
| Plugin tests | 16/16 |
| Mock panel verifier | all checks passed |
| Committed lock, `source: path` count | 1, equal to HEAD |
| `flutter build macos --debug` | exit 0, run manually because CI compiles no Swift |
| Running app walk | `/` -> `/izle` -> back -> `/izle` again, clean both visits |

## What the review round changed

Twelve findings fixed, two further defects found while fixing them, one
referred out. `review-log.md` carries the table. The three that mattered:

The native side stops the core when it prunes a platform view and says nothing
about it, so Dart believed it still held a live surface after every route pop.
`PlaybackController.detach` is where it catches up, and it closes three
symptoms at once: the dead view id on the second visit, the connection gate
latching shut for the life of the process, and the wakelock outliving its core.

The chrome was washing the picture with two scrims built for a still image
behind a text block. Both are gone.

Redaction lost a token two ways, and neither was the one the report named
first: a binary signature made the strict UTF-8 decode throw, and the run
class admitted `=` so the match reached back through `token=` and decoded to
nothing. Both reproduced before they were patched.

## Referred out

The chrome's panel is 72 percent black, the theme's own `bg-scrim-strong`.
`DESIGN.md:441-442` says never heavier than 40. The theme ships exactly two
scrim weights, 45 and 72, and records 72 as what a line of text needs over a
frame whose brightness we do not control, so one of the two numbers is wrong
and only a design call settles which. What this plan honoured is the half it
could: nothing washes the frame.

## Reported out of the ecosystem

- CI compiles no Swift at all (`ci.yml:23`, `:150` are `ubuntu-latest`), so
  step 4's whole deliverable needed a manual macOS build.
- magic's `ConsoleLoggerDriver.log` files an unknown level as debug
  (`console_logger_driver.dart:41`), so mpv's `warn` would land below a
  release build's threshold. Mapped locally in `MpvPlaybackEngine._receive`.
- `.gitignore`'s `.swiftpm/` does not match Xcode's `xcshareddata/swiftpm/`,
  which is why two untracked directories sit in the tree after a macOS build.
- `/saglayici` is registered nowhere. All six references in `lib/` are call
  sites, so the fault panel's settings button on five layouts falls through to
  `/`. It is the onboarding screen `CLAUDE.md` records as not existing yet.

## Not done, deliberately

Publishing Wind (`release/1.5.3`, PR #203) and bumping the constraint here.
Outward-facing, and outside the standing authorisation for this run. Until it
lands, `WAnchor`'s `ActivateIntent` binding exists only in an unreleased
commit, so what CI builds has the focus ring and not the D-pad activation.
