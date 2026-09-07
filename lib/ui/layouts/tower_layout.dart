import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../../app/models/title_item.dart';
import '../components/artwork/index.dart';
import '../components/channel_mark/index.dart';
import '../components/channel_row/index.dart';
import '../components/fact_list/index.dart';
import '../components/favourite_button/index.dart';
import '../components/play_progress/index.dart';
import '../components/scrim/index.dart';
import '../components/section_header/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';
import 'support/page_gutter.dart';
import 'support/search_field.dart';

/// Direction two: the list is the product.
///
/// Plex's web library, and the reason it earns a place beside a cinematic
/// direction: a real provider ships six to twenty thousand channels, scrolling
/// them is not browsing, and the only navigation that scales is a labelled
/// sidebar, a permanent search field and a dense virtualised list. This is the
/// direction that survives the catalogue the product will actually receive.
///
/// One panel moves and the rest stays put. Plex's detail column is the only
/// part of its window that changes as you walk the list, which is what makes
/// arrow-key browsing feel like reading rather than like navigating.
///
/// Below `sm` the panel cannot fit, so it becomes a bar pinned to the bottom
/// carrying the same three things a phone needs from it: what is on, how much
/// is left, and the button.
@immutable
class TowerLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [TowerLayout].
  const TowerLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 640;
    final bool hasPanel = width >= 1100;

    return WDiv(
      className: 'flex flex-row w-full h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(expanded: true),
        WDiv(
          className: 'flex-1 min-w-0 h-full',
          child: WDiv(
            className: 'flex flex-col w-full h-full',
            children: <Widget>[
              _toolbar(wide: wide),
              PageGutter.gap,
              CategoryStrip(controller: controller),
              WDiv(
                className: 'flex-1 w-full',
                child: controller.matches.isEmpty ? GuideEmpty(controller: controller) : _list(),
              ),
              if (!hasPanel) _dock(),
            ],
          ),
        ),
        if (hasPanel) _panel(),
      ],
    );
  }

  Widget _toolbar({required bool wide}) {
    final String? note = controller.noGuideNote;

    return WDiv(
      className: 'flex flex-row items-center gap-4 w-full ${PageGutter.x} ${PageGutter.top}',
      children: <Widget>[
        WDiv(
          // Fixed above `sm`, growing below it. A `flex-1` with a `max-w-*`
          // beside it does not clamp, because `flex-1` is an `Expanded` whose
          // tight minimum beats the maximum, and the field rendered at 620
          // pixels. `w-full shrink-0` is the other wrong answer: it claims the
          // whole row and then refuses to give the count any of it back.
          className: wide ? 'w-[470px] shrink-0' : 'flex-1 min-w-0',
          child: SearchField(value: controller.query, onChanged: controller.search),
        ),
        if (wide) const WDiv(className: 'flex-1'),
        // The count and the missing-guide note are one truncating line rather
        // than two `shrink-0` cells. Both want their content width, and at 414
        // pixels there is not enough for both of them beside a search field.
        WDiv(
          className: 'shrink-0',
          child: WText(
            note == null ? controller.countLabel : '${controller.countLabel} · $note',
            className: 'text-xs text-fg-muted line-clamp-1',
          ),
        ),
      ],
    );
  }

  /// A `ListView.builder`, because this is the direction whose whole claim is
  /// that it survives a real line-up. Wind's `overflow-y-auto` composes a
  /// `SingleChildScrollView` and would build every row.
  ///
  /// The `LayoutBuilder` is what tells the row how much width it really has.
  /// This is the one direction where a sidebar and a panel take 580 pixels off
  /// a 1440 pixel window, and Wind's breakpoints read the viewport rather than
  /// the parent, so without it every row builds its widest arrangement into a
  /// column that cannot hold it.
  Widget _list() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The horizontal padding the list itself adds, plus the star's cell.
        final double available = constraints.maxWidth - 24 - 44;

        return ListView.separated(
          padding: PageGutter.scrollable,
          itemCount: controller.matches.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (BuildContext context, int index) {
            final Channel channel = controller.matches[index];

            return ChannelRow(
              channel: channel,
              nowMinute: GuideController.now,
              available: available,
              selected: identical(channel, controller.channel),
              onTap: () => controller.selectChannel(channel),
              onToggleFavourite: () => controller.toggleFavourite(channel),
            );
          },
        );
      },
    );
  }

  /// The sticky detail column.
  Widget _panel() {
    final Channel channel = controller.channel;
    final Programme? live = controller.programme;

    return WDiv(
      className: '''
        shrink-0 w-[380px] h-full
        bg-surface-container
        border-l border-color-border-subtle
      ''',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(PageGutter.value, PageGutter.value, PageGutter.value, 32),
        child: WDiv(
          className: 'flex flex-col gap-4 w-full',
          children: <Widget>[
            _panelArt(channel, live),
            WDiv(
              className: 'flex flex-row items-center gap-2 w-full',
              children: <Widget>[
                if (channel.status != ChannelStatus.idle)
                  WDiv(
                    className: 'shrink-0',
                    child: StatusBadge(status: channel.status),
                  ),
                WDiv(
                  className: 'flex-1 min-w-0',
                  child: WText(
                    '${channel.name} · ${channel.numberLabel}',
                    className: 'text-xs font-semibold text-fg-muted line-clamp-1',
                  ),
                ),
              ],
            ),
            WText(live?.title ?? 'Akış bilgisi yok', className: 'text-xl font-bold text-fg line-clamp-2'),
            if (live != null)
              WText(
                '${live.startLabel} - ${live.endLabel} · ${live.durationMinutes} dk',
                className: 'text-xs font-medium text-primary',
              ),
            _actions(channel, live),
            if (live?.description != null) WText(live!.description!, className: 'text-sm text-fg-muted line-clamp-4'),
            _upcoming(channel),
            // The technical stack. Plex's `Video / Ses / Altyazılar` table is
            // the single most transplantable thing in the references, because
            // this product's audience is the one that opens a panel
            // specifically to find out whether a stream is really what the
            // provider called it.
            const SectionHeader(title: 'Künye'),
            FactList(entries: _facts(channel)),
          ],
        ),
      ),
    );
  }

  Widget _panelArt(Channel channel, Programme? live) {
    return WDiv(
      className: 'w-full rounded-lg overflow-hidden bg-surface-container-high',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Artwork(
              src: live?.imageUrl,
              slotWidth: 340,
              fallback: WDiv(
                className: 'w-full h-full items-center justify-center',
                child: ChannelMark(channel: channel, size: 'xl'),
              ),
            ),
            if (live != null) ...<Widget>[
              Scrim.flat,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PlayProgress(value: live.progressAt(GuideController.now), tone: 'live'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(Channel channel, Programme? live) {
    return WDiv(
      className: 'flex flex-row items-center gap-2 w-full',
      children: <Widget>[
        // Content-width rather than filling the panel. Plex's `Devam` is sized
        // to its own label, and a button stretched across a 340 pixel column
        // stops reading as a button and starts reading as a banner.
        WDiv(
          className: 'shrink-0',
          child: WAnchor(
            onTap: () {},
            semanticLabel: live == null ? '${channel.name} izle' : '${live.title} izle',
            child: const WDiv(
              className: '''
                flex flex-row items-center justify-center gap-2
                h-10 px-6 rounded-full
                bg-primary text-on-primary
                hover:bg-primary-hover
                focus:ring-2 focus:ring-focus-ring
              ''',
              children: <Widget>[
                WIcon(Icons.play_arrow_rounded, className: 'text-base'),
                WText('İzle', className: 'text-sm font-bold'),
              ],
            ),
          ),
        ),
        WDiv(
          className: 'shrink-0',
          child: FavouriteButton(
            starred: channel.favourite,
            subject: channel.name,
            shape: 'circle',
            onToggle: () => controller.toggleFavourite(channel),
          ),
        ),
      ],
    );
  }

  /// What follows, as a short list with the times in tabular figures.
  ///
  /// Empty is a designed state rather than a dropped section: a channel whose
  /// guide stops after the current programme is common, and a panel that simply
  /// ends there reads as a truncated render.
  Widget _upcoming(Channel channel) {
    final List<Programme> rest = channel.schedule
        .where((Programme p) => p.startMinute > GuideController.now)
        .take(4)
        .toList();

    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: <Widget>[
        const SectionHeader(title: 'Sırada'),
        if (rest.isEmpty)
          const WDiv(
            className: 'w-full p-3 rounded-lg border border-color-border-subtle',
            child: WText('Bu kanal için sonraki yayın bilgisi yok.', className: 'text-xs text-fg-muted'),
          )
        else
          for (final Programme programme in rest)
            WDiv(
              className: 'flex flex-row items-baseline gap-3 w-full',
              children: <Widget>[
                WText(
                  programme.startLabel,
                  className: 'shrink-0 w-10 text-xs font-semibold text-fg-muted',
                  textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                ),
                WDiv(
                  className: 'flex-1 min-w-0',
                  child: WText(programme.title, className: 'text-sm text-fg line-clamp-1'),
                ),
              ],
            ),
      ],
    );
  }

  List<FactEntry> _facts(Channel channel) {
    // Matched on the fact's shape, not read by position. A provider's fact list
    // is an unordered bag, so `facts[2]` printed `H.265` under the label `Ses`
    // for any channel whose list ran video, video, video.
    final List<String> video = StreamFacts.videoIn(channel.facts);
    final String? audio = StreamFacts.audioIn(channel.facts);

    return <FactEntry>[
      FactEntry(label: 'Kanal', value: '${channel.name} · ${channel.numberLabel}'),
      FactEntry(label: 'Grup', value: channel.group),
      FactEntry(label: 'Video', value: video.isEmpty ? 'Bilinmiyor' : video.join(' · ')),
      FactEntry(label: 'Ses', value: audio ?? 'Bilinmiyor'),
      FactEntry(label: 'Altyazılar', value: 'Hiçbiri', onTap: () {}),
    ];
  }

  /// The panel's phone form: what is on, how far in, and the button.
  Widget _dock() {
    final Channel channel = controller.channel;
    final Programme? live = controller.programme;

    return WDiv(
      className: '''
        flex flex-col w-full shrink-0
        bg-surface-container
        border-t border-color-border-subtle
      ''',
      children: <Widget>[
        if (live != null) PlayProgress(value: live.progressAt(GuideController.now), tone: 'live', size: 'sm'),
        WDiv(
          className: 'flex flex-row items-center gap-3 w-full p-3',
          children: <Widget>[
            WDiv(
              className: 'shrink-0',
              child: ChannelMark(channel: channel, size: 'sm'),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: WDiv(
                className: 'flex flex-col',
                children: <Widget>[
                  WText(live?.title ?? 'Akış bilgisi yok', className: 'text-sm font-semibold text-fg line-clamp-1'),
                  WText(
                    live == null ? channel.name : '${channel.name} · ${live.endLabel}',
                    className: 'text-xs text-fg-muted line-clamp-1',
                  ),
                ],
              ),
            ),
            WDiv(
              className: 'shrink-0',
              child: WAnchor(
                onTap: () {},
                semanticLabel: live == null ? '${channel.name} izle' : '${live.title} izle',
                child: const WDiv(
                  className: '''
                    size-10 rounded-full items-center justify-center
                    bg-primary text-on-primary
                    hover:bg-primary-hover
                    focus:ring-2 focus:ring-focus-ring
                  ''',
                  child: WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
