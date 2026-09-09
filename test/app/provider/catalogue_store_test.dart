import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/programme.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/provider/catalogue_store.dart';
import 'package:watchools/app/support/scale_fixture.dart';

/// A channel name shaped to break out of a single-quoted SQL literal.
///
/// The table name inside it is this store's real one on purpose: if the string
/// were ever interpolated, the statement would parse, the insert would succeed
/// and the table would be gone, so the gate is "both tables still answer a
/// COUNT" rather than "the write threw".
const String _quoteBreak = "Robert'); DROP TABLE catalogue_channels;--";

/// A string shaped to close a bound row and open a second one.
///
/// This is the multi-row `INSERT ... VALUES (?,?),(?,?)` attack rather than the
/// single-quote one: it only works against SQL that was built by concatenating
/// a row at a time, which is exactly the shortcut a 38,247-row write invites.
const String _rowBreak = '?), (1, (SELECT name FROM catalogue_titles)), (2';

/// Every SQL statement the store handed to the connection, with its bindings.
class _Statement {
  /// The SQL text, as the store wrote it.
  final String sql;

  /// The bound values, empty when the store passed none.
  final List<Object?> params;

  const _Statement(this.sql, this.params);

  /// Whether the statement carries a bind placeholder at all.
  ///
  /// This is what separates the store's control statements (`BEGIN`, `COMMIT`,
  /// the fixed DDL) from every statement that moves a value, and it is the
  /// split the binding gate below is keyed on.
  bool get isParameterised => sql.contains('?');
}

/// What the connection double saw, and where it should fail.
class _Recorder {
  /// Every `execute` and `select` the store ran on the connection, plus every
  /// `execute` on a prepared statement, in order.
  final List<_Statement> ran = <_Statement>[];

  /// Every distinct SQL string the store compiled through `prepare`.
  ///
  /// A set rather than a list, because the assertion that matters is how MANY
  /// distinct statements a thousand-row write compiles: one.
  final Set<String> prepared = <String>{};

  /// Fail the prepared write on this row, 0-based, or never when null.
  int? failOnRow;

  /// How many prepared-statement executes have run since the last reset.
  int rows = 0;
}

/// A [CommonDatabase] that records what the store does to it and delegates the
/// rest to a real in-memory database.
///
/// This exists because the two load-bearing gates in this file cannot be
/// written any other way. `DB.statement` is a static on magic with no seam, so
/// the only place to observe the SQL the store actually emits is the
/// connection [DatabaseManager] hands it, and `setConnection` is magic's own
/// documented seam for exactly that (`database_manager.dart:75`).
class _RecordingDatabase implements CommonDatabase {
  final Database _inner;
  final _Recorder _recorder;

  _RecordingDatabase(this._inner, this._recorder);

  @override
  void execute(String sql, [List<Object?> parameters = const <Object?>[]]) {
    _recorder.ran.add(_Statement(sql, parameters));
    _inner.execute(sql, parameters);
  }

  @override
  ResultSet select(String sql, [List<Object?> parameters = const <Object?>[]]) {
    _recorder.ran.add(_Statement(sql, parameters));

    return _inner.select(sql, parameters);
  }

  @override
  CommonPreparedStatement prepare(String sql, {bool persistent = false, bool vtab = true, bool checkNoTail = false}) {
    _recorder.prepared.add(sql);

    return _RecordingStatement(
      _inner.prepare(sql, persistent: persistent, vtab: vtab, checkNoTail: checkNoTail),
      _recorder,
    );
  }

  @override
  List<CommonPreparedStatement> prepareMultiple(String sql, {bool persistent = false, bool vtab = true}) {
    _recorder.prepared.add(sql);

    return _inner
        .prepareMultiple(sql, persistent: persistent, vtab: vtab)
        .map((PreparedStatement statement) => _RecordingStatement(statement, _recorder))
        .toList();
  }

  @override
  DatabaseConfig get config => _inner.config;

  @override
  int get userVersion => _inner.userVersion;

  @override
  set userVersion(int version) => _inner.userVersion = version;

  @override
  int get lastInsertRowId => _inner.lastInsertRowId;

  @override
  int get updatedRows => _inner.updatedRows;

  @override
  int getUpdatedRows() => _inner.updatedRows;

  @override
  Stream<SqliteUpdate> get updates => _inner.updates;

  @override
  Stream<SqliteUpdate> get updatesSync => _inner.updatesSync;

  @override
  VoidPredicate? get commitFilter => _inner.commitFilter;

  @override
  set commitFilter(VoidPredicate? filter) => _inner.commitFilter = filter;

  @override
  Stream<void> get commits => _inner.commits;

  @override
  Stream<void> get rollbacks => _inner.rollbacks;

  @override
  void createCollation({required String name, required CollatingFunction function}) =>
      _inner.createCollation(name: name, function: function);

  @override
  void createFunction({
    required String functionName,
    required ScalarFunction function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) => _inner.createFunction(
    functionName: functionName,
    function: function,
    argumentCount: argumentCount,
    deterministic: deterministic,
    directOnly: directOnly,
    subtype: subtype,
  );

  @override
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) => _inner.createAggregateFunction<V>(
    functionName: functionName,
    function: function,
    argumentCount: argumentCount,
    deterministic: deterministic,
    directOnly: directOnly,
    subtype: subtype,
  );

  @override
  set busyHandler(bool Function(int count)? handler) => _inner.busyHandler = handler;

  @override
  bool get autocommit => _inner.autocommit;

  @override
  void dispose() => _inner.close();

  @override
  void close() => _inner.close();
}

/// A prepared statement that records every row it binds.
///
/// Extends rather than implements, so the concrete `execute([params])` on
/// [CommonPreparedStatement] is the single place a bound row passes through and
/// the opaque `StatementParameters` overloads stay pure delegation.
class _RecordingStatement extends CommonPreparedStatement {
  final PreparedStatement _inner;
  final _Recorder _recorder;

  _RecordingStatement(this._inner, this._recorder);

  @override
  void execute([List<Object?> parameters = const <Object?>[]]) {
    _recorder.ran.add(_Statement(_inner.sql, parameters));

    if (_recorder.rows == _recorder.failOnRow) {
      throw StateError('injected mid-write failure on row ${_recorder.rows}');
    }
    _recorder.rows++;

    _inner.execute(parameters);
  }

  /// Declared [Never] rather than `RawPreparedStatement`, and that is a
  /// deliberate type trick rather than laziness: [Never] is a subtype of every
  /// type, so this is a legal override that never names the experimental type
  /// and therefore needs no `// ignore` to clear `--fatal-warnings`. Nothing in
  /// the store reaches raw access, and a double that pretended to offer it
  /// would be lying about what it wraps.
  @override
  Never get raw => throw UnsupportedError('the recording double exposes no raw statement');

  @override
  String get sql => _inner.sql;

  @override
  int get parameterCount => _inner.parameterCount;

  @override
  bool get isReadOnly => _inner.isReadOnly;

  @override
  bool get isExplain => _inner.isExplain;

  @override
  void executeWith(StatementParameters parameters) => _inner.executeWith(parameters);

  @override
  ResultSet selectWith(StatementParameters parameters) => _inner.selectWith(parameters);

  @override
  IteratingCursor iterateWith(StatementParameters parameters) => _inner.iterateWith(parameters);

  @override
  void reset() => _inner.reset();

  @override
  void dispose() => _inner.close();

  @override
  void close() => _inner.close();
}

/// [source] with the two provider identifiers [ScaleFixture] predates attached.
///
/// `ScaleFixture` was written for the render path, before `streamId` and
/// `catchupDays` existed, so its channels carry neither and a round trip over
/// them would silently never exercise the identity the favourite carry-over is
/// keyed on. Everything else (the 40% with no schedule, the third with no
/// logo) is the generator's own realistic distribution and is left alone.
List<Channel> _withProviderIds(List<Channel> source) => <Channel>[
  for (int i = 0; i < source.length; i++)
    Channel(
      number: source[i].number,
      name: source[i].name,
      group: source[i].group,
      status: source[i].status,
      logoUrl: source[i].logoUrl,
      schedule: source[i].schedule,
      facts: source[i].facts,
      favourite: source[i].favourite,
      streamId: 100000 + i,
      // 0.7% of the measured real provider's channels carry an archive
      // (`channel.dart:79`), so most of these are null and the column has to
      // survive being mostly null.
      catchupDays: i % 143 == 0 ? 7 : null,
    ),
];

/// [source] with a `providerId` per title, in the two colliding ID spaces.
///
/// The index is reused across both kinds on purpose: a movie's `stream_id` and
/// a series' `series_id` really do collide numerically, so a store keyed on the
/// number alone would merge them and the carry-over would hand one title's
/// favourite to another.
List<TitleItem> _titlesWithProviderIds(List<TitleItem> source) => <TitleItem>[
  for (int i = 0; i < source.length; i++) _titleWith(source[i], providerId: i ~/ 3),
];

/// [source] rebuilt with [providerId], since [TitleItem] has no `copyWith`.
TitleItem _titleWith(
  TitleItem source, {
  int? providerId,
  String? name,
  String? synopsis,
  double? progress,
  bool? favourite,
}) => TitleItem(
  kind: source.kind,
  name: name ?? source.name,
  category: source.category,
  year: source.year,
  posterUrl: source.posterUrl,
  backdropUrl: source.backdropUrl,
  minutes: source.minutes,
  rating: source.rating,
  genres: source.genres,
  synopsis: synopsis ?? source.synopsis,
  facts: source.facts,
  cast: source.cast,
  episodes: source.episodes,
  progress: progress ?? source.progress,
  favourite: favourite ?? source.favourite,
  providerId: providerId ?? source.providerId,
);

/// Every channel field the store promises to carry, compared one at a time.
///
/// [Channel] has no `==`, and writing one for a test would put a store concern
/// in a render model. Naming the fields here also states the contract: what is
/// absent from this list (`schedule`, `status`) is absent from the store by
/// decision rather than by omission, and has its own test below.
void _expectSameChannel(Channel actual, Channel expected) {
  expect(actual.number, expected.number, reason: 'number');
  expect(actual.name, expected.name, reason: 'name');
  expect(actual.group, expected.group, reason: 'group');
  expect(actual.logoUrl, expected.logoUrl, reason: 'logoUrl');
  expect(actual.facts, expected.facts, reason: 'facts');
  expect(actual.favourite, expected.favourite, reason: 'favourite');
  expect(actual.streamId, expected.streamId, reason: 'streamId');
  expect(actual.catchupDays, expected.catchupDays, reason: 'catchupDays');
}

/// Every title field the store promises to carry. `cast` and `episodes` are
/// absent for the same reason `schedule` is; see the store's doc block.
void _expectSameTitle(TitleItem actual, TitleItem expected) {
  expect(actual.kind, expected.kind, reason: 'kind');
  expect(actual.name, expected.name, reason: 'name');
  expect(actual.category, expected.category, reason: 'category');
  expect(actual.year, expected.year, reason: 'year');
  expect(actual.posterUrl, expected.posterUrl, reason: 'posterUrl');
  expect(actual.backdropUrl, expected.backdropUrl, reason: 'backdropUrl');
  expect(actual.minutes, expected.minutes, reason: 'minutes');
  expect(actual.rating, expected.rating, reason: 'rating');
  expect(actual.genres, expected.genres, reason: 'genres');
  expect(actual.synopsis, expected.synopsis, reason: 'synopsis');
  expect(actual.facts, expected.facts, reason: 'facts');
  expect(actual.progress, expected.progress, reason: 'progress');
  expect(actual.favourite, expected.favourite, reason: 'favourite');
  expect(actual.providerId, expected.providerId, reason: 'providerId');
}

void main() {
  const String account = 'http%3A%2F%2Fpanel.example%3A8080/demo';
  const String other = 'http%3A%2F%2Fpanel.example%3A8080/second';
  const CatalogueStore store = CatalogueStore();

  late Database inner;
  late _Recorder recorder;

  setUp(() {
    inner = sqlite3.openInMemory();
    recorder = _Recorder();
    DatabaseManager().setConnection(_RecordingDatabase(inner, recorder));
    store.migrate();
    recorder.ran.clear();
    recorder.prepared.clear();
  });

  tearDown(() {
    DatabaseManager().dispose();
    Magic.flush();
  });

  group('CatalogueStore, the schema and the round trip', () {
    test('round-trips 1000 channels as equal value objects', () async {
      final List<Channel> written = _withProviderIds(ScaleFixture.channels(1000, 40));

      await store.replaceChannels(account: account, channels: written);

      final List<Channel> read = store.channelsFor(account);

      expect(read, hasLength(1000));
      for (int i = 0; i < written.length; i++) {
        _expectSameChannel(read[i], written[i]);
      }
    });

    test('round-trips titles as equal value objects', () async {
      final List<TitleItem> written = _titlesWithProviderIds(ScaleFixture.titles(300, 12));

      await store.replaceTitles(account: account, titles: written);

      final List<TitleItem> read = store.titlesFor(account);

      expect(read, hasLength(300));
      for (int i = 0; i < written.length; i++) {
        _expectSameTitle(read[i], written[i]);
      }
    });

    test('restores a channel with an empty schedule and an idle status', () async {
      const Channel live = Channel(
        number: 1,
        name: 'Kanal D',
        group: 'ULUSAL',
        status: ChannelStatus.live,
        streamId: 42,
        schedule: <Programme>[Programme(startMinute: 1200, endMinute: 1470, title: 'Akşam Kuşağı')],
      );

      await store.replaceChannels(account: account, channels: <Channel>[live]);

      final Channel read = store.channelsFor(account).single;

      expect(read.schedule, isEmpty);
      expect(read.status, ChannelStatus.idle);
    });

    test('restores a title with no cast and no episodes', () async {
      final TitleItem series = _titlesWithProviderIds(ScaleFixture.titles(3, 2)).first;

      expect(series.episodes, isNotEmpty, reason: 'the fixture has to carry episodes for this to mean anything');

      await store.replaceTitles(account: account, titles: <TitleItem>[series]);

      final TitleItem read = store.titlesFor(account).single;

      expect(read.episodes, isEmpty);
      expect(read.cast, isEmpty);
    });

    test('scopes every row to its account key', () async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'First', group: 'A', status: ChannelStatus.idle, streamId: 1),
        ],
      );
      await store.replaceChannels(
        account: other,
        channels: const <Channel>[
          Channel(number: 9, name: 'Second', group: 'B', status: ChannelStatus.idle, streamId: 9),
        ],
      );

      expect(store.channelsFor(account).single.name, 'First');
      expect(store.channelsFor(other).single.name, 'Second');
    });
  });

  group('CatalogueStore, binding rather than interpolation', () {
    /// The two injection strings pushed through every text column the store
    /// owns, in one write per table.
    Future<void> writeHostileCatalogue() async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(
            number: 1,
            name: _quoteBreak,
            group: _rowBreak,
            status: ChannelStatus.idle,
            logoUrl: _quoteBreak,
            facts: <String>[_rowBreak],
            streamId: 1,
          ),
        ],
      );
      await store.replaceTitles(
        account: account,
        titles: const <TitleItem>[
          TitleItem(
            kind: TitleKind.movie,
            name: _rowBreak,
            category: _quoteBreak,
            year: 2026,
            synopsis: _quoteBreak,
            genres: <String>[_rowBreak],
            providerId: 1,
          ),
        ],
      );
    }

    test('stores injection-shaped provider strings literally and both tables survive', () async {
      await writeHostileCatalogue();

      final Channel channel = store.channelsFor(account).single;
      final TitleItem title = store.titlesFor(account).single;

      expect(channel.name, _quoteBreak);
      expect(channel.group, _rowBreak);
      expect(channel.logoUrl, _quoteBreak);
      expect(channel.facts, <String>[_rowBreak]);
      expect(title.name, _rowBreak);
      expect(title.category, _quoteBreak);
      expect(title.synopsis, _quoteBreak);
      expect(title.genres, <String>[_rowBreak]);
    });

    test('never lets a provider string reach a SQL string', () async {
      await writeHostileCatalogue();

      expect(recorder.ran, isNotEmpty, reason: 'the double saw nothing, so this gate proves nothing');
      for (final _Statement statement in recorder.ran) {
        expect(statement.sql, isNot(contains(_quoteBreak)));
        expect(statement.sql, isNot(contains(_rowBreak)));
        expect(statement.sql, isNot(contains('DROP')));
      }
      for (final String sql in recorder.prepared) {
        expect(sql, isNot(contains(_quoteBreak)));
        expect(sql, isNot(contains(_rowBreak)));
      }
    });

    test('binds every value: no parameterised statement runs with an empty params list', () async {
      await writeHostileCatalogue();

      final List<_Statement> parameterised = recorder.ran.where((_Statement s) => s.isParameterised).toList();

      expect(parameterised, isNotEmpty, reason: 'the store emitted no bound statement at all');
      for (final _Statement statement in parameterised) {
        expect(statement.params, isNotEmpty, reason: statement.sql);
      }

      // The other half of the same gate: a statement with no placeholder has to
      // be one of the fixed control statements, never a row carrier.
      for (final _Statement statement in recorder.ran.where((_Statement s) => !s.isParameterised)) {
        expect(
          statement.sql.trimLeft().split(' ').first.toUpperCase(),
          anyOf('BEGIN', 'COMMIT', 'ROLLBACK', 'CREATE'),
          reason: statement.sql,
        );
      }
    });

    test('writes 1000 channels through exactly one prepared INSERT', () async {
      await store.replaceChannels(account: account, channels: _withProviderIds(ScaleFixture.channels(1000, 40)));

      expect(recorder.prepared, hasLength(1));
      expect(recorder.prepared.single.toUpperCase(), startsWith('INSERT INTO'));
      expect(recorder.rows, 1000);
    });
  });

  group('CatalogueStore, a refresh', () {
    test('replaces the previous contents for that account', () async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'Gone', group: 'A', status: ChannelStatus.idle, streamId: 1),
          Channel(number: 2, name: 'Also gone', group: 'A', status: ChannelStatus.idle, streamId: 2),
        ],
      );
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'Kept', group: 'A', status: ChannelStatus.idle, streamId: 1),
        ],
      );

      final List<Channel> read = store.channelsFor(account);

      expect(read, hasLength(1));
      expect(read.single.name, 'Kept');
    });

    test('preserves a channel favourite across a full refresh', () async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'Starred', group: 'A', status: ChannelStatus.idle, streamId: 7),
        ],
      );
      store.setChannelFavourite(account: account, streamId: 7, favourite: true);

      expect(store.channelsFor(account).single.favourite, isTrue);

      // The refresh sends the channel renamed and renumbered, with the provider
      // default of `favourite: false`, which is what an unguarded replace loses.
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 12, name: 'Starred HD', group: 'B', status: ChannelStatus.idle, streamId: 7),
        ],
      );

      final Channel read = store.channelsFor(account).single;

      expect(read.favourite, isTrue);
      expect(read.name, 'Starred HD', reason: 'provider fields still refresh');
    });

    test('preserves a title favourite and progress across a full refresh', () async {
      await store.replaceTitles(
        account: account,
        titles: const <TitleItem>[
          TitleItem(kind: TitleKind.movie, name: 'Film', category: 'A', year: 2020, providerId: 3),
          // Same number, other ID space: this is the collision the key has to
          // survive, and it must not inherit the movie's user state.
          TitleItem(kind: TitleKind.series, name: 'Dizi', category: 'A', year: 2021, providerId: 3),
        ],
      );
      store.setTitleFavourite(account: account, kind: TitleKind.movie, providerId: 3, favourite: true);
      store.setTitleProgress(account: account, kind: TitleKind.movie, providerId: 3, progress: 0.42);

      await store.replaceTitles(
        account: account,
        titles: const <TitleItem>[
          TitleItem(kind: TitleKind.movie, name: 'Film 4K', category: 'B', year: 2020, providerId: 3),
          TitleItem(kind: TitleKind.series, name: 'Dizi', category: 'A', year: 2021, providerId: 3),
        ],
      );

      final List<TitleItem> read = store.titlesFor(account);
      final TitleItem movie = read.firstWhere((TitleItem t) => t.kind == TitleKind.movie);
      final TitleItem series = read.firstWhere((TitleItem t) => t.kind == TitleKind.series);

      expect(movie.favourite, isTrue);
      expect(movie.progress, 0.42);
      expect(movie.name, 'Film 4K');
      expect(series.favourite, isFalse, reason: 'the other ID space must not inherit it');
      expect(series.progress, 0);
    });

    test('rolls the whole write back when it throws mid-write', () async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'Survivor', group: 'A', status: ChannelStatus.idle, streamId: 1),
        ],
      );

      recorder.failOnRow = 500;

      await expectLater(
        store.replaceChannels(account: account, channels: _withProviderIds(ScaleFixture.channels(1000, 40))),
        throwsA(isA<StateError>()),
      );

      final List<Channel> read = store.channelsFor(account);

      expect(read, hasLength(1), reason: 'the DELETE has to roll back with the inserts');
      expect(read.single.name, 'Survivor');
    });
  });

  group('CatalogueStore, user state', () {
    test('writes a channel favourite and takes it away again', () async {
      await store.replaceChannels(
        account: account,
        channels: const <Channel>[
          Channel(number: 1, name: 'Kanal', group: 'A', status: ChannelStatus.idle, streamId: 5),
        ],
      );

      store.setChannelFavourite(account: account, streamId: 5, favourite: true);
      expect(store.channelsFor(account).single.favourite, isTrue);

      store.setChannelFavourite(account: account, streamId: 5, favourite: false);
      expect(store.channelsFor(account).single.favourite, isFalse);
    });

    test('writes a title favourite and a title progress independently', () async {
      await store.replaceTitles(
        account: account,
        titles: const <TitleItem>[
          TitleItem(kind: TitleKind.movie, name: 'Film', category: 'A', year: 2020, providerId: 8),
        ],
      );

      store.setTitleProgress(account: account, kind: TitleKind.movie, providerId: 8, progress: 0.5);
      expect(store.titlesFor(account).single.progress, 0.5);
      expect(store.titlesFor(account).single.favourite, isFalse);

      store.setTitleFavourite(account: account, kind: TitleKind.movie, providerId: 8, favourite: true);
      expect(store.titlesFor(account).single.progress, 0.5);
      expect(store.titlesFor(account).single.favourite, isTrue);
    });
  });

  group('CatalogueStore.accountKey', () {
    test('keys on the panel URL and the username, never the password', () {
      final XtreamCredentials first = XtreamCredentials(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'one',
        userAgent: 'Watchools/1.0',
      );
      final XtreamCredentials second = XtreamCredentials(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'two',
        userAgent: 'Watchools/1.0',
      );

      expect(CatalogueStore.accountKey(first), CatalogueStore.accountKey(second));
      expect(CatalogueStore.accountKey(first), isNot(contains('one')));
      expect(CatalogueStore.accountKey(first), contains('demo'));
    });

    test('separates two accounts on one panel and one account on two panels', () {
      final XtreamCredentials demo = XtreamCredentials(
        baseUrl: 'http://panel.example:8080',
        username: 'demo',
        password: 'x',
        userAgent: 'W',
      );
      final XtreamCredentials otherUser = XtreamCredentials(
        baseUrl: 'http://panel.example:8080',
        username: 'demo2',
        password: 'x',
        userAgent: 'W',
      );
      final XtreamCredentials otherPanel = XtreamCredentials(
        baseUrl: 'http://panel2.example:8080',
        username: 'demo',
        password: 'x',
        userAgent: 'W',
      );

      expect(CatalogueStore.accountKey(demo), isNot(CatalogueStore.accountKey(otherUser)));
      expect(CatalogueStore.accountKey(demo), isNot(CatalogueStore.accountKey(otherPanel)));
    });

    test('cannot be collided by a username carrying the separator', () {
      final XtreamCredentials first = XtreamCredentials(
        baseUrl: 'http://a.example',
        username: 'b/c',
        password: 'x',
        userAgent: 'W',
      );
      final XtreamCredentials second = XtreamCredentials(
        baseUrl: 'http://a.example/b',
        username: 'c',
        password: 'x',
        userAgent: 'W',
      );

      expect(CatalogueStore.accountKey(first), isNot(CatalogueStore.accountKey(second)));
    });
  });
}
