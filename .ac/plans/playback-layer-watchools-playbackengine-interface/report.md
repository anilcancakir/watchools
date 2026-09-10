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
| `flutter test` | 489 pass, 1 deliberate skip |
| Coverage (CI's own script, scaffold excluded) | 2439/2538 = 96.1%, floor 90% |
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

## The three decisions the user took

**The scrim ceiling: fix the rule, not the tokens.** `DESIGN.md` capped a
player scrim at 40 percent, the theme's own minimum for legible text is 72, and
no token satisfied the cap. What keeps Plex's artwork legible is that nothing
covers it; 40 percent was the document's guess at how to say so. The rule now
says no scrim spans the frame and cites `playback_layout.dart`. No code changed.

**`/saglayici`: ship a minimal placeholder.** Six call sites, no route. There is
now a screen that names what is happening and offers the way back, with no
form, and a route-table test that fails if any path a layout navigates to is
registered nowhere.

**Wind publishing: not now.** The `ActivateIntent` binding stays unreleased, so
what CI builds has the focus ring and not the D-pad activation.

## The oracle round

Six premises tested before merge, three refuted, all three above the interface.
The gate was the sharp one: `refresh` checked its predicate at the door and
then ran roughly 26 requests unguarded, while `boot()` fires that batch
unawaited at every cold start, so a user tapping a channel seconds into launch
played straight through it on a one-connection account. `review-log.md` carries
the table and what each fix was.

## Reported out of the ecosystem

- CI compiles no Swift at all (`ci.yml:23`, `:150` are `ubuntu-latest`), so
  step 4's whole deliverable needed a manual macOS build.
- magic's `ConsoleLoggerDriver.log` files an unknown level as debug
  (`console_logger_driver.dart:41`), so mpv's `warn` would land below a
  release build's threshold. Mapped locally in `MpvPlaybackEngine._receive`.
- `.gitignore`'s `.swiftpm/` does not match Xcode's `xcshareddata/swiftpm/`,
  which is why two untracked directories sit in the tree after a macOS build.
- `/saglayici` was registered nowhere, with six call sites in `lib/`. Fixed in
  this branch with a placeholder screen and a route-table test.
- No `WidgetsBindingObserver` exists anywhere, so on the mobile targets that
  are coming, backgrounding leaves the core, the single connection slot and the
  wakelock held. Issue #27; it belongs with the engine, not the screen.

## Not done, deliberately

Publishing Wind (`release/1.5.3`, PR #203) and bumping the constraint here.
Outward-facing, and outside the standing authorisation for this run. Until it
lands, `WAnchor`'s `ActivateIntent` binding exists only in an unreleased
commit, so what CI builds has the focus ring and not the D-pad activation.
