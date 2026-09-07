import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';
import '../../../app/models/title_item.dart';
import '../../components/artwork/index.dart';
import '../../components/episode_row/index.dart';
import '../../components/fact_chip/index.dart';
import '../../components/favourite_button/index.dart';

/// The detail surface for one catalogue entry: backdrop, metadata, actions, and
/// for a series its episode list.
///
/// One component for both kinds rather than a movie page and a series page.
/// Everything above the fold is identical, and the difference is that a series
/// continues below it: splitting them would mean two implementations of the
/// same header drifting apart, and a viewer does not think of them as two
/// screens either.
///
/// The play button names what it will play. For a movie that is `İzle` or
/// `Devam et`; for a series it is the episode code, because the whole point of
/// a series page is that the viewer should not have to remember where they got
/// to. Apple's Up Next row is the same idea one level up.
@immutable
class TitleDetail extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Whether the surface has room for the wide treatment.
  final bool wide;

  /// Whether to draw a back affordance over the header.
  ///
  /// True when the detail is a screen of its own rather than a pane beside the
  /// body. Back is the one control a TV audience is trained hardest on, and a
  /// screen you can enter and not leave is the failure the walk caught.
  final bool dismissible;

  /// Creates the [TitleDetail].
  const TitleDetail({
    super.key,
    required this.controller,
    required this.wide,
    this.dismissible = false,
  });

  @override
  Widget build(BuildContext context) {
    final TitleItem title = controller.selected;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: dismissible
              ? Stack(
                  children: <Widget>[
                    _header(context, title),
                    Positioned(left: 12, top: 12, child: _back()),
                  ],
                )
              : _header(context, title),
        ),
        if (title.isSeries) ...<Widget>[
          SliverToBoxAdapter(child: _seasonStrip(title)),
          SliverList.builder(
            itemCount: title.episodesOf(controller.season).length,
            itemBuilder: (BuildContext context, int index) {
              final Episode episode = title.episodesOf(controller.season)[index];

              return WDiv(
                className: 'px-4 md:px-8',
                child: EpisodeRow(
                  episode: episode,
                  density: wide ? 'full' : 'compact',
                  selected: identical(episode, title.upNext),
                  onTap: () {},
                ),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _back() {
    return WAnchor(
      onTap: controller.closeDetail,
      semanticLabel: 'Kütüphaneye dön',
      child: const WDiv(
        className: '''
          size-10 rounded-full
          flex items-center justify-center
          bg-scrim-strong
          text-fg
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WIcon(Icons.arrow_back_rounded, className: 'text-lg'),
      ),
    );
  }

  Widget _header(BuildContext context, TitleItem title) {
    final String? backdrop = title.backdropUrl;
    final double height = wide ? 320 : 200;

    return WDiv(
      className: 'flex flex-col',
      children: <Widget>[
        SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // No backdrop is the common case for a provider feed. A flat
              // tonal panel rather than a stretched poster: upscaling a 2:3
              // poster to 16:9 is the artefact that makes a catalogue look
              // broken rather than sparse.
              Artwork(src: backdrop, fallback: const WDiv(className: 'bg-surface-container')),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x00000000), Color(0x99000000), Color(0xF20E0F11)],
                    stops: <double>[0.0, 0.55, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ],
          ),
        ),
        WDiv(
          className: 'flex flex-col gap-3 px-4 md:px-8 -mt-16',
          children: <Widget>[
            WText(title.name, className: 'text-2xl md:text-3xl font-bold text-fg line-clamp-2'),
            WDiv(
              className: 'flex flex-row items-center gap-2 wrap',
              children: <Widget>[
                WText(_meta(title), className: 'text-xs text-fg-muted'),
                for (final String genre in title.genres) FactChip(label: genre),
              ],
            ),
            if (title.synopsis != null) WText(title.synopsis!, className: 'text-sm text-fg-muted line-clamp-4 max-w-[680px]'),
            _actions(title),
            if (title.facts.isNotEmpty)
              WDiv(
                className: 'flex flex-row gap-1 wrap',
                children: <Widget>[for (final String fact in title.facts) FactChip(label: fact)],
              ),
          ],
        ),
      ],
    );
  }

  String _meta(TitleItem title) {
    final String? rating = title.ratingLabel;
    final String kind = title.isSeries ? 'Dizi' : 'Film';
    final String head = '$kind · ${title.year} · ${title.lengthLabel}';

    return rating == null ? head : '$head · ★ $rating';
  }

  Widget _actions(TitleItem title) {
    final Episode? next = title.upNext;
    final String label = switch ((title.isSeries, next, title.inProgress)) {
      (true, final Episode e, _) => '${e.code} oynat',
      (false, _, true) => 'Devam et',
      _ => 'İzle',
    };

    return WDiv(
      className: 'flex flex-row items-center gap-2 wrap',
      children: <Widget>[
        WAnchor(
          onTap: () {},
          semanticLabel: '${title.name} $label',
          child: WDiv(
            className: '''
              flex flex-row items-center gap-2
              h-11 px-6 rounded-full
              bg-primary
              text-on-primary
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              const WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
              WText(label, className: 'text-sm font-bold'),
            ],
          ),
        ),
        FavouriteButton(
          starred: title.favourite,
          subject: title.name,
          shape: 'pill',
          onToggle: () => controller.toggleFavourite(title),
        ),
      ],
    );
  }

  /// The season tabs.
  ///
  /// A strip rather than a dropdown, and it opens on the season the next
  /// episode is in rather than season one. A viewer six seasons deep who lands
  /// on season one every time is a viewer counting taps.
  Widget _seasonStrip(TitleItem title) {
    final List<int> seasons = title.seasons;

    if (seasons.length <= 1) {
      return WDiv(
        className: 'px-4 md:px-8 pt-6 pb-2',
        child: WText(
          '${title.episodes.length} bölüm',
          className: 'text-[11px] font-bold text-fg-muted tracking-wide',
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          for (final int season in seasons)
            WAnchor(
              onTap: () => controller.selectSeason(season),
              semanticLabel: '$season. sezon',
              child: WDiv(
                className: '''
                  flex flex-row items-center
                  mr-2 my-2 px-4 h-9 rounded-full
                  bg-surface-container
                  text-sm font-semibold text-fg-muted
                  hover:bg-surface-container-high hover:text-fg
                  focus:ring-2 focus:ring-focus-ring
                  selected:bg-inverse selected:text-on-inverse
                ''',
                states: controller.season == season ? const <String>{'selected'} : const <String>{},
                child: WText('$season. Sezon', className: 'text-sm font-semibold'),
              ),
            ),
        ],
      ),
    );
  }
}
