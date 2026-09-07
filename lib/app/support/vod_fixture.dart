/// Sample VOD catalogue for the design phase.
///
/// Replaced wholesale by the Xtream client's output. It exists so the movie and
/// series screens can be judged against something shaped like a real library:
/// a mix of posters and missing posters, ratings and missing ratings, part
/// watched titles, a series with three seasons and one with a single season,
/// and provider categories that overlap the way real ones do.
///
/// The artwork comes from a placeholder photo service with fixed seeds, so the
/// screen renders the same every time. A provider's real artwork is worse than
/// this: lower resolution, wrong aspect, and frequently absent, which is why
/// several entries here deliberately have none.
library;

import '../models/title_item.dart';

/// The catalogue category tabs, in the order the screens show them.
///
/// `Tümü` leads for the same reason it does in the line-up: the default scope
/// needs a tab, or narrowing is one-way. `İzlemeye devam et` is ours rather
/// than the provider's, and it comes second because it is what a returning
/// viewer opens the app for.
const List<String> vodCategories = <String>[
  'Tümü',
  'İzlemeye devam et',
  'Favoriler',
  'Aksiyon',
  'Dram',
  'Komedi',
  'Bilim Kurgu',
  'Belgesel',
  'Yerli',
  'Animasyon',
];

String _poster(String seed) => 'https://picsum.photos/seed/$seed/400/600';
String _backdrop(String seed) => 'https://picsum.photos/seed/$seed/1280/720';

/// Two square portraits, shared across the cast lists.
///
/// Constants rather than a helper, because a `const CastMember` needs a const
/// URL. Two rather than one per person on purpose: the point of the fixture is
/// the ratio of portraits to blanks, not the variety of faces.
const String _portraitOne = 'https://picsum.photos/seed/portre-1/200/200';
const String _portraitTwo = 'https://picsum.photos/seed/portre-2/200/200';

/// The fixture catalogue: movies first, then series.
final List<TitleItem> vodFixture = <TitleItem>[
  // A part-watched flagship with everything filled in. The best case, and the
  // one every layout will look good on.
  TitleItem(
    kind: TitleKind.movie,
    name: 'Sessiz Şehir',
    category: 'Aksiyon',
    year: 2024,
    posterUrl: _poster('sessiz-sehir'),
    backdropUrl: _backdrop('sessiz-sehir-bd'),
    minutes: 132,
    rating: 7.8,
    genres: const <String>['Aksiyon', 'Gerilim'],
    synopsis:
        'Bir gece yarısı elektrikleri kesilen kentte, kayıp bir çocuğun izini '
        'süren dedektifin yirmi dört saati. Kalabalığın arasında kaybolmak, '
        'aradığın kişiden çok kendini kaybetmek anlamına geliyor.',
    facts: const <String>['4K', 'HDR', 'H.265', '5.1'],
    // Two of the five carry no portrait, which is the ratio a real feed sends
    // and the reason the cast rail's fallback is a designed state rather than a
    // gap. `Aylin Gürses` also has no photo AND the longest name, which is what
    // the two-line clamp under a circle is there for.
    cast: const <CastMember>[
      CastMember(name: 'Deniz Aksoy', role: 'Komiser Ferhat', imageUrl: _portraitOne),
      CastMember(name: 'Selin Yalçın', role: 'Nihal'),
      CastMember(name: 'Mert Öztürk', role: 'Sabri', imageUrl: _portraitTwo),
      CastMember(name: 'Aylin Gürses Karahan', role: 'Yönetmen'),
      CastMember(name: 'Kaan Demirsoy', role: 'Senarist'),
    ],
    progress: 0.41,
    favourite: true,
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Kuzey Rüzgârı',
    category: 'Dram',
    year: 2023,
    posterUrl: _poster('kuzey-ruzgari'),
    backdropUrl: _backdrop('kuzey-ruzgari-bd'),
    minutes: 108,
    rating: 8.2,
    genres: const <String>['Dram'],
    synopsis:
        'Karadeniz kıyısındaki bir kasabaya otuz yıl sonra dönen bir kadının, '
        'geride bıraktığı evi satmaya çalışırken hatırlamak zorunda kaldıkları.',
    facts: const <String>['1080p', 'H.264', '5.1'],
    progress: 0.88,
  ),
  // No poster, no rating, no synopsis. A large share of a real catalogue looks
  // exactly like this, and it is the case a poster wall cannot render.
  const TitleItem(
    kind: TitleKind.movie,
    name: 'Gece Yarısı Ekspresi',
    category: 'Gerilim',
    year: 1998,
    minutes: 121,
    facts: <String>['576p'],
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Sonsuz Yaz',
    category: 'Komedi',
    year: 2025,
    posterUrl: _poster('sonsuz-yaz'),
    minutes: 96,
    rating: 6.4,
    genres: const <String>['Komedi', 'Romantik'],
    synopsis: 'Aynı yazı yeniden yaşamaya mahkûm bir grup arkadaşın tatil planı her seferinde başka bir yerde çöküyor.',
    facts: const <String>['1080p', 'AAC'],
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Yörünge',
    category: 'Bilim Kurgu',
    year: 2022,
    posterUrl: _poster('yorunge'),
    backdropUrl: _backdrop('yorunge-bd'),
    minutes: 147,
    rating: 7.1,
    genres: const <String>['Bilim Kurgu', 'Dram'],
    synopsis:
        'Dünya yörüngesindeki bir istasyonda tek başına kalan mühendis, aşağıdan '
        'gelen sinyallerin susmasının ardından ne yapacağına karar vermek zorunda.',
    facts: const <String>['4K', 'HDR', '7.1'],
    progress: 0.12,
  ),
  const TitleItem(
    kind: TitleKind.movie,
    name: 'Taş Bahçe',
    category: 'Yerli',
    year: 2019,
    minutes: 104,
    rating: 5.9,
    genres: <String>['Dram'],
    facts: <String>['720p'],
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Mavi Saat',
    category: 'Belgesel',
    year: 2024,
    posterUrl: _poster('mavi-saat'),
    backdropUrl: _backdrop('mavi-saat-bd'),
    minutes: 88,
    rating: 8.7,
    genres: const <String>['Belgesel', 'Doğa'],
    synopsis: 'Gün batımıyla karanlık arasındaki kırk dakikada Anadolu bozkırının kaydedilmemiş sesleri.',
    facts: const <String>['4K', 'HDR', 'H.265'],
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Küçük Kâşif',
    category: 'Animasyon',
    year: 2021,
    posterUrl: _poster('kucuk-kasif'),
    minutes: 79,
    rating: 7.4,
    genres: const <String>['Animasyon', 'Aile'],
    synopsis: 'Bir gemi maketiyle okyanusu geçmeye karar veren çocuğun, mutfak lavabosunda başlayan yolculuğu.',
    facts: const <String>['1080p', 'AAC'],
  ),
  const TitleItem(
    kind: TitleKind.movie,
    name: 'Ateş Hattı',
    category: 'Aksiyon',
    year: 2016,
    minutes: 113,
    genres: <String>['Aksiyon'],
    facts: <String>['720p', 'AAC'],
  ),
  TitleItem(
    kind: TitleKind.movie,
    name: 'Cam Ev',
    category: 'Dram',
    year: 2020,
    posterUrl: _poster('cam-ev'),
    minutes: 119,
    rating: 6.9,
    genres: const <String>['Dram', 'Gerilim'],
    synopsis: 'Mimarın kendisi için tasarladığı şeffaf evde saklanacak hiçbir şey kalmadığında olanlar.',
    facts: const <String>['1080p', 'H.265', '5.1'],
    progress: 0.62,
  ),

  // Series. Three seasons with a real resume point, so the "up next" logic has
  // something to be right about.
  TitleItem(
    kind: TitleKind.series,
    name: 'Bozkır Hattı',
    category: 'Dram',
    year: 2022,
    posterUrl: _poster('bozkir-hatti'),
    backdropUrl: _backdrop('bozkir-hatti-bd'),
    rating: 8.4,
    genres: const <String>['Dram', 'Tarih'],
    synopsis:
        'Bir demiryolu hattının otuz yılda geçtiği kasabaların ve o hattı döşeyen '
        'ailelerin üç kuşaklık hikâyesi.',
    facts: const <String>['4K', 'HDR', 'H.265', '5.1'],
    favourite: true,
    cast: const <CastMember>[
      CastMember(name: 'Hakan Beyaz', role: 'Rasim', imageUrl: _portraitOne),
      CastMember(name: 'Elif Tanrıkulu', role: 'Zehra'),
      CastMember(name: 'Orhan Kılıç', role: 'Mühendis Cemil', imageUrl: _portraitTwo),
      CastMember(name: 'Nurgül Seven', role: 'Yönetmen'),
    ],
    episodes: <Episode>[
      Episode(
        season: 1,
        number: 1,
        title: 'İlk Ray',
        minutes: 52,
        synopsis: 'Hat, kasabaya varmadan önce kimin toprağından geçeceğine karar verilmesi gerekiyor.',
        imageUrl: _backdrop('bozkir-s1b1'),
        progress: 1,
      ),
      Episode(
        season: 1,
        number: 2,
        title: 'Kuyu',
        minutes: 49,
        synopsis: 'Kazma sırasında bulunan şey, hattın güzergâhını ve iki ailenin ilişkisini birlikte değiştiriyor.',
        imageUrl: _backdrop('bozkir-s1b2'),
        progress: 1,
      ),
      Episode(
        season: 1,
        number: 3,
        title: 'Gece Vardiyası',
        minutes: 47,
        imageUrl: _backdrop('bozkir-s1b3'),
        progress: 1,
      ),
      Episode(
        season: 2,
        number: 1,
        title: 'Yeni Hat',
        minutes: 54,
        synopsis: 'On yıl sonra, aynı hattın ikinci kolu için bu kez oğullar masaya oturuyor.',
        imageUrl: _backdrop('bozkir-s2b1'),
        progress: 1,
      ),
      // The resume point. Everything before it is finished, everything after is
      // untouched, which is the only arrangement where `upNext` has one right
      // answer.
      Episode(
        season: 2,
        number: 2,
        title: 'Sınır Taşı',
        minutes: 51,
        synopsis: 'Bir taşın yeri değiştiğinde iki kasaba arasındaki yirmi yıllık anlaşma da değişiyor.',
        imageUrl: _backdrop('bozkir-s2b2'),
        progress: 0.37,
      ),
      Episode(season: 2, number: 3, title: 'Kar', minutes: 50, imageUrl: _backdrop('bozkir-s2b3')),
      Episode(season: 2, number: 4, title: 'Dönüş', minutes: 53, imageUrl: _backdrop('bozkir-s2b4')),
      // No still and no title in the provider's feed. It renders as its code,
      // which is what a real catalogue does for a whole late season.
      const Episode(season: 3, number: 1, title: 'Bölüm 1', minutes: 48),
      const Episode(season: 3, number: 2, title: 'Bölüm 2', minutes: 48),
    ],
  ),
  TitleItem(
    kind: TitleKind.series,
    name: 'Ada Muhafızları',
    category: 'Bilim Kurgu',
    year: 2024,
    posterUrl: _poster('ada-muhafizlari'),
    backdropUrl: _backdrop('ada-muhafizlari-bd'),
    rating: 7.6,
    genres: const <String>['Bilim Kurgu', 'Gerilim'],
    synopsis: 'Haritadan silinmiş bir adada nöbet tutan ekibin, adanın neden silindiğini öğrendiği sezon.',
    facts: const <String>['1080p', 'H.265', '5.1'],
    episodes: <Episode>[
      Episode(
        season: 1,
        number: 1,
        title: 'Nöbet',
        minutes: 44,
        synopsis: 'Yeni gelen teknisyen, vardiya defterinde olmayan bir kayıt buluyor.',
        imageUrl: _backdrop('ada-s1b1'),
      ),
      Episode(season: 1, number: 2, title: 'Sis', minutes: 43, imageUrl: _backdrop('ada-s1b2')),
      Episode(season: 1, number: 3, title: 'Fener', minutes: 45, imageUrl: _backdrop('ada-s1b3')),
      Episode(season: 1, number: 4, title: 'Liman', minutes: 42, imageUrl: _backdrop('ada-s1b4')),
    ],
  ),
  // A series with no poster at all: the case every poster-led surface in the
  // app has to answer for, and the reason the title screen leads with a
  // backdrop and typography rather than with an afiş.
  const TitleItem(
    kind: TitleKind.series,
    name: 'Mahalle Defteri',
    category: 'Komedi',
    year: 2018,
    genres: <String>['Komedi'],
    facts: <String>['576p'],
    episodes: <Episode>[
      Episode(season: 1, number: 1, title: 'Bölüm 1', minutes: 24),
      Episode(season: 1, number: 2, title: 'Bölüm 2', minutes: 24),
      Episode(season: 1, number: 3, title: 'Bölüm 3', minutes: 25),
    ],
  ),
  TitleItem(
    kind: TitleKind.series,
    name: 'Derin Sular',
    category: 'Belgesel',
    year: 2023,
    posterUrl: _poster('derin-sular'),
    backdropUrl: _backdrop('derin-sular-bd'),
    rating: 8.9,
    genres: const <String>['Belgesel', 'Doğa'],
    synopsis: 'Akdeniz’in üç yüz metre altında, ışığın bittiği yerde başlayan hayat.',
    facts: const <String>['4K', 'HDR', 'H.265'],
    episodes: <Episode>[
      Episode(
        season: 1,
        number: 1,
        title: 'Işığın Sonu',
        minutes: 58,
        imageUrl: _backdrop('derin-s1b1'),
        progress: 0.71,
      ),
      Episode(season: 1, number: 2, title: 'Soğuk Akıntı', minutes: 56, imageUrl: _backdrop('derin-s1b2')),
      Episode(season: 2, number: 1, title: 'Kanyon', minutes: 57, imageUrl: _backdrop('derin-s2b1')),
    ],
  ),
  TitleItem(
    kind: TitleKind.series,
    name: 'Son Tren',
    category: 'Aksiyon',
    year: 2021,
    posterUrl: _poster('son-tren'),
    rating: 6.8,
    genres: const <String>['Aksiyon', 'Gerilim'],
    synopsis: 'Bir gece treninde başlayan takip, sabaha kadar altı istasyonda sürüyor.',
    facts: const <String>['1080p', 'AAC'],
    episodes: <Episode>[
      Episode(season: 1, number: 1, title: 'Peron', minutes: 41, imageUrl: _backdrop('tren-s1b1'), progress: 1),
      Episode(season: 1, number: 2, title: 'Vagon 4', minutes: 40, imageUrl: _backdrop('tren-s1b2')),
      Episode(season: 1, number: 3, title: 'Makas', minutes: 43, imageUrl: _backdrop('tren-s1b3')),
    ],
  ),
];
