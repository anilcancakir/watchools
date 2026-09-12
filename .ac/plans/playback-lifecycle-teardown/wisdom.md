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
