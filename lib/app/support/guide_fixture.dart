/// Sample line-up for the design phase.
///
/// Replaced wholesale by the Xtream client's output. It exists so the guide can
/// be judged against something that looks like a real evening: overlapping
/// programme lengths, a channel with no EPG at all, a match that runs across
/// three slots, and logos that will not load.
///
/// The backdrops come from a placeholder photo service with fixed seeds, so the
/// screen renders the same every time. A provider's real artwork is worse than
/// this: lower resolution, wrong aspect, and frequently missing.
library;

import '../models/channel.dart';
import '../models/programme.dart';

/// The group tabs, in the order the guide shows them.
///
/// `Tümü` leads and is not optional. The controller's default group is `Tümü`,
/// and without a tab for it the user could narrow to a category and never get
/// back: a one-way filter, which is how the design phase shipped it until the
/// end-to-end walk could not restore the unfiltered state either.
///
/// `Favoriler` sits second rather than first. It is the tab a returning user
/// wants, but leading with it means an empty screen on first run.
const List<String> guideGroups = <String>['Tümü', 'Favoriler', 'Ulusal', 'Spor', 'Haber', 'Belgesel', 'Çocuk'];

String _shot(String seed) => 'https://picsum.photos/seed/$seed/1200/675';

/// The fixture line-up.
final List<Channel> guideFixture = <Channel>[
  Channel(
    number: 1,
    name: 'TRT 1',
    group: 'Ulusal',
    status: ChannelStatus.live,
    facts: const <String>['1080p', 'H.265', '5.1'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60, endMinute: 20 * 60, title: 'Gün Ortası'),
      Programme(
        startMinute: 20 * 60,
        endMinute: 20 * 60 + 55,
        title: 'Ana Haber Bülteni',
        subtitle: 'Akşam kuşağı',
        episode: 'Canlı yayın',
        description:
            'Günün gelişmeleri, ekonomi ve spor başlıkları. Stüdyodan canlı '
            'bağlantılarla saha muhabirlerinin aktardığı son dakika haberleri.',
        imageUrl: _shot('newsroom'),
      ),
      const Programme(
        startMinute: 20 * 60 + 55,
        endMinute: 22 * 60 + 30,
        title: 'Perşembe Filmi: Uzak Şehir',
        subtitle: 'Dram, 2021',
      ),
    ],
  ),
  Channel(
    number: 2,
    name: 'Show TV',
    group: 'Ulusal',
    status: ChannelStatus.live,
    facts: const <String>['1080p', 'H.264'],
    schedule: <Programme>[
      const Programme(
        startMinute: 19 * 60 + 15,
        endMinute: 20 * 60 + 30,
        title: 'Yarışma Gecesi',
        subtitle: 'Bölüm 34',
      ),
      Programme(
        startMinute: 20 * 60 + 30,
        endMinute: 23 * 60,
        title: 'Dizi: Kuzeyin Işıkları',
        subtitle: 'Sezon 3 · Bölüm 12',
        episode: 'S3 · B12',
        description:
            'Ailenin geçmişiyle yüzleştiği bölümde, kasabaya dönen yabancı '
            'herkesin sakladığı sırrı ortaya çıkarmaya kararlıdır.',
        imageUrl: _shot('nordic'),
      ),
    ],
  ),
  Channel(
    number: 7,
    name: 'Kanal D',
    group: 'Ulusal',
    status: ChannelStatus.catchup,
    facts: const <String>['1080p', 'AAC'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60 + 30, endMinute: 20 * 60 + 15, title: 'Gün Sonu'),
      Programme(
        startMinute: 20 * 60 + 15,
        endMinute: 22 * 60,
        title: 'Akşam Dizisi',
        subtitle: 'Sezon 2 · Bölüm 8',
        episode: 'S2 · B8',
        description:
            'Şehirden kaçan üç arkadaşın, sahil kasabasında kurdukları yeni '
            'hayatı bir mektup altüst eder.',
        imageUrl: _shot('coastline'),
      ),
    ],
  ),
  Channel(
    number: 26,
    name: 'Spor Ekstra',
    group: 'Spor',
    status: ChannelStatus.recording,
    facts: const <String>['4K', 'HDR', 'H.265'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60, endMinute: 19 * 60 + 45, title: 'Maç Öncesi'),
      Programme(
        startMinute: 19 * 60 + 45,
        endMinute: 21 * 60 + 50,
        title: 'Derbi: Fenerbahçe - Galatasaray',
        subtitle: 'Süper Lig · 14. Hafta',
        episode: 'Canlı',
        description:
            'Sezonun en çok beklenen karşılaşması. İki takım da ligin ilk '
            'sırası için sahaya çıkıyor; maç öncesi son durum ve muhtemel '
            'on birler stüdyodan aktarılıyor.',
        imageUrl: _shot('stadium'),
      ),
      const Programme(startMinute: 21 * 60 + 50, endMinute: 23 * 60, title: 'Maç Sonu Değerlendirme'),
    ],
  ),
  Channel(
    number: 27,
    name: 'Spor Ekstra 2',
    group: 'Spor',
    status: ChannelStatus.live,
    facts: const <String>['1080p'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60 + 30, endMinute: 20 * 60 + 30, title: 'Basketbol Öncesi'),
      Programme(
        startMinute: 20 * 60 + 30,
        endMinute: 22 * 60 + 15,
        title: 'Anadolu Efes - Fenerbahçe Beko',
        subtitle: 'THY EuroLeague',
        imageUrl: _shot('basketball'),
      ),
    ],
  ),
  Channel(
    number: 12,
    name: 'NTV',
    group: 'Haber',
    status: ChannelStatus.live,
    facts: const <String>['720p'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60 + 30, endMinute: 20 * 60, title: 'Piyasalar'),
      Programme(
        startMinute: 20 * 60,
        endMinute: 21 * 60,
        title: 'Gündem Özel',
        subtitle: 'Canlı yayın',
        description:
            'Haftanın gündemini belirleyen başlıklar, konuklar ve saha '
            'bağlantılarıyla değerlendiriliyor.',
        imageUrl: _shot('studio'),
      ),
      const Programme(startMinute: 21 * 60, endMinute: 22 * 60, title: 'Dünya Raporu'),
    ],
  ),
  const Channel(number: 14, name: 'Haber Global', group: 'Haber', status: ChannelStatus.idle),
  Channel(
    number: 108,
    name: 'Doğa TV',
    group: 'Belgesel',
    status: ChannelStatus.live,
    facts: const <String>['4K', 'HDR'],
    schedule: <Programme>[
      Programme(
        startMinute: 19 * 60 + 40,
        endMinute: 20 * 60 + 40,
        title: 'Vahşi Anadolu',
        subtitle: 'Bozkırın Sessiz Avcıları',
        episode: 'S1 · B4',
        description:
            'İç Anadolu bozkırında bir yıl. Kışın sonunda yeniden uyanan '
            'ekosistem, gece çekimleriyle ilk kez bu ayrıntıda görüntülendi.',
        imageUrl: _shot('steppe'),
      ),
      const Programme(startMinute: 20 * 60 + 40, endMinute: 21 * 60 + 40, title: 'Derinlerde'),
    ],
  ),
  Channel(
    number: 210,
    name: 'Çocuk Kanalı',
    group: 'Çocuk',
    status: ChannelStatus.live,
    facts: const <String>['720p'],
    schedule: <Programme>[
      const Programme(startMinute: 19 * 60 + 30, endMinute: 20 * 60 + 20, title: 'Çizgi Kuşağı'),
      Programme(
        startMinute: 20 * 60 + 20,
        endMinute: 21 * 60,
        title: 'Uyku Vakti Masalları',
        imageUrl: _shot('storybook'),
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // From here down the provider sent no EPG. This is not an edge case: on a
  // real line-up it is routinely half the channels, and it is the reason the
  // guide and the list are separate views. A time axis has nothing to draw for
  // these, so the toolbars state how many, and the grid view draws them
  // with a full-window block saying so.
  // ---------------------------------------------------------------------------
  const Channel(
    number: 305,
    name: 'Müzik Türk',
    group: 'Müzik',
    status: ChannelStatus.live,
    facts: <String>['1080p', 'AAC'],
  ),
  const Channel(number: 306, name: 'Slow Türk', group: 'Müzik', status: ChannelStatus.live, facts: <String>['720p']),
  const Channel(number: 307, name: 'Number One', group: 'Müzik', status: ChannelStatus.live, facts: <String>['1080p']),
  const Channel(
    number: 41,
    name: 'Sinema Aksiyon',
    group: 'Sinema',
    status: ChannelStatus.catchup,
    facts: <String>['1080p', 'DTS'],
  ),
  const Channel(
    number: 42,
    name: 'Sinema Komedi',
    group: 'Sinema',
    status: ChannelStatus.live,
    facts: <String>['1080p'],
  ),
  const Channel(number: 43, name: 'Sinema Yerli', group: 'Sinema', status: ChannelStatus.idle),
  const Channel(number: 512, name: 'Yaşam TV', group: 'Yaşam', status: ChannelStatus.live, facts: <String>['720p']),
  const Channel(
    number: 610,
    name: 'Kanal 35 İzmir',
    group: 'Yerel',
    status: ChannelStatus.live,
    facts: <String>['576p'],
  ),
  const Channel(
    number: 611,
    name: 'Bursa Olay TV',
    group: 'Yerel',
    status: ChannelStatus.live,
    facts: <String>['576p'],
  ),
  const Channel(number: 612, name: 'Antalya Kanal V', group: 'Yerel', status: ChannelStatus.idle),
  const Channel(number: 720, name: 'Diyanet TV', group: 'Din', status: ChannelStatus.live, facts: <String>['720p']),
  const Channel(
    number: 810,
    name: 'Alışveriş 24',
    group: 'Alışveriş',
    status: ChannelStatus.live,
    facts: <String>['576p'],
  ),
  const Channel(
    number: 901,
    name: 'BBC World News',
    group: 'Yabancı',
    status: ChannelStatus.live,
    facts: <String>['1080p', 'H.265'],
  ),
  const Channel(
    number: 902,
    name: 'Al Jazeera English',
    group: 'Yabancı',
    status: ChannelStatus.live,
    facts: <String>['720p'],
  ),
];
