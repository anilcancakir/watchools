# Execution anchors, verified at source during the run

Everything here was opened and read by the orchestrator while a worker was in flight, so a later briefing
can cite it without re-deriving. Anything the plan states loosely is tightened here, and the tightening wins.

## Corrections to the plan's own citations

| Plan says | Actually |
|---|---|
| `platform_dispatcher.dart:2358-2446` for "only entered on iOS and Android" | `/Users/anilcan/flutter/bin/cache/pkg/sky_engine/lib/ui/platform_dispatcher.dart:2444`. The phrase does not appear anywhere under `packages/flutter`, so a briefing pointing there sends a worker to a file that does not contain it |
| wind has no way to mark an option unavailable | `SelectOption` carries `disabled` (`wind/lib/src/widgets/select_option.dart:48-51`). What is missing is a field for the REASON: no note, no description, and `==` covers only `value`, `label`, `disabled` |

## Wave 3: the setting's writer

**The precondition helper already exists.** `test/app/controllers/provider_setup_controller_test.dart` runs the
REAL `ProviderSession` rather than a double: `MagicTest.init()` at `:80`, `DatabaseManager().setConnection(
sqlite3.openInMemory())` and `Vault.fake()` at `:93-94`. Two session builders sit at `:118-135`:

- `emptySession({bool playing})` at `:118`, a started session with no credential
- `configuredSession()` at `:126`, which does `await stored.save()` then starts a session, so the credential is
  already adopted. This is exactly the precondition `setBackgroundPlayback` needs
- `controllerFor(session, {order, hostResolver})` at `:137` builds the controller with the playback seam
  appending to a list instead of reaching an engine

So wave 3's decisive test is short, and `panel.handshakeCalls` (a field on the file's `_MockPanel`) is what
proves the point the whole step exists for:

```dart
final ProviderSession session = await configuredSession();
final ProviderSetupController controller = controllerFor(session);

await controller.setBackgroundPlayback(BackgroundPlayback.audio);

expect((await XtreamCredentials.load())?.backgroundPlayback, 'audio');
expect(controller.backgroundPlayback, BackgroundPlayback.audio);
expect(panel.handshakeCalls, 0);
```

**The getter shape to copy** is `ProviderSession.providerResolution` at `provider_session.dart:249-255`,
which derives from `_credentials` on every read and returns null when there is none. Its doc block at
`:240-248` is the one to match for depth: it explains why the member is public where the credential is not.

**`signOut()` at `:441-470`** nulls `_credentials` at `:444`, so a derive-on-read getter returns `stop`
afterwards with no push. `_pushResolverSetting()` at `:460` exists only because `HostResolver` holds a cached
address that the getter has no equivalent of.

**`adopt()` at `:383-399`** is the only existing writer, `await credentials.save()` at `:384`. It also assigns
`_client`, nulls `_account`, `_fault` and `_inFlight`, pushes the resolver, restores the cached catalogue for
the new account key, and notifies. `setBackgroundPlayback` must do none of that: only rebuild, save, assign,
notify.

**`_normaliseBaseUrl` at `:441-455`** trims, strips trailing slashes and validates. Idempotent on a value it
already produced, so `withBackgroundPlayback` can pass `baseUrl` back through the public constructor.

**The facade is `abstract interface class ProviderSetupFacade`** at `provider_setup_controller.dart:24`, with
`ResolverSetting get resolver` declared at `:52` and `submit` at `:67-73`. Two implementers:
`ProviderSetupController` at `:111` (`extends SimpleMagicController implements ProviderSetupFacade`) and
`_FakeProvider` at `test/ui/layouts/provider_settings_layout_test.dart:21`. The fake's shape: one mutable field
per getter, `submitted` as a record at `:50`, counters `submits` and `signOuts`, and a `Completer<void>? gate`
at `:58` that makes `submit` hang. A new facade member must be answered in BOTH or analyze goes red.

**`submit` stores only past the handshake**: `provider_setup_controller.dart:346-350` reads
`_fault = classifyProviderFault(...)` then `if (_fault != null) return;` before `await _session.adopt(...)`.

## Wave 4: the picker

**Where it goes.** `provider_settings_layout.dart:237-240` is the disclosure block:

```dart
_disclosure(),
if (_advancedOpen) _userAgentField(),
if (_advancedOpen) _resolverField(),
if (_advancedOpen) _resolverScopeNote(),
```

`hasCredential` is already used as a render guard at `:208` (`_backButton`) and `:254` (`_signOutButton`), so
gating the new field on it follows the file's own convention rather than inventing one.

**The picker to copy** is `_resolverField()` at `:325-348`. `WFormSelect<T>` is
`wind/lib/src/widgets/w_form_select.dart:34`, `extends FormField<T>`, which is why `onSaved` exists on it and
why the unmounted-field trap applies. The resolver's own doc block at `:315-324` states the
`onChange`-not-`onSaved` rule in the codebase's own words.

**`placeholder` is not optional.** `WSelect`'s semantics label always prefers it over the selected option's
label (`w_select.dart:517-529`) and its default is the English `'Select an option'`, which is why the resolver
passes a Turkish one. A picker without it ships an English semantics label into a Turkish screen.

**The note shape** is `_resolverScopeNote()` at `:414-423`: a `WDiv` with `flex flex-col gap-1` holding
`WText`s at `text-xs text-fg-muted`.

**The submit path** is `:620-665`. It ends by navigating away on success, which is the second reason the
picker must not ride it: the screen the user just configured closes.

## Wave 6: what the gates can and cannot prove

Measured in this worktree:

- `.env.local` is **absent**; `.env` and `pubspec_overrides.yaml` are present and all three are gitignored
  (`.gitignore:52`, `:58`, `:82`). So the dusk walk cannot reach a configured credential and the vault round
  trip must be recorded NOT RUN
- `git ls-files --error-unmatch` fails for all three, so that gate can fail honestly. `git status --short`
  cannot, because it never prints ignored paths
- `pubspec.lock` carries exactly one `source: path` entry, `watchools_player` with `relative: true`. That is
  the in-repo plugin and it resolves on any machine, so it is NOT the hazard CLAUDE.md warns about, which is a
  sibling under an absolute `/Users/` path. The gate is `git diff --name-only -- pubspec.lock` being empty

## A consequence of wave 2 worth knowing before wave 3

`PlaybackController.holdsConnection` at `playback_controller.dart:255` is
`(_channel != null && !_unplayable) || health != PlaybackHealth.idle`. A background `stop()` takes the engine
to `idle` but leaves the controller's `_channel` set, so the gate keeps reporting that a connection is held
even though the provider slot is free. That is over-reporting, which the same doc block at `:250-254`
explicitly accepts: it costs a skipped catalogue refresh, which the next one fixes. Not a defect, and not
something wave 3 should try to fix.
