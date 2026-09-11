import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/app/provider/catalogue_store.dart';
import 'package:watchools/app/support/scale_fixture.dart';

/// The measured real provider's live channel count.
const int _channelCount = 2976;

/// The measured real provider's VOD count. 12.9 titles per channel, which is
/// the ratio `FixtureScale` cannot reach: its `titles => channels ~/ 2` and its
/// 50,000 channel clamp put this size out of range from the app side, so this
/// file calls the generator directly.
const int _titleCount = 38247;

/// Group and category counts on `FixtureScale`'s own ratios: one per twenty
/// five, capped at 400 so the strip stays a strip.
const int _groupCount = 119;
const int _categoryCount = 400;

/// A `stream_id` per channel, since [ScaleFixture] predates the field and the
/// favourite carry-over walks it on every write.
List<Channel> _withStreamIds(List<Channel> source) => <Channel>[
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
    ),
];

/// A `provider_id` per title, in the ID space [TitleItem.kind] names.
List<TitleItem> _withProviderIds(List<TitleItem> source) => <TitleItem>[
  for (int i = 0; i < source.length; i++)
    TitleItem(
      kind: source[i].kind,
      name: source[i].name,
      category: source[i].category,
      year: source[i].year,
      posterUrl: source[i].posterUrl,
      backdropUrl: source[i].backdropUrl,
      minutes: source[i].minutes,
      rating: source[i].rating,
      genres: source[i].genres,
      synopsis: source[i].synopsis,
      facts: source[i].facts,
      episodes: source[i].episodes,
      progress: source[i].progress,
      favourite: source[i].favourite,
      providerId: i ~/ 3,
    ),
];

/// What a full refresh costs at the real provider's size.
///
/// The write is synchronous, so the elapsed figure below IS a frozen UI for
/// exactly that long. Above roughly two seconds combined, a blocking SQLite
/// write is not survivable behind a progress state on a television and the
/// design has to move to a background isolate with its own connection, which
/// magic's web arm cannot provide. That is why this file prints the number and
/// asserts nothing about it: a threshold here is a threshold somebody softens.
///
/// The counts round-trip assertions are the only gates, and they are here so
/// the measurement cannot be of a write that silently dropped rows.
///
/// Read the figure as a floor rather than a device number. This runs against
/// `openInMemory` on a development machine, so it carries no file system and no
/// disk sync at all, and it is a debug build. What it does measure honestly is
/// the statement count: the transaction and the single prepared statement are
/// what keep the shape linear, and a regression to `insertAll` would show here
/// as an order of magnitude rather than as noise.
///
/// `stdout.writeln` rather than `print`, which `analysis_options.yaml` bans.
void main() {
  test('writes the real catalogue size', () async {
    final Database db = sqlite3.openInMemory();
    DatabaseManager().setConnection(db);
    addTearDown(() {
      DatabaseManager().dispose();
      Magic.flush();
    });

    const CatalogueStore store = CatalogueStore();
    store.migrate();

    const String account = 'http%3A%2F%2Fpanel.example%3A8080/demo';

    final List<Channel> channels = _withStreamIds(ScaleFixture.channels(_channelCount, _groupCount));
    final List<TitleItem> titles = _withProviderIds(ScaleFixture.titles(_titleCount, _categoryCount));

    final Stopwatch channelWrite = Stopwatch()..start();
    await store.replaceChannels(account: account, channels: channels);
    channelWrite.stop();

    final Stopwatch titleWrite = Stopwatch()..start();
    await store.replaceTitles(account: account, titles: titles);
    titleWrite.stop();

    final int total = channelWrite.elapsedMilliseconds + titleWrite.elapsedMilliseconds;

    stdout.writeln('SCALE channels: $_channelCount rows in ${channelWrite.elapsedMilliseconds} ms');
    stdout.writeln('SCALE titles:   $_titleCount rows in ${titleWrite.elapsedMilliseconds} ms');
    stdout.writeln('SCALE combined: $total ms (redesign threshold, not asserted: ~2000 ms)');

    expect(store.channelsFor(account), hasLength(_channelCount));
    expect(store.titlesFor(account), hasLength(_titleCount));
  });
}
