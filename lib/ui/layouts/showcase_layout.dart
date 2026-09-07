import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/favourite_button/index.dart';
import '../components/title_poster/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/title_detail.dart';

/// Catalogue direction three: the showcase.
///
/// Netflix. One title fills the top of the screen, then horizontal shelves of
/// posters underneath, `İzlemeye devam et` first and the provider's categories
/// after it.
///
/// This is the one direction where the archetype fits the content: a VOD
/// catalogue does have artwork, titles do have synopses and ratings, and a
/// shelf of 2:3 posters is what those were made for. The argument against it
/// for a channel line-up does not carry over, which is why it is here for the
/// catalogue and was rejected for the guide.
///
/// What it optimises: being sold something. A viewer with no destination gets
/// one title argued for properly rather than four hundred listed.
///
/// What it sacrifices: reaching a known title. Everything is two shelves and a
/// horizontal scroll away, and the count of what you cannot see is invisible.
/// The measured Netflix comparison is the cost: roughly seven posters per row
/// down to three or four, and a year of beta that could not prove engagement
/// improved.
@immutable
class ShowcaseLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [ShowcaseLayout].
  const ShowcaseLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = wScreenIs(context, 'md');

    // Always a screen here, at every width. The hero sells one title and the
    // shelves sell the rest; neither can hold an episode list, so without this
    // the shelf layout was the one direction with no way to see a season at
    // all, which the end-to-end walk caught rather than a screenshot.
    if (controller.detailOpen) {
      return TitleDetail(controller: controller, wide: wide, dismissible: true);
    }

    final List<(String, List<TitleItem>)> shelves = _shelves();

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 min-w-0',
          child: CustomScrollView(
            primary: true,
            slivers: <Widget>[
              SliverToBoxAdapter(child: _hero(context, wide)),
              SliverToBoxAdapter(child: LibraryToolbar(controller: controller, wide: wide)),
              SliverToBoxAdapter(child: LibraryCategories(controller: controller)),
              if (shelves.isEmpty)
                // The default `hasScrollBody: true` matters: false measures the
                // child's intrinsic height, and Wind's `h-full` column path
                // carries a `LayoutBuilder`, which cannot answer that.
                SliverFillRemaining(child: LibraryEmpty(controller: controller))
              else
                for (final (String, List<TitleItem>) shelf in shelves)
                  SliverToBoxAdapter(child: _shelf(shelf.$1, shelf.$2)),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ],
    );
  }

  /// The shelves, in the order a returning viewer wants them.
  ///
  /// `İzlemeye devam et` leads when there is anything in it, because that is
  /// what a returning viewer opened the app for and Apple's Up Next row is the
  /// same decision. `Favorileriniz` next, then the provider's categories.
  List<(String, List<TitleItem>)> _shelves() {
    // Not while a synthetic category is the filter: a "continue watching" shelf
    // inside the continue-watching view is the same list twice.
    final bool synthetic = controller.category == 'İzlemeye devam et' || controller.category == 'Favoriler';

    final List<TitleItem> resume = synthetic ? const <TitleItem>[] : controller.continueWatching;
    final List<TitleItem> starred = synthetic
        ? const <TitleItem>[]
        : controller.matches.where((TitleItem t) => t.favourite).toList();

    return <(String, List<TitleItem>)>[
      if (resume.isNotEmpty) ('İzlemeye devam et', resume),
      if (starred.isNotEmpty) ('Favorileriniz', starred),
      ...controller.sections,
    ];
  }

  Widget _hero(BuildContext context, bool wide) {
    final TitleItem title = controller.selected;
    final String? backdrop = title.backdropUrl;
    final double height = (MediaQuery.sizeOf(context).height * 0.58).clamp(260.0, 560.0);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(src: backdrop, fallback: const WDiv(className: 'bg-surface-container')),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xE60E0F11), Color(0xB30E0F11), Color(0x000E0F11)],
                stops: <double>[0.0, 0.5, 0.85],
              ),
            ),
            child: SizedBox.expand(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x000E0F11), Color(0x000E0F11), Color(0xFF0E0F11)],
                stops: <double>[0.0, 0.55, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          WDiv(
            className: 'flex flex-col justify-end gap-3 h-full px-6 md:px-12 pb-8 max-w-[720px]',
            children: <Widget>[
              WDiv(
                className: 'flex flex-row items-center gap-2',
                children: <Widget>[
                  WText(
                    title.isSeries ? 'DİZİ' : 'FİLM',
                    className: 'text-[11px] font-bold text-fg-muted tracking-wide',
                  ),
                  WText(_meta(title), className: 'text-xs text-fg-muted'),
                ],
              ),
              WAnchor(
                onTap: () => controller.openDetail(title),
                semanticLabel: '${title.name} ayrıntıları',
                child: WText(title.name, className: 'text-3xl md:text-5xl font-bold text-fg line-clamp-2'),
              ),
              if (title.synopsis != null && wide)
                WDiv(
                  className: 'max-w-[640px]',
                  child: WText(title.synopsis!, className: 'text-sm md:text-base text-fg-muted line-clamp-3'),
                ),
              _actions(title),
            ],
          ),
        ],
      ),
    );
  }

  String _meta(TitleItem title) {
    final String? rating = title.ratingLabel;
    final String head = '${title.year} · ${title.lengthLabel}';

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
      className: 'flex flex-row items-center gap-3',
      children: <Widget>[
        WAnchor(
          onTap: () {},
          semanticLabel: '${title.name} $label',
          child: WDiv(
            className: '''
              flex flex-row items-center gap-2
              h-12 px-7 rounded
              bg-inverse
              text-on-inverse
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              const WIcon(Icons.play_arrow_rounded, className: 'text-xl'),
              WText(label, className: 'text-base font-bold'),
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

  Widget _shelf(String heading, List<TitleItem> titles) {
    return WDiv(
      className: 'flex flex-col gap-3 pt-6',
      children: <Widget>[
        MergeSemantics(
          child: WDiv(
            className: 'flex flex-row items-baseline gap-2 px-6 md:px-12',
            children: <Widget>[
              WText(heading, className: 'text-base font-bold text-fg'),
              WText('${titles.length}', className: 'text-xs font-semibold text-fg-disabled'),
            ],
          ),
        ),
        SizedBox(
          // 168 of poster at 2:3 is 252, plus two label lines. A shelf that
          // clips its own captions is the failure mode of every one of these.
          height: 320,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: titles.length,
            itemBuilder: (BuildContext context, int index) {
              final TitleItem title = titles[index];

              return WDiv(
                className: 'mx-1.5',
                child: TitlePoster(
                  title: title,
                  selected: identical(title, controller.selected),
                  // A poster tap opens the detail. It was a two-step before
                  // (tap to repoint the hero, then tap the hero's title), which
                  // is not what any catalogue does and which nothing on screen
                  // announced: the walk found the episode list unreachable.
                  // The hero still follows along, one step behind, because it
                  // shows whatever was last opened.
                  onTap: () => controller.openDetail(title),
                  onToggleFavourite: () => controller.toggleFavourite(title),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
