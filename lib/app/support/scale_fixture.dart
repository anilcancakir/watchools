import '../models/channel.dart';
import '../models/programme.dart';
import '../models/title_item.dart';

/// A generated line-up and catalogue at provider scale, for measurement.
///
/// The hand-written fixtures are 23 channels and 15 titles, which is the right
/// size for judging a design and the wrong size for judging a frame. A real
/// Xtream playlist is hundreds of `group-title` values and five figures of
/// channels, and every performance question this app has (does a rail build
/// lazily, does a strip build every chip, does a search walk the list on every
/// keystroke) is invisible below about a thousand rows.
///
/// Deterministic on purpose. Every value is derived from the item's own index
/// through [_mix], so two runs a week apart produce byte-identical data and a
/// measurement can be compared against the one before it. Nothing here calls
/// `Random`, `DateTime.now` or the network.
///
/// The distributions are the point rather than the volume. A generator that
/// gives every channel a full schedule and every title a poster measures a
/// line-up nobody has: it is the MISSING data that decides the layout, so the
/// shares below are set from what the doctrine records about real playlists.
abstract final class ScaleFixture {
  /// Share of channels the provider sends no EPG for.
  ///
  /// Two in five. `.ac/research/design-doctrine.md` treats a missing schedule as
  /// the common case rather than the exception, and the whole `Akış bilgisi
  /// olmayan kanallar` rail plus the grid's full-window block exist for it.
  static const double _noSchedule = 0.4;

  /// Share of titles the provider sends no poster for.
  static const double _noPoster = 0.3;

  /// Share of channels and titles the user has starred.
  static const double _starred = 0.02;

  /// A one pixel transparent GIF, as the artwork URL for every item that has
  /// one.
  ///
  /// A `data:` URI rather than a real photo service, and this is a measurement
  /// correctness fix rather than a shortcut. The first version of this
  /// generator emitted `https://picsum.photos/seed/...` for five thousand
  /// channels, so every perf session raced hundreds of live HTTP fetches and a
  /// decode per fetch against the frames it was timing. That is the most likely
  /// single cause of the run to run variance that swamped the effect size and
  /// made one change look like a regression it was not.
  ///
  /// The cost of losing real images is that this fixture cannot measure decode
  /// or `ImageCache` pressure. That is a separate question and it needs its own
  /// harness; mixing the two measures neither.
  static const String _pixel = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

  /// A cheap integer hash, so every derived value is a pure function of the
  /// index and the field it feeds.
  ///
  /// Knuth's multiplicative constant against a per-field salt. It is not a good
  /// hash and does not need to be: it needs to be stable across runs and to
  /// decorrelate the fields, so that a channel's group does not predict whether
  /// it has a schedule.
  static int _mix(int index, int salt) => (index * 2654435761 + salt * 40503) & 0x7fffffff;

  /// Whether item [index] falls in the leading [share] of the distribution for
  /// [salt].
  static bool _inShare(int index, int salt, double share) => _mix(index, salt) % 1000 < share * 1000;

  /// Provider group names, in the shape a real playlist sends them.
  ///
  /// Uppercased with a country prefix, because that is what `group-title`
  /// actually carries and it is what makes a category strip wide. A generator
  /// that emits `Spor` measures a strip nobody has.
  static const List<String> _groupStems = <String>[
    'ULUSAL',
    'SPOR',
    'HABER',
    'BELGESEL',
    'ÇOCUK',
    'MÜZİK',
    'SİNEMA',
    'DİZİ',
    'YEREL',
    'DİNİ',
    'YAŞAM',
    'EĞİTİM',
    'YEMEK',
    'MODA',
    'OTOMOBİL',
    'DOĞA',
    'TARİH',
    'BİLİM',
    'KADIN',
    'GENÇLİK',
  ];

  static const List<String> _nameStems = <String>[
    'Anadolu',
    'Marmara',
    'Ege',
    'Toros',
    'Karadeniz',
    'Fırat',
    'Meriç',
    'Sakarya',
    'Kızılırmak',
    'Yeşilırmak',
    'Boğaziçi',
    'Kapadokya',
    'Nemrut',
    'Ararat',
    'Uludağ',
    'Erciyes',
  ];

  static const List<String> _factSets = <String>['1080p', '720p', '4K', 'H.264', 'H.265', 'AAC', '5.1', 'STEREO'];

  /// [count] group names, `Tümü` and `Favoriler` first.
  ///
  /// The two synthetic tabs lead for the same reason they do in the hand-written
  /// fixture: `Tümü` is the way out of a filter and `Favoriler` is the tab a
  /// returning viewer wants.
  static List<String> groups(int count) => <String>[
    'Tümü',
    'Favoriler',
    for (int i = 0; i < count; i++) 'TR | ${_groupStems[i % _groupStems.length]} ${i ~/ _groupStems.length + 1}',
  ];

  /// [count] catalogue categories, the two synthetic ones first.
  static List<String> categories(int count) => <String>[
    'Tümü',
    'İzlemeye devam et',
    'Favoriler',
    for (int i = 0; i < count; i++)
      '${_groupStems[i % _groupStems.length].toLowerCase()} ${i ~/ _groupStems.length + 1}',
  ];

  /// [count] channels spread over [groupCount] groups.
  static List<Channel> channels(int count, int groupCount) {
    final List<String> names = groups(groupCount).sublist(2);

    return <Channel>[
      for (int i = 0; i < count; i++)
        Channel(
          number: i + 1,
          name: '${_nameStems[_mix(i, 1) % _nameStems.length]} ${_mix(i, 2) % 90 + 10}',
          group: names[_mix(i, 3) % names.length],
          status: ChannelStatus.values[_mix(i, 4) % ChannelStatus.values.length],
          // A third carry no logo, which is what makes `ChannelMark`'s initials
          // fallback the common path rather than the exception.
          logoUrl: _inShare(i, 5, 0.33) ? null : _pixel,
          schedule: _inShare(i, 6, _noSchedule) ? const <Programme>[] : _schedule(i),
          facts: <String>[_factSets[_mix(i, 7) % 3], _factSets[3 + _mix(i, 8) % 2], _factSets[5 + _mix(i, 9) % 3]],
          favourite: _inShare(i, 10, _starred),
        ),
    ];
  }

  /// One channel's evening, covering the guide window with no holes.
  ///
  /// Programmes are 30, 60 or 90 minutes and start on the half hour, which is
  /// what a Turkish schedule does and what makes the grid's blocks line up into
  /// columns rather than into a ragged edge.
  static List<Programme> _schedule(int channel) {
    final List<Programme> out = <Programme>[];
    int minute = 18 * 60;
    int slot = 0;

    while (minute < 24 * 60 + 60) {
      final int length = <int>[30, 60, 90][_mix(channel * 31 + slot, 11) % 3];
      final int end = minute + length;

      out.add(
        Programme(
          startMinute: minute,
          endMinute: end,
          title: '${_nameStems[_mix(channel + slot, 12) % _nameStems.length]} Kuşağı ${_mix(slot, 13) % 40 + 1}',
          subtitle: _inShare(channel + slot, 14, 0.5) ? null : 'Bölüm ${_mix(slot, 15) % 200 + 1}',
          description: _inShare(channel + slot, 16, 0.4)
              ? null
              : 'Akşam kuşağında yayınlanan yapımın bu bölümünde konuklar gündemi değerlendiriyor.',
          imageUrl: _inShare(channel + slot, 17, 0.35) ? null : _pixel,
        ),
      );

      minute = end;
      slot++;
    }

    return out;
  }

  /// [count] titles spread over [categoryCount] categories.
  ///
  /// Every third one is a series, and a series carries three seasons of eight
  /// episodes. That is 1.8 episode objects per title on average, so a catalogue
  /// of 3000 titles holds roughly 5400 episodes: the number that matters,
  /// because catalogue search reaches episode titles.
  static List<TitleItem> titles(int count, int categoryCount) {
    final List<String> names = categories(categoryCount).sublist(3);

    return <TitleItem>[
      for (int i = 0; i < count; i++)
        TitleItem(
          kind: i % 3 == 0 ? TitleKind.series : TitleKind.movie,
          name: '${_nameStems[_mix(i, 21) % _nameStems.length]} ${_mix(i, 22) % 400 + 1}',
          category: names[_mix(i, 23) % names.length],
          year: 1985 + _mix(i, 24) % 41,
          posterUrl: _inShare(i, 25, _noPoster) ? null : _pixel,
          backdropUrl: _inShare(i, 26, 0.35) ? null : _pixel,
          minutes: i % 3 == 0 ? null : 80 + _mix(i, 27) % 80,
          rating: _inShare(i, 28, 0.25) ? null : (30 + _mix(i, 29) % 70) / 10,
          genres: <String>[
            _groupStems[_mix(i, 30) % _groupStems.length].toLowerCase(),
            _groupStems[_mix(i, 31) % _groupStems.length].toLowerCase(),
          ],
          synopsis: _inShare(i, 32, 0.3)
              ? null
              : 'Bir kasabanın sessiz gecesinde başlayan olaylar, yıllar önce kapanmış bir dosyayı yeniden açar.',
          facts: <String>[_factSets[_mix(i, 33) % 3], _factSets[3 + _mix(i, 34) % 2]],
          episodes: i % 3 == 0 ? _episodes(i) : const <Episode>[],
          progress: i % 3 == 0 ? 0 : (_inShare(i, 35, 0.15) ? (_mix(i, 36) % 80 + 10) / 100 : 0),
          favourite: _inShare(i, 37, _starred),
        ),
    ];
  }

  /// Three seasons of eight, with the resume point in season two.
  static List<Episode> _episodes(int title) => <Episode>[
    for (int season = 1; season <= 3; season++)
      for (int number = 1; number <= 8; number++)
        Episode(
          season: season,
          number: number,
          title: '${_nameStems[_mix(title + season * 8 + number, 41) % _nameStems.length]} Yolu',
          minutes: 40 + _mix(title + number, 42) % 20,
          synopsis: _inShare(title + number, 43, 0.3) ? null : 'Bölümde ekip yeni bir ipucunun peşine düşer.',
          imageUrl: _inShare(title + number, 44, 0.3) ? null : _pixel,
          // Season one watched, season two part way in, so `upNext` has one
          // right answer and the resume rail is populated at scale.
          progress: season == 1
              ? 1
              : season == 2 && number == 1
              ? 1
              : season == 2 && number == 2
              ? 0.37
              : 0,
        ),
  ];
}
