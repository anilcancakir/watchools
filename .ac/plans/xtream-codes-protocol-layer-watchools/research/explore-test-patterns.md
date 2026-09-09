# Test patterns for a networked client (ac:explore)

## The two support helpers

- `test/support/wind_test_app.dart:34` — `wrapWithTheme(Widget child, {WindThemeData? themeData, Brightness brightness})`,
  for a leaf widget.
- `test/support/screen.dart:44` — `pumpScreen(WidgetTester, Widget, {Size size = desktop})`, a full
  screen at 1440x900 or 414x896 in dark mode, collecting errors through `FlutterError.onError`
  rather than `takeException`.

Neither is needed by a protocol layer, which is pure Dart. Relevant only for the layout steps that
render a fault.

## HTTP faking: first-party, and exercised

Nothing in watchools `test/` fakes HTTP; this layer's tests are the first. The seam is magic's:

- `Http.fake([stubs])` → `FakeNetworkDriver`, stubs by URL-pattern map or callback.
- `Http.response(data, statusCode)` builds a stub.
- `FakeNetworkDriver.assertSent()` and `assertSentCount()` verify calls.
- `Http.unfake()` restores.
- Worked example in magic's own suite: `magic/test/network/http_fake_test.dart:16-56`.

So faking is ready and the request assertions come for free. That matters for the User-Agent
requirement: `assertSent` is how a test proves the header was sent, though see the header-case
defect in `verification-log.md` for what it cannot prove.

## The database under `flutter test`, which the report did not settle

The agent answered for the **Laravel** side (`backend/phpunit.xml:35-36`, in-memory SQLite with
`RefreshDatabase`). For Flutter it found nothing, and my own check confirms **no Flutter test
touches the ORM at all**: `grep -rl 'DB\.\|Model\|sqflite\|database' test/` returns nothing.

What I established instead: magic depends on **`sqlite3` (Dart FFI)** plus
`sqlite3_flutter_libs`, not `sqflite` (`magic/pubspec.yaml:39-40`). `package:sqlite3` loads the
native library directly and works under the Dart VM, so a `flutter test` on macOS should reach the
system libsqlite3. magic ships its own `test/database/` suite (`blueprint_test.dart`,
`migrator_test.dart`, `query_builder_test.dart`, `schema_test.dart`, plus `eloquent/`), which is
evidence that the ORM is testable headlessly.

**Not yet proven in this repo**, and it decides whether the catalogue's write path can be
unit-tested at all. It is cheap to settle with one throwaway test and belongs as an early
plan step rather than an assumption.

Note also `sqlite3_flutter_libs: ^0.6.0+eol` — the `+eol` suffix marks the package end-of-life.
Worth raising with the sibling independently of this plan.

## Test layout and the `.env` trap

Mirror the source path: `test/app/controllers/guide_controller_test.dart`,
`test/app/models/title_item_test.dart`, `test/app/support/guide_clock_test.dart`. Private factory
helpers at the top of the file (`_movie()`, `_series()`, `_ep()` in `title_item_test.dart`), no
cross-file doubles. `setUp` prepares, `tearDown` cleans, one premise per test.

`.env` is a real asset during `flutter test`, so the safe pattern is to override rather than
assert a default (`test/config/app_config_test.dart:15-18`):

```dart
setUp(() async {
  Env.reset();
  await Env.load(mergeWith: <String, String>{'APP_NAME': 'Watchools', ...});
});
```

## The coverage gate, and a useful lever inside it

`.github/workflows/ci.yml:113-145`. Flutter and backend both **90%**, and the Flutter denominator
excludes:

```python
EXCLUDED = ('lib/resources/views/', 'lib/app/providers/', 'lib/app/kernel.dart', 'lib/routes/app.dart')
```

`lib/app/providers/` being excluded is the lever: binding and wiring code placed there carries no
coverage obligation, while the client's own logic must clear 90%. That argues for keeping the
providers thin and the client pure, which is the shape we want anyway.
