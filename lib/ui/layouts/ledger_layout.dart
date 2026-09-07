import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/library_controller.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/favourite_button/index.dart';
import 'support/library_categories.dart';
import 'support/library_empty.dart';
import 'support/library_toolbar.dart';
import 'support/nav_rail.dart';
import 'support/title_detail.dart';

/// Catalogue direction two: the ledger.
///
/// A dense row per title, with a small poster thumbnail rather than a card, and
/// the facts a viewer actually chooses on laid out in columns: year, length,
/// rating, kind, resolution.
///
/// This is the direction nobody demos and several people want. The measured
/// finding is that a text menu wins for the broadest and most diverse level of
/// a hierarchy while artwork wins once the options become nuanced, and a
/// provider's VOD catalogue is the broad case: thousands of entries, no
/// curation, no ordering, and mixed-quality artwork. It is also the only one of
/// the three that can be scanned by a fact rather than by a picture, which is
/// what "the 4K one" and "the one from 2024" actually need.
///
/// What it sacrifices: any sense of occasion. Nothing here is enjoyable to
/// look at, and on a 10-foot screen a row this dense is unreadable.
@immutable
class LedgerLayout extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [LedgerLayout].
  const LedgerLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = wScreenIs(context, 'md');
    final bool split = wScreenIs(context, 'xl');

    if (!split && controller.detailOpen) {
      return TitleDetail(controller: controller, wide: wide, dismissible: true);
    }

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 flex flex-col min-w-0',
          children: <Widget>[
            LibraryToolbar(controller: controller, wide: wide),
            LibraryCategories(controller: controller),
            if (wide) _head(),
            WDiv(className: 'flex-1 min-w-0', child: _rows(wide, split)),
          ],
        ),
        if (split)
          WDiv(
            className: 'w-[480px] shrink-0 border-l border-color-border-subtle',
            child: TitleDetail(controller: controller, wide: false),
          ),
      ],
    );
  }

  /// The column header, which is what makes this a table rather than a list.
  ///
  /// It is not sortable yet and it does not pretend to be: a header that looks
  /// clickable and is not is worse than a plain label. Sorting is the obvious
  /// next thing this direction earns if it wins.
  Widget _head() {
    return const WDiv(
      className: '''
        flex flex-row items-center gap-3
        h-9 px-4 md:px-8
        text-[10px] font-bold text-fg-disabled tracking-wide
      ''',
      children: <Widget>[
        WDiv(className: 'w-[40px] shrink-0'),
        WDiv(
          className: 'flex-1 min-w-0',
          child: WText('BAŞLIK', className: 'text-[10px] font-bold tracking-wide'),
        ),
        WDiv(
          className: 'hidden lg:block w-[120px] shrink-0',
          child: WText('TÜR', className: 'text-[10px] font-bold'),
        ),
        WDiv(
          className: 'w-[54px] shrink-0',
          child: WText('YIL', className: 'text-[10px] font-bold'),
        ),
        WDiv(
          className: 'w-[76px] shrink-0',
          child: WText('SÜRE', className: 'text-[10px] font-bold'),
        ),
        WDiv(
          className: 'w-[54px] shrink-0',
          child: WText('PUAN', className: 'text-[10px] font-bold'),
        ),
        WDiv(
          className: 'hidden xl:block w-[92px] shrink-0',
          child: WText('KALİTE', className: 'text-[10px] font-bold'),
        ),
        WDiv(className: 'w-11 shrink-0'),
      ],
    );
  }

  Widget _rows(bool wide, bool split) {
    if (controller.matches.isEmpty) return LibraryEmpty(controller: controller);

    return ListView.separated(
      primary: true,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: controller.matches.length,
      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 2),
      itemBuilder: (BuildContext context, int index) => _row(controller.matches[index], wide, split),
    );
  }

  Widget _row(TitleItem title, bool wide, bool split) {
    final bool selected = identical(title, controller.selected);
    final Set<String> states = selected ? const <String>{'selected'} : const <String>{};

    // The star is a sibling of the row's anchor rather than a descendant, the
    // same as in the line-up row: nested, the row's semantics node absorbs it
    // and a screen reader can never reach the star.
    return WDiv(
      className: '''
        flex flex-row items-center
        mx-2 md:mx-6 rounded-lg
        hover:bg-surface-container
        selected:bg-surface-container-high
      ''',
      states: states,
      children: <Widget>[
        WDiv(
          className: 'flex-1 min-w-0',
          child: WAnchor(
            onTap: () => split ? controller.select(title) : controller.openDetail(title),
            semanticLabel: _label(title),
            child: WDiv(
              className: 'flex flex-row items-center gap-3 h-14 px-2 md:px-2 focus:ring-2 focus:ring-focus-ring',
              children: <Widget>[
                _thumb(title),
                WDiv(className: 'flex-1 min-w-0', child: _identity(title, wide)),
                if (wide) ...<Widget>[
                  WDiv(
                    className: 'hidden lg:block w-[120px] shrink-0',
                    child: WText(title.category, className: 'text-xs text-fg-muted truncate'),
                  ),
                  WText(
                    '${title.year}',
                    className: 'w-[54px] shrink-0 text-xs text-fg-muted',
                    textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                  ),
                  WText(
                    title.lengthLabel,
                    className: 'w-[76px] shrink-0 text-xs text-fg-muted',
                    textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                  ),
                  _rating(title),
                  WDiv(
                    className: 'hidden xl:block w-[92px] shrink-0',
                    child: WText(title.facts.isEmpty ? '—' : title.facts.first, className: 'text-xs text-fg-disabled'),
                  ),
                ],
              ],
            ),
          ),
        ),
        FavouriteButton(
          starred: title.favourite,
          subject: title.name,
          onToggle: () => controller.toggleFavourite(title),
        ),
      ],
    );
  }

  /// Everything the columns say, in one sentence.
  ///
  /// A `WAnchor`'s `semanticLabel` replaces the text of everything beneath it,
  /// so a row labelled with just a name and a year hid its own kind badge, its
  /// runtime, its rating and its resume note. This layout's whole argument is
  /// that it can be scanned by a fact rather than by a picture, and a screen
  /// reader was getting none of the facts.
  String _label(TitleItem title) {
    final List<String> parts = <String>[
      title.name,
      title.isSeries ? 'dizi' : 'film',
      '${title.year}',
      title.lengthLabel,
      if (title.ratingLabel != null) 'puan ${title.ratingLabel}',
      if (title.inProgress) _resumeNote(title),
    ];

    return parts.join(', ');
  }

  /// A 2:3 thumbnail at 28 by 42.
  ///
  /// Small enough that it is an identifier rather than artwork, which is the
  /// point: a row that cannot be scanned faster than a grid has no reason to
  /// exist. Titles with no poster get their initial rather than a hole.
  Widget _thumb(TitleItem title) {
    final String? poster = title.posterUrl;

    return WDiv(
      className: '''
        w-[28px] h-[42px] shrink-0
        rounded overflow-hidden
        bg-surface-container-high
        flex items-center justify-center
      ''',
      child: Artwork(
        src: poster,
        slotWidth: 28,
        fallback: WText(title.name.substring(0, 1).toUpperCase(), className: 'text-xs font-bold text-fg-disabled'),
      ),
    );
  }

  Widget _identity(TitleItem title, bool wide) {
    return WDiv(
      className: 'flex flex-col min-w-0',
      children: <Widget>[
        WDiv(
          className: 'flex flex-row items-center gap-2 w-full min-w-0',
          children: <Widget>[
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(title.name, className: 'text-sm font-semibold text-fg truncate'),
            ),
            if (title.isSeries)
              const WDiv(
                className: 'shrink-0 px-1.5 h-4 rounded bg-surface-container-high flex items-center',
                child: WText('DİZİ', className: 'text-[9px] font-bold text-fg-muted'),
              ),
          ],
        ),
        // Below `md` the columns are gone, so the facts they carried move under
        // the name. Dropping them would leave the row saying only which titles
        // exist, which is the one thing a poster grid already does better.
        if (!wide)
          WText(
            '${title.year} · ${title.lengthLabel}${title.ratingLabel == null ? '' : ' · ★ ${title.ratingLabel}'}',
            className: 'text-xs text-fg-disabled truncate',
          )
        else if (title.inProgress)
          WText(_resumeNote(title), className: 'text-xs font-semibold text-primary truncate'),
      ],
    );
  }

  /// What is left to watch, in words rather than as a bar.
  ///
  /// A one pixel trough in a 56 pixel row beside five numeric columns is noise;
  /// the sentence is the thing the viewer acts on.
  String _resumeNote(TitleItem title) {
    if (!title.isSeries) {
      final int left = ((title.minutes ?? 0) * (1 - title.progress)).round();

      return '$left dk kaldı';
    }

    final Episode? next = title.upNext;

    return next == null ? 'Devam ediyor' : '${next.code} sırada';
  }

  Widget _rating(TitleItem title) {
    final String? label = title.ratingLabel;

    if (label == null) {
      return const WDiv(
        className: 'w-[54px] shrink-0',
        child: WText('—', className: 'text-xs text-fg-disabled'),
      );
    }

    return WDiv(
      className: 'w-[54px] shrink-0 flex flex-row items-center gap-1',
      children: <Widget>[
        const WIcon(Icons.star_rounded, className: 'text-xs text-primary'),
        WText(
          label,
          className: 'text-xs font-semibold text-fg',
          textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
