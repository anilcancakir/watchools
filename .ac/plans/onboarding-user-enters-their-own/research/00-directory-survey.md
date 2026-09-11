# Directory survey

Run by the main agent at Stage 1a. This planner already carries a deep read of this
codebase from the session that built the playback layer and the development-credential
path, so this survey records the map that matters for onboarding rather than re-deriving
the whole tree.

## Top-level structure

```
lib/
  app/
    commands/ controllers/ models/ playback/ protocol/xtream/ provider/ providers/ support/
  config/
  resources/views/
  routes/
  ui/components/<17 atomic folders>/ ui/layouts/ ui/layouts/support/
backend/            Laravel 13, out of scope for onboarding
macos/Runner/       entitlements + Xcode project, IN scope (Keychain)
packages/watchools_player/   in-repo libmpv plugin
tool/xtream-mock/   local panel serving real video
tool/dev/           run_with_provider.sh, the --dart-define launcher
```

## Language / stack markers

- `pubspec.yaml`: Flutter 3.47 / Dart 3.13, six platforms. `fluttersdk_wind: ^1.5.0`,
  `magic`, `magic_devtools`, `watchools_player` (path), `wakelock_plus`.
- `analysis_options.yaml:51`: `unawaited_futures: error`. Analyze runs
  `--fatal-infos --fatal-warnings`.
- `CLAUDE.md`: the authority. Wind owns styling, magic owns everything below the widget,
  `Vault` is where secrets go, `.env.local` + `--dart-define` is the development
  credential path, and **`Vault` cannot write on macOS**.
- `.claude/rules/workflow.md`: branch + worktree + PR flow, three review rounds max on a
  sibling PR.

## Project conventions in force for this topic

- Screens split: a thin `MagicStatefulView` in `lib/resources/views/` (excluded from the
  CI coverage denominator) over a layout in `lib/ui/layouts/` (inside it, and where the
  behaviour and the tests go).
- Routes registered in `registerAppRoutes()` (`lib/routes/app.dart`), read by
  `RouteServiceProvider.boot()`. A route added after the router builds is silently absent.
- Wind only: `className` strings, `W`-prefixed widgets, semantic colour aliases. Never
  `Colors.*` or `Color(0x...)`.
- Widget tests go through `pumpScreen` (`test/support/screen.dart`) with
  `setUp(WindParser.clearCache)`. The test font makes every glyph a square, so overflow
  assertions are meaningless and a size assertion is the reliable one.
- Coverage floor 90% over a denominator excluding the generated scaffold; currently
  2443/2542 = 96.1%.

## What already exists for onboarding

| Piece | Where | State |
|---|---|---|
| The destination screen | `lib/ui/layouts/provider_settings_layout.dart` | placeholder, says the screen is not ready, deliberately no form |
| Its mounting half | `lib/resources/views/provider_settings_view.dart` | plain `StatelessWidget`, no controller |
| The route | `lib/routes/app.dart` | `/saglayici`, registered, titled `Sağlayıcı` |
| The credential record | `lib/app/protocol/xtream/xtream_credentials.dart` | `save`, `load`, `clear`, `fromEnvironment`, `redact`, base URL validation |
| The session | `lib/app/provider/provider_session.dart` | `start`, `refresh`, `hasCredentials`, `fault`, `streamUrlFor`, `_developmentCredential` seam |
| The handshake | `lib/app/protocol/xtream/xtream_client.dart` | `handshake()`, own `provider_network` driver |
| Fault classification | `lib/app/protocol/xtream/xtream_account.dart` | `classifyProviderFault(account, statusCode, body)` |
| The fault surface | `lib/ui/components/provider_notice/` | four faults rendered, `onOpenSettings` already points at `/saglayici` |
| A real panel to test against | `tool/xtream-mock/` | 8 channels, real video, `demo:demo` |

## The blocker this plan has to clear

`Vault` is the Keychain and cannot write on macOS: every `Vault.put` fails with
OSStatus -34018, "A required entitlement isn't present". Measured through the running app
with the sandbox on and off. Adding `keychain-access-groups` makes the build fail with
`"Runner" has entitlements that require signing with a development certificate`. The user
has supplied Apple Developer team ID `883V9SVA54`.

## Provisional research angles

1. Does any form with validation exist in this app yet, and what is the Wind idiom for one
   (`WInput` vs `WFormInput`, `Form` + `GlobalKey`, error rendering)?
2. What exactly does a sandboxed macOS Flutter app need for Keychain access:
   `keychain-access-groups` alone, `DEVELOPMENT_TEAM`, a signing identity, and does
   `flutter_secure_storage` document more?
3. What is magic's `Vault` contract on failure, and is there any capability probe?
4. How do existing widget tests drive a text field on this project, and what does
   `search_focus_test.dart` record about focus surviving a rebuild?
5. Who reads `hasCredentials`, and what has to happen on sign-out: the catalogue store, the
   anchored clock, the playback controller, the four screens.
6. What is the honest reuse set: the placeholder screen, `ProviderNotice`,
   `classifyProviderFault`, `XtreamClient.handshake`, `XtreamCredentials` validation.
7. Does a first-run route exist anywhere, or does the app always land on `/`?
