import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';
import '../../../app/models/title_item.dart';
import '../../components/count_badge/index.dart';
import '../../components/episode_row/index.dart';
import '../../components/fact_list/index.dart';
import '../../components/person_circle/index.dart';
import '../../components/rail/index.dart';
import '../../components/section_header/index.dart';
import '../../components/title_poster/index.dart';
import 'page_gutter.dart';

/// The sections all three detail directions share.
///
/// Extracted because there are exactly three callers, which is the bar: a
/// season list, an episode list, a cast rail and a technical stack are the same
/// content in all three, and the directions differ in how they COMPOSE those,
/// not in what a season chip looks like. Letting each direction own its own
/// copy would make the comparison a comparison of four accidental variations.
abstract final class TitleSections {
  /// The season selector, as a row of posters with unwatched counts.
  ///
  /// Plex's shape, and it beats a dropdown for the reason Netflix's sibling
  /// list does: a dropdown hides how many seasons there are and how far into
  /// them you got, which are the two things that decide which one you want.
  static Widget seasons(LibraryController controller, TitleItem title) {
    final List<int> numbers = title.seasons;
    if (numbers.length < 2) return const SizedBox.shrink();

    return WDiv(
      className: 'flex flex-col gap-3 w-full',
      children: <Widget>[
        WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(
            title: 'Sezonlar',
            trailing: WText('${numbers.length}', className: 'text-sm font-semibold text-fg-muted'),
          ),
        ),
        Rail(
          height: 92,
          itemCount: numbers.length,
          itemBuilder: (BuildContext context, int index) => _seasonChip(controller, title, numbers[index]),
        ),
      ],
    );
  }

  static Widget _seasonChip(LibraryController controller, TitleItem title, int season) {
    final List<Episode> episodes = title.episodesOf(season);
    final int unwatched = episodes.where((Episode e) => e.progress <= 0.03).length;
    final bool selected = controller.season == season;

    return SizedBox(
      width: 168,
      child: Stack(
        children: <Widget>[
          WAnchor(
            onTap: () => controller.selectSeason(season),
            semanticLabel: '$season. sezon, ${episodes.length} bölüm',
            child: WDiv(
              className: '''
                flex flex-col justify-center gap-1 w-full h-[84px] px-4 rounded-xl
                bg-surface-container
                hover:bg-surface-container-high
                focus:ring-2 focus:ring-focus-ring
                selected:bg-inverse selected:text-on-inverse
              ''',
              states: selected ? const <String>{'selected'} : const <String>{},
              children: <Widget>[
                WText('$season. Sezon', className: 'text-base font-bold', states: _states(selected)),
                WText(
                  '${episodes.length} bölüm',
                  className: selected ? 'text-xs' : 'text-xs text-fg-muted',
                  states: _states(selected),
                ),
              ],
            ),
          ),
          if (unwatched > 0) Positioned(top: 0, right: 0, child: CountBadge(label: '$unwatched')),
        ],
      ),
    );
  }

  static Set<String> _states(bool selected) => selected ? const <String>{'selected'} : const <String>{};

  /// The episode list for whichever season is selected.
  ///
  /// [density] is `full` where the direction has room for a still and a
  /// synopsis, and `compact` where it does not.
  static Widget episodes(LibraryController controller, TitleItem title, {String density = 'full'}) {
    if (!title.isSeries) return const SizedBox.shrink();

    final List<Episode> list = title.episodesOf(controller.season);
    final Episode? next = title.upNext;

    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.x}',
      children: <Widget>[
        SectionHeader(
          title: 'Bölümler',
          source: '${controller.season}. sezon',
          trailing: WText('${list.length}', className: 'text-sm font-semibold text-fg-muted'),
        ),
        if (list.isEmpty)
          const WDiv(
            className: 'w-full p-4 rounded-lg border border-color-border-subtle',
            child: WText('Bu sezon için bölüm bilgisi gelmedi.', className: 'text-sm text-fg-muted'),
          )
        else
          for (final Episode episode in list)
            EpisodeRow(episode: episode, density: density, selected: identical(episode, next), onTap: () {}),
      ],
    );
  }

  /// The cast rail, with the empty state the references all render.
  ///
  /// Plex draws a bordered box carrying a sentence where it has nothing, rather
  /// than dropping the section. That is worth copying exactly: a provider sends
  /// no cast far more often than it sends one, and a page that silently loses a
  /// heading teaches the user that the app is unreliable.
  static Widget cast(TitleItem title) {
    return WDiv(
      className: 'flex flex-col gap-3 w-full',
      children: <Widget>[
        const WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: 'Oyuncular ve ekip'),
        ),
        if (title.cast.isEmpty)
          const WDiv(
            className: 'mx-6 p-4 rounded-lg border border-color-border-subtle',
            child: WText('Sağlayıcı bu başlık için oyuncu bilgisi göndermedi.', className: 'text-sm text-fg-muted'),
          )
        else
          Rail(
            height: PersonCircle.height,
            gap: 8,
            itemCount: title.cast.length,
            itemBuilder: (BuildContext context, int index) {
              final CastMember member = title.cast[index];

              return PersonCircle(name: member.name, role: member.role, imageUrl: member.imageUrl);
            },
          ),
      ],
    );
  }

  /// The technical stack.
  static Widget specs(TitleItem title) {
    return WDiv(
      className: 'flex flex-col gap-3 w-full ${PageGutter.x}',
      children: <Widget>[
        const SectionHeader(title: 'Künye'),
        FactList(entries: entries(title)),
      ],
    );
  }

  /// The label-value rows, in the order Plex reads them: what the title IS,
  /// then where it came from, then what the stream actually carries.
  static List<FactEntry> entries(TitleItem title) {
    final List<String> facts = title.facts;

    return <FactEntry>[
      FactEntry(label: 'Tür', value: title.genres.isEmpty ? 'Belirtilmemiş' : title.genres.join(', ')),
      FactEntry(label: 'Yıl', value: '${title.year}'),
      FactEntry(label: 'Süre', value: title.lengthLabel),
      const FactEntry(label: 'Sağlayıcı', value: 'Ana sağlayıcı'),
      FactEntry(label: 'Video', value: facts.isEmpty ? 'Bilinmiyor' : facts.take(2).join(' · ')),
      FactEntry(label: 'Ses', value: facts.length > 3 ? facts[3] : 'Bilinmiyor'),
      FactEntry(label: 'Altyazılar', value: 'Hiçbiri', onTap: () {}),
    ];
  }

  /// The related-titles rail, which every reference ends its detail page with.
  static Widget related(LibraryController controller, TitleItem title) {
    final List<TitleItem> others = controller.titles
        .where((TitleItem t) => t.category == title.category && !identical(t, title))
        .take(10)
        .toList();

    return WDiv(
      className: 'flex flex-col gap-3 w-full',
      children: <Widget>[
        WDiv(
          className: '${PageGutter.x} w-full',
          child: SectionHeader(title: 'Benzer başlıklar', source: '${title.category} kategorisinden'),
        ),
        if (others.isEmpty)
          const WDiv(
            className: 'mx-6 p-4 rounded-lg border border-color-border-subtle',
            child: WText('Bu kategoride başka başlık yok.', className: 'text-sm text-fg-muted'),
          )
        else
          Rail(
            height: TitlePoster.heightFor(124),
            itemCount: others.length,
            itemBuilder: (BuildContext context, int index) {
              final TitleItem other = others[index];

              return SizedBox(
                width: 124,
                child: TitlePoster(
                  title: other,
                  size: 'sm',
                  onTap: () => controller.select(other),
                  onToggleFavourite: () => controller.toggleFavourite(other),
                ),
              );
            },
          ),
      ],
    );
  }

  /// What the play button says.
  ///
  /// It names the episode when there is one, because a series page whose button
  /// says only `Oynat` makes the viewer open the episode list to find out what
  /// it would have played. Plex spells the target out under its poster for the
  /// same reason.
  static String playLabel(TitleItem title) {
    final Episode? next = title.upNext;
    final bool resuming = title.isSeries ? (next?.progress ?? 0) > 0.03 : title.progress > 0.03;

    if (title.isSeries && next != null) return '${resuming ? 'Devam et' : 'Başla'} · ${next.code}';

    return resuming ? 'Devam et' : 'Oynat';
  }

  /// The one filled button.
  static Widget playVerb(TitleItem title, {bool wide = false}) {
    final String label = playLabel(title);

    return WAnchor(
      onTap: () {},
      semanticLabel: '${title.name} $label',
      child: WDiv(
        className: wide
            ? '''
              flex flex-row items-center justify-center gap-2 w-full
              h-12 rounded-full
              bg-primary text-on-primary
              hover:bg-primary-hover
              focus:ring-2 focus:ring-focus-ring
            '''
            : '''
              flex flex-row items-center gap-2
              h-11 px-6 rounded-full
              bg-primary text-on-primary
              hover:bg-primary-hover
              focus:ring-2 focus:ring-focus-ring
            ''',
        children: <Widget>[
          const WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
          WText(label, className: 'text-sm font-bold'),
        ],
      ),
    );
  }

  /// The row of ghost icon buttons that follows the one filled verb.
  ///
  /// Every reference demotes everything except playback to an icon, and that is
  /// the discipline worth keeping: a second filled button makes the first one
  /// stop meaning "this is what you came for".
  static Widget ghostActions(LibraryController controller, TitleItem title) {
    return WDiv(
      className: 'flex flex-row items-center gap-1',
      children: <Widget>[
        _ghost(Icons.bookmark_border_rounded, 'İzleme listesine ekle'),
        _ghost(Icons.check_circle_outline, 'İzlendi olarak işaretle'),
        _ghost(Icons.file_download_outlined, 'İndir'),
        _ghost(Icons.ios_share, 'Paylaş'),
        _ghost(Icons.more_horiz, 'Diğer'),
      ],
    );
  }

  static Widget _ghost(IconData icon, String label) {
    return WAnchor(
      onTap: () {},
      semanticLabel: label,
      child: WDiv(
        className: '''
          size-10 rounded-full items-center justify-center
          text-fg-muted
          hover:bg-surface-container-high hover:text-fg
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(icon, className: 'text-base'),
      ),
    );
  }
}
