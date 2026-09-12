## Wave 1

- **[REMEDIATION] A new file's own contract had no test, and the step that created it was green.** The worker
  added `BackgroundPlayback.parse` and `storedValue`, both of them contracts steps 2 to 4 depend on, and every
  test it wrote lived in `xtream_credentials_test.dart` and exercised the CREDENTIAL's round trip instead. The
  key-absent test passes `null` to the constructor directly, so it never calls `storedValue` at all. Zero tests
  touched the enum. This is `host_lookup_io.dart` at 2/47 lines repeating: a file whose parser had never
  executed. Added `test/app/models/background_playback_test.dart`, 7 cases, each proved red with the fix
  removed. The lesson for the remaining waves: when a step creates a file, check that the file's own members
  are tested, not only the caller that consumes them.
- **A step's Files list is a coverage decision nobody makes on purpose.** Step 1 listed three files and none was
  a test for the new one, so the plan itself is what left the gap. Check a `Files` list for a missing test path
  before spawning, not after verifying.
- **The strongest test of a two-sided enum is the round trip over `values`.** `for (final choice in
  BackgroundPlayback.values) expect(parse(choice.storedValue), choice)` catches a member added to `parse` and
  not to `storedValue`, which is exactly the drift a hand-written per-member test cannot see.
- **`'key': ?value` needs a nullable producer to be reachable.** `storedValue` returning `String?` with null for
  the default is what stops every credential blob gaining a key for users who never chose. A non-nullable
  getter would have made the omission dead code, and the test that was supposed to catch it did not, because it
  bypassed the getter.

## Wave 2

- **`AppLifecycleListener.dispose` throws on a second call**, `assert(_debugAssertNotDisposed())` at
  `app_lifecycle_listener.dart:179`, verified at source. `PlaybackEngine` promise 7 makes `dispose`
  idempotent, so the field has to be nullable and cleared rather than `late final`. The plan did not
  anticipate this and the worker found it; without the clear, four tests go red, two of them pre-existing.
- **A declared `tearDown` runs AFTER an `addTearDown` registered inside the test.** Declared ones register
  before the body (`declarer.dart:241-248`) and tearDowns run LIFO (`invoker.dart:296`). That ordering is what
  lets the binding be walked back to `resumed` after `engine.dispose` has removed the listener, rather than
  past a live one. My briefing had said `addTearDown`; the worker's shape is the correct one.
- **The binding's lifecycle state outlives a case in a plain-`test()` file.** `postTest`, which resets it, is
  registered only by `WidgetTester` (`widget_tester.dart:183`). The symptom is NOT the
  `Invalid state transition` I predicted: left at `paused`, the next case's walker drives no transition at all
  and its engine simply never hears one, so two arm cases fail silently. Same cause, quieter failure, which
  makes it worse rather than better.
- **The discriminating assertion for "did the core stay open" is a tick pushed afterwards**, not a method-call
  list. `expect(calls, isEmpty)` alone would pass for an engine that never had a core; `push(_tickEvent(...))`
  then `expect(health, playing)` is what separates "still open" from "never was".
- **A doc-block sentence that a change falsifies is part of the change.** The class doc said this engine "owns
  no policy the others would have to copy"; the lifecycle branch makes that false, and the worker corrected it
  in the same diff rather than leaving it for a later reader to trip over.

## Wave 3

- **[REMEDIATION] `withBackgroundPlayback` shipped with no test of its own**, because the credential test file
  was not in the step's Files list. The worker flagged it rather than expanding scope, which is the right
  call, and the gap was real: dropping `resolver:` from the rebuild turns nothing red without it. Added three
  cases, the first proved red by dropping exactly that line. Second wave running in a row where a new member
  went untested because a Files list did not name its test file.
- **A rebuild-through-the-constructor is a field-dropping bug waiting to happen.** The assertion that matters
  is not "the new value is set" but "every OTHER field came through", and the one most likely to be dropped is
  the other optional one, because it is the one a user chose deliberately.
- **`setBackgroundPlayback` can throw `MagicVaultException`**, since `save()` is a keychain write and macOS
  refuses it on a build with no entitlement (OSStatus -34018). `submit` already catches it and renders a field
  message. The picker in the next wave must AWAIT this call and surface a failure rather than fire-and-forget
  from `onChange`, or a user on a refusing keychain sees the picker move and nothing persist.
- **The composition root stays untestable on purpose, and that is the argument for keeping it a
  one-expression delegation.** `app_service_provider.dart` is outside the CI coverage denominator; the wiring
  is `backgroundPlayback: () => session.backgroundPlayback`, so the behaviour is asserted where it can be, on
  `ProviderSession.backgroundPlayback` itself. The failure this avoids is the one CLAUDE.md records: two
  transcriptions of the connection gate drifted apart and deleting a clause of the real gate turned nothing red.
- **An unused constructor parameter on a test double is an analyzer error here**, `unused_element_parameter`
  under `--fatal-warnings`. A field default is the shape that satisfies "settable, defaults to X" without one.

## Wave 4

- **The honesty line shipped and it is checkable.** `_backgroundPlaybackScope` says stop works everywhere,
  and that audio and picture-in-picture aim to keep the connection open but the platform half is finished on
  no device, so macOS keeps playing either way and mobile treats the two identically today. The test greps
  `'platform tarafı'`, so deleting the sentence turns a test red rather than quietly shipping a lie.
- **An async `onChange` needs an extra `pump()` past `pumpAndSettle()`.** The handler awaits the facade, so
  the state it writes back (a revert, or the recorded write) lands a microtask after the tap that
  `pumpAndSettle` alone does not guarantee to flush. The test file's own helper records this.
- **The refusal path renders through a seam that already existed.** `fieldError` at
  `provider_settings_layout.dart:232` is `_localFieldError ?? widget.provider.fieldError`, so a screen-local
  refusal reaches the same banner a facade refusal does, with nothing new built.
- **[MINOR, not fixed] The honesty note is wrapped in a `WDiv(className: 'flex flex-col gap-1')` holding a
  single `WText`.** `gap-1` does nothing with one child. It mirrors `_resolverScopeNote`, which has a
  conditional second child and needs the wrapper; this one does not. Cosmetic, left alone deliberately rather
  than diverging from the sibling shape for one line.

## Wave 5

- **A `quick`/haiku worker stalled for fifteen minutes on a two-paragraph prose step and wrote nothing.** It
  never got past its first sentence. Neither target file was large (210 and 714 lines). Escalating to
  `junior` finished the same briefing in 43 seconds with 11 tool calls. The signal that decided it was
  `git status --porcelain` staying empty: for a step whose whole output is file edits, an empty working tree
  after fifteen minutes is a stall, not slow progress.
- **The retry briefing is worth a Section 0.** Saying "a previous worker stalled, nothing survives, you are
  starting from scratch" plus an explicit efficiency instruction ("grep the 714-line file, do not read it")
  cost four lines and the retry did not repeat the failure.
- **`git diff --stat` is the cheap check that a prose worker only ADDED.** 15 insertions, 0 deletions is the
  whole proof that nothing surrounding was reflowed, which is the failure mode a documentation edit has.
