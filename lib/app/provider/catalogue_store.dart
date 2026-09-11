import 'dart:convert';

import 'package:magic/magic.dart';
import 'package:sqlite3/common.dart';

import '../models/channel.dart';
import '../models/title_item.dart';
import '../protocol/xtream/xtream_credentials.dart';
import '../protocol/xtream/xtream_json.dart';

/// The cached catalogue: one table per kind, keyed by the account.
///
/// ## What this is for
///
/// Cold start and nothing else. The controllers filter, search and section the
/// catalogue in Dart over an in-memory list, and the Magic query builder could
/// not express those filters anyway (no `like`, no `whereIn`), so SQLite's only
/// job here is that a line-up and a catalogue survive a restart. That is why
/// there are no queries in this file beyond "everything for this account", why
/// no column exists to be filtered on, and why the ORM's missing
/// `Blueprint.index()` does not matter: an index would cost write time on
/// 41,000 rows and serve no read.
///
/// ## Every provider string is bound
///
/// A refresh carries 41,000 channel names, category names and descriptions
/// from a host the user typed, so this is the one surface in the app where
/// untrusted third-party text reaches SQL. Two rules hold throughout and both
/// are executable in `catalogue_store_test.dart`:
///
/// - **No SQL string in this file is interpolated.** Every statement is a
///   literal, table and column names included, which makes the property
///   greppable rather than a claim.
/// - **Every statement carrying a value carries a params list.** That is not a
///   style rule. `DB.statement` with an EMPTY params list reaches
///   `sqlite3_exec` (`sqlite3-3.5.2/lib/src/implementation/database.dart:287`,
///   verified at the resolved version), whose own comment says it "can run
///   multiple statements at once", so one interpolated value there is arbitrary
///   DDL rather than a widened `WHERE`. A non-empty list goes to
///   `prepare(sql, checkNoTail: true)` instead, which rejects a trailing
///   statement, so passing params IS the anti-stacking defence. [migrate] is
///   the only method that passes none, and its DDL carries no value at all.
///
/// ## The bulk path
///
/// One prepared statement per table, reused per row, inside one
/// `DB.transaction`. `insertAll` runs an `INSERT` plus a
/// `SELECT last_insert_rowid()` per row (`magic/query_builder.dart:302`), which
/// is 76,494 statements for 38,247 titles, and `DB` exposes no `prepare`, so
/// the connection is reached directly. This is the only sanctioned direct reach
/// past a magic facade in the app.
///
/// No multi-row `VALUES` list and therefore no chunking: one row per `execute`
/// binds 9 or 15 variables against a measured cap of 32,766 on this build
/// (32,767 answers "too many SQL variables"; the folklore 999 is two SQLite
/// releases stale), so the cap cannot be approached and there is no row count
/// to guess.
///
/// The write is **synchronous and uninterrupted**: `DB.transaction` wraps a
/// synchronous BEGIN/COMMIT around an async callback, so an `await` inside it
/// would leave the transaction open for any other query in the app to join.
/// The callbacks below are deliberately NOT `async` and return
/// `Future.value()`, which makes adding an `await` a compile error rather than
/// a silent open transaction. One microtask boundary remains, between the last
/// row and the COMMIT, because `DB.transaction` awaits the callback's future;
/// it is named here rather than left to be discovered.
///
/// ## What is NOT persisted, and why
///
/// **A channel's schedule.** `Programme.startMinute` is minutes since the
/// schedule's reference midnight, never wrapped, and that reference is chosen
/// by whoever built the schedule. A persisted `1470` therefore means a
/// different absolute instant tomorrow than it did today, so a window restored
/// without its reference date is silently wrong by however many days passed.
/// The EPG in scope is a now/next window fetched per on-screen channel, stale
/// within the hour, so caching it buys nothing on cold start and costs that
/// correctness problem. [channelsFor] restores an empty schedule, which is
/// correct rather than lossy: it is the same state a channel the provider sent
/// no EPG for is already in, and two in five real channels are in it.
///
/// **A channel's status.** Computed, never stored, because a stored status is a
/// stale status: `Channel.fromXtream` derives it from the schedule against a
/// `GuideClock` so it stays right when the clock moves. With no cached
/// schedule the only honest answer is [ChannelStatus.idle], which is exactly
/// what `Channel.fromXtream` returns for an empty schedule.
///
/// **A title's cast and episodes.** `get_vod_streams` populates neither (the
/// detail actions do, and those are deferred), so on a refresh both arrive
/// empty and a child table would hold nothing. The cost is that a per-episode
/// resume position would not survive a restart; nothing writes one yet, and
/// when `get_series_info` lands it brings its own table with it.
///
/// ## User state
///
/// A channel's `favourite` and a title's `favourite` plus `progress` are the
/// only things in this system the user created, and preserving them across a
/// refresh is the whole reason they are separate columns. Every `replace`
/// reads the starred and part-watched rows before deleting and re-applies them
/// by provider identity: `stream_id` for a channel, `(kind, provider_id)` for
/// a title, because a movie's `stream_id` and a series' `series_id` are
/// different ID spaces that collide numerically. A row whose provider
/// identifier is null keeps no user state across a refresh, because there is
/// nothing stable to key it on; a real panel sends one on every entry.
class CatalogueStore {
  /// Creates a store. Stateless: the connection is resolved per call, so an
  /// instance holds nothing a test or a hot restart could leave stale.
  const CatalogueStore();

  /// The account a cached row belongs to: the panel URL and the username,
  /// **never the password**.
  ///
  /// Both halves are percent-encoded before being joined with a `/`, which
  /// makes the key injective: `baseUrl` ending in `/b` with username `c`
  /// cannot collide with `baseUrl` plus username `b/c`, because
  /// [Uri.encodeComponent] escapes the separator inside each half.
  ///
  /// The password is excluded on purpose rather than by omission. This value is
  /// written into a plain SQLite row, which is the one place a credential must
  /// never sit, and it is also the string that would appear in any diagnostic
  /// naming which account a refresh failed for.
  static String accountKey(XtreamCredentials credentials) =>
      '${Uri.encodeComponent(credentials.baseUrl)}/${Uri.encodeComponent(credentials.username)}';

  /// Creates both tables if they are not already there.
  ///
  /// Idempotent, and the only method here that passes no params: the DDL below
  /// carries no value of any kind, so there is nothing for an empty params list
  /// to widen. Call it once per session before anything else; there is no lazy
  /// creation, so a missing call fails loudly on the first read rather than
  /// re-checking the schema on every one.
  ///
  /// No primary key and no index, deliberately. The only read is "everything
  /// for this account", which is a scan whatever the schema says, and the only
  /// write is a full delete plus insert. An index would cost time on 41,000
  /// inserts and serve nothing.
  ///
  /// `group_name` rather than `group` because `GROUP` is a SQLite keyword and
  /// the alternative is a quoted identifier in six statements.
  void migrate() {
    DB.statement('''
      CREATE TABLE IF NOT EXISTS catalogue_channels (
        account TEXT NOT NULL,
        stream_id INTEGER,
        number INTEGER NOT NULL,
        name TEXT NOT NULL,
        group_name TEXT NOT NULL,
        logo_url TEXT,
        facts TEXT NOT NULL,
        catchup_days INTEGER,
        favourite INTEGER NOT NULL
      )
    ''');

    DB.statement('''
      CREATE TABLE IF NOT EXISTS catalogue_titles (
        account TEXT NOT NULL,
        kind TEXT NOT NULL,
        provider_id INTEGER,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        year INTEGER NOT NULL,
        poster_url TEXT,
        backdrop_url TEXT,
        minutes INTEGER,
        rating REAL,
        genres TEXT NOT NULL,
        synopsis TEXT,
        facts TEXT NOT NULL,
        progress REAL NOT NULL,
        favourite INTEGER NOT NULL
      )
    ''');
  }

  /// Replaces [account]'s cached line-up with [channels], carrying starred
  /// channels over.
  ///
  /// Atomic: the delete and every insert are in one transaction, so a throw
  /// part way through leaves the previous line-up intact rather than a
  /// half-written one.
  Future<void> replaceChannels({required String account, required List<Channel> channels}) => DB.transaction(() {
    final Map<int, bool> starred = _starredChannels(account);

    DB.statement('DELETE FROM catalogue_channels WHERE account = ?', <Object?>[account]);

    final CommonPreparedStatement insert = _connection.prepare(
      'INSERT INTO catalogue_channels '
      '(account, stream_id, number, name, group_name, logo_url, facts, catchup_days, favourite) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );

    try {
      for (final Channel channel in channels) {
        insert.execute(<Object?>[
          account,
          channel.streamId,
          channel.number,
          channel.name,
          channel.group,
          channel.logoUrl,
          jsonEncode(channel.facts),
          channel.catchupDays,
          _flag(starred[channel.streamId] ?? channel.favourite),
        ]);
      }
    } finally {
      insert.close();
    }

    return Future<void>.value();
  });

  /// Replaces [account]'s cached catalogue with [titles], carrying starred and
  /// part-watched titles over.
  Future<void> replaceTitles({required String account, required List<TitleItem> titles}) => DB.transaction(() {
    final Map<String, _TitleState> kept = _keptTitleState(account);

    DB.statement('DELETE FROM catalogue_titles WHERE account = ?', <Object?>[account]);

    final CommonPreparedStatement insert = _connection.prepare(
      'INSERT INTO catalogue_titles '
      '(account, kind, provider_id, name, category, year, poster_url, backdrop_url, minutes, rating, '
      'genres, synopsis, facts, progress, favourite) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );

    try {
      for (final TitleItem title in titles) {
        final int? providerId = title.providerId;
        final _TitleState? carried = providerId == null ? null : kept[_titleKey(title.kind, providerId)];

        insert.execute(<Object?>[
          account,
          title.kind.name,
          providerId,
          title.name,
          title.category,
          title.year,
          title.posterUrl,
          title.backdropUrl,
          title.minutes,
          title.rating,
          jsonEncode(title.genres),
          title.synopsis,
          jsonEncode(title.facts),
          carried?.progress ?? title.progress,
          _flag(carried?.favourite ?? title.favourite),
        ]);
      }
    } finally {
      insert.close();
    }

    return Future<void>.value();
  });

  /// [account]'s cached line-up, in the order it was written.
  ///
  /// `ORDER BY rowid` states insertion order as a contract rather than relying
  /// on it being the scan order, which it happens to be. The provider's own
  /// ordering is the one the line-up screens render in.
  List<Channel> channelsFor(String account) {
    final List<Map<String, dynamic>> rows = DB.select(
      'SELECT stream_id, number, name, group_name, logo_url, facts, catchup_days, favourite '
      'FROM catalogue_channels WHERE account = ? ORDER BY rowid',
      <Object?>[account],
    );

    return <Channel>[
      for (final Map<String, dynamic> row in rows)
        Channel(
          number: _requiredInt(row, 'number'),
          name: _requiredString(row, 'name'),
          group: _requiredString(row, 'group_name'),
          status: ChannelStatus.idle,
          logoUrl: readNullableString(row, 'logo_url'),
          facts: _stringList(row, 'facts'),
          favourite: _requiredInt(row, 'favourite') != 0,
          streamId: readInt(row, 'stream_id'),
          catchupDays: readInt(row, 'catchup_days'),
        ),
    ];
  }

  /// [account]'s cached catalogue, in the order it was written.
  List<TitleItem> titlesFor(String account) {
    final List<Map<String, dynamic>> rows = DB.select(
      'SELECT kind, provider_id, name, category, year, poster_url, backdrop_url, minutes, rating, '
      'genres, synopsis, facts, progress, favourite '
      'FROM catalogue_titles WHERE account = ? ORDER BY rowid',
      <Object?>[account],
    );

    return <TitleItem>[
      for (final Map<String, dynamic> row in rows)
        TitleItem(
          kind: TitleKind.values.byName(_requiredString(row, 'kind')),
          name: _requiredString(row, 'name'),
          category: _requiredString(row, 'category'),
          year: _requiredInt(row, 'year'),
          posterUrl: readNullableString(row, 'poster_url'),
          backdropUrl: readNullableString(row, 'backdrop_url'),
          minutes: readInt(row, 'minutes'),
          rating: readDouble(row, 'rating'),
          genres: _stringList(row, 'genres'),
          synopsis: readNullableString(row, 'synopsis'),
          facts: _stringList(row, 'facts'),
          progress: _requiredDouble(row, 'progress'),
          favourite: _requiredInt(row, 'favourite') != 0,
          providerId: readInt(row, 'provider_id'),
        ),
    ];
  }

  /// Stars or unstars the channel [streamId] identifies.
  ///
  /// Keyed on `stream_id` rather than on the channel number, because a refresh
  /// renumbers channels and the star has to follow the channel.
  void setChannelFavourite({required String account, required int streamId, required bool favourite}) {
    DB.statement('UPDATE catalogue_channels SET favourite = ? WHERE account = ? AND stream_id = ?', <Object?>[
      _flag(favourite),
      account,
      streamId,
    ]);
  }

  /// Stars or unstars a title. [kind] is load-bearing: it says which ID space
  /// [providerId] came from, and the two collide numerically.
  void setTitleFavourite({
    required String account,
    required TitleKind kind,
    required int providerId,
    required bool favourite,
  }) {
    DB.statement(
      'UPDATE catalogue_titles SET favourite = ? WHERE account = ? AND kind = ? AND provider_id = ?',
      <Object?>[_flag(favourite), account, kind.name, providerId],
    );
  }

  /// Records how far through a title the viewer got, 0 to 1.
  void setTitleProgress({
    required String account,
    required TitleKind kind,
    required int providerId,
    required double progress,
  }) {
    DB.statement(
      'UPDATE catalogue_titles SET progress = ? WHERE account = ? AND kind = ? AND provider_id = ?',
      <Object?>[progress, account, kind.name, providerId],
    );
  }

  /// The starred channels of [account], by `stream_id`.
  ///
  /// Only the starred rows, so the map is a handful of entries rather than
  /// 2,976: a channel absent from it takes whatever the refresh sent, which for
  /// a `Channel.fromXtream` channel is `false`.
  Map<int, bool> _starredChannels(String account) {
    final List<Map<String, dynamic>> rows = DB.select(
      'SELECT stream_id FROM catalogue_channels '
      'WHERE account = ? AND stream_id IS NOT NULL AND favourite = 1',
      <Object?>[account],
    );

    return <int, bool>{for (final Map<String, dynamic> row in rows) _requiredInt(row, 'stream_id'): true};
  }

  /// The starred and part-watched titles of [account], by [_titleKey].
  Map<String, _TitleState> _keptTitleState(String account) {
    final List<Map<String, dynamic>> rows = DB.select(
      'SELECT kind, provider_id, progress, favourite FROM catalogue_titles '
      'WHERE account = ? AND provider_id IS NOT NULL AND (favourite = 1 OR progress > 0)',
      <Object?>[account],
    );

    return <String, _TitleState>{
      for (final Map<String, dynamic> row in rows)
        _titleKey(TitleKind.values.byName(_requiredString(row, 'kind')), _requiredInt(row, 'provider_id')): _TitleState(
          progress: _requiredDouble(row, 'progress'),
          favourite: _requiredInt(row, 'favourite') != 0,
        ),
    };
  }

  /// A title's identity across a refresh. Both halves are ours (an enum name
  /// and an integer), so no provider string reaches this key.
  static String _titleKey(TitleKind kind, int providerId) => '${kind.name}|$providerId';

  /// The live connection, for the one thing `DB` does not expose.
  ///
  /// Mirrors `DB`'s own resolution (`magic/lib/src/facades/db.dart:56-61`): the
  /// container's `db` singleton when the app booted one, the [DatabaseManager]
  /// singleton otherwise. Both are the same object, since
  /// `database_service_provider.dart:17` binds `() => DatabaseManager()` and
  /// that constructor returns a singleton, so a prepared statement taken here
  /// runs inside the transaction `DB.transaction` opened.
  static CommonDatabase get _connection =>
      (Magic.bound('db') ? Magic.make<DatabaseManager>('db') : DatabaseManager()).connection;

  /// SQLite has no boolean type, so a flag is an integer column.
  static int _flag(bool value) => value ? 1 : 0;

  /// A `NOT NULL` integer column. The `!` is the schema's guarantee rather than
  /// a hope: these readers are shared with the wire layer, where a missing
  /// field is normal, and here it cannot happen.
  static int _requiredInt(Map<String, dynamic> row, String column) => readInt(row, column)!;

  /// A `NOT NULL` real column. Read through [num] like everything else, because
  /// on web `int` and `double` share one float and a bound `0` comes back
  /// either way.
  static double _requiredDouble(Map<String, dynamic> row, String column) => readDouble(row, column)!;

  /// A `NOT NULL` text column.
  static String _requiredString(Map<String, dynamic> row, String column) => readNullableString(row, column)!;

  /// A `List<String>` column, stored as a JSON array.
  ///
  /// JSON rather than a separator because a provider's genre or fact really can
  /// contain a comma, and the encoded string is bound like every other value,
  /// so the encoding adds no SQL surface.
  static List<String> _stringList(Map<String, dynamic> row, String column) {
    final List<Object?> values = jsonDecode(_requiredString(row, column)) as List<Object?>;

    return <String>[for (final Object? value in values) value as String];
  }
}

/// The user state a refresh has to carry over for one title.
class _TitleState {
  /// How far through the viewer got, 0 to 1.
  final double progress;

  /// Whether the user starred it.
  final bool favourite;

  const _TitleState({required this.progress, required this.favourite});
}
