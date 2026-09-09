# Vault and the raw SQL path (ac:explore)

Paths in `/Users/anilcan/Code/fluttersdk/magic`. **One claim from this report was refuted; see
`verification-log.md` before using the Vault section.**

## (A) Vault

| Member | Signature |
|---|---|
| `lib/src/facades/vault.dart:17` | `put(String key, String value)` async |
| `:24` | `get(String key)` async, `Future<String?>` |
| `:29` | `delete(String key)` async |
| `:36` | `flush()` async, all keys |

Backed by `FlutterSecureStorage` (`lib/src/security/magic_vault_service.dart:24-29`), configured
for the iOS keychain and Android `EncryptedSharedPreferences`. Throws
`MagicVaultException(message, originalError)` on a `PlatformException` (`:4-13`).

**Strings only.** A credential pair plus a panel URL has to be serialised before `put` and parsed
after `get`, so the record shape is ours to define.

**Web: supported, but weaker.** The report claimed no web implementation; refuted, five platform
packages resolve including `flutter_secure_storage_web` (`magic/pubspec.lock:334`). What is true is
that the web implementation is IndexedDB plus a WebCrypto key rather than a keychain, so
same-origin JavaScript can reach the key material. A decision for the interview, not a blocker.

## (B) The raw storage path

| Member | Signature |
|---|---|
| `lib/src/facades/db.dart:105` | `static void statement(String sql, [List<Object?> params = const []])`, synchronous |
| `lib/src/facades/db.dart:183` | `static Future<T> transaction<T>(Future<T> Function() callback)`, BEGIN/COMMIT, rollback on throw |
| `lib/src/facades/db.dart:~111` | `DB.insert(sql, params)` returns the last insert id |

Parameter binding works throughout (`query_builder.dart:287`, `:330`): `?` placeholders bound from
the params list. Mandatory here, since provider names and descriptions are untrusted input.

**`CLAUDE.md`'s three ORM claims all verified against current source:**

- `Blueprint` (`blueprint.dart:152-248`) offers `id`, `string`, `text`, `integer`, `bigInteger`,
  `boolean`, `real`, `blob`, `timestamps`, `dropColumn`, `renameColumn`. **No `index()`.** An index
  needs `DB.statement('CREATE INDEX ...')` after the table exists.
- No `whereIn`, `like` or `join` on the query builder; only `where`, `whereNull`, `whereNotNull`.
- `insertAll` (`query_builder.dart:302-306`) is `for (final record in records) { await insert(record); }`.

**The real cost is the per-row shape, not the API.** Each `insert` runs an `INSERT` **and** a
`SELECT last_insert_rowid()` (`query_builder.dart:274-292`), so two statements per row:

| Rows | Statements through `insertAll` |
|---|---|
| 2,976 live channels | 5,952 |
| 38,247 VOD titles | 76,494 |

And by default each pair lands outside a transaction, paying a disk sync per row. Two ways out,
both available today: wrap in `DB.transaction` to collapse the syncs, or build multi-row
`INSERT ... VALUES (?,?),(?,?),...` and run it through `DB.statement`, which also removes the
per-row `SELECT`. The second is what a 38,000-row write needs.

A sibling `insertMany` that builds multi-row SQL is the clean fix and is a separate PR per
`.claude/rules/workflow.md`. Worth filing either way; not a prerequisite, because `DB.statement`
already reaches the same place.
