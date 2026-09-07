import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../components/artwork/index.dart';
import '../components/channel_mark/index.dart';
import '../components/favourite_button/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';

/// Direction two: the line-up as a catalogue.
///
/// Netflix and the Apple TV app. A full-bleed backdrop driven by whatever is
/// selected, then horizontal rails of 16:9 cards below it. It assumes the user
/// arrived without a destination and wants to be sold something.
///
/// This one is here to be rejected on the evidence rather than on taste, so it
/// is built honestly and its cost is on screen. Netflix shipped exactly this in
/// 2025, going from roughly seven cards per row to three or four, could not
/// prove after a year of beta that engagement improved, and took a public
/// beating for it. The reason the trade worked for them at all is that their
/// artwork carries the title, so a card needs no label. A provider line-up
/// sends a flat logo and, for a large share of channels, no programme still and
/// no title either, so the same card spends Netflix's space and returns a grey
/// rectangle.
///
/// The 16:9 shape is deliberate and follows the convention: 2:3 posters are for
/// titles whose artwork carries the name, 16:9 with a text label is for stills,
/// and 1:1 is the ratio for channel logos. Cards here show a still, so they are
/// 16:9 and they are labelled.
@immutable
class MarqueeLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [MarqueeLayout].
  const MarqueeLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool wide = wScreenIs(context, 'md');

    final List<(String, List<Channel>)> rails = _rails();

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wide) const NavRail(),
        WDiv(
          className: 'flex-1 min-w-0',
          child: CustomScrollView(
            primary: true,
            slivers: <Widget>[
              // The search bar floats over the billboard rather than sitting
              // above it. A shop window that opens on a toolbar is not a shop
              // window, and the billboard is the whole argument for this
              // layout, so the chrome has to be on top of it or the layout
              // stops being the thing it is competing as.
              SliverToBoxAdapter(
                child: Stack(
                  children: <Widget>[
                    _billboard(context),
                    Positioned(left: 0, right: 0, top: 0, child: _chrome()),
                  ],
                ),
              ),
              if (rails.isEmpty)
                // The default `hasScrollBody: true` is load-bearing here.
                // Setting it false measures the child's intrinsic height, and
                // Wind's `h-full` column path carries a `LayoutBuilder`, which
                // cannot answer an intrinsic query: an empty result set threw
                // `LayoutBuilder does not support returning intrinsic
                // dimensions` and took the viewport's geometry down with it.
                // The default hands the child the remaining extent as a tight
                // constraint instead, which is what `h-full` wants anyway.
                SliverFillRemaining(child: GuideEmpty(controller: controller))
              else
                for (final (String, List<Channel>) section in rails)
                  SliverToBoxAdapter(child: _rail(section.$1, section.$2)),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ],
    );
  }

  /// Search and categories, over the billboard.
  Widget _chrome() {
    return WDiv(
      className: 'flex flex-col gap-1 pt-5',
      children: <Widget>[
        WDiv(
          className: 'flex flex-row items-center gap-3 px-6 md:px-12',
          children: <Widget>[
            WDiv(
              className: 'flex-1 max-w-[360px] min-w-0',
              child: WInput(
                value: controller.query,
                onChanged: controller.search,
                placeholder: 'Kanal veya program ara',
                semanticLabel: 'Kanal veya program ara',
                className: '''
                  border-0
                  rounded-full px-4 py-2.5
                  bg-scrim-strong
                  text-sm text-fg
                  focus:ring-2 focus:ring-focus-ring
                ''',
              ),
            ),
            // One string, not two. As separate children the count and the note
            // overlapped at the right edge of the row: `shrink-0` keeps a child
            // from being squeezed but does nothing about a row that has run out
            // of width, and Wind clips that silently.
            //
            // On a scrim pill, like the category tabs beside it, because this
            // sits over the brightest part of the billboard and white text on a
            // pale sky clears nothing.
            WDiv(
              className: 'shrink-0 px-3 h-7 rounded-full bg-scrim flex items-center',
              child: WText(_count(), className: 'text-xs font-semibold text-fg'),
            ),
          ],
        ),
        CategoryStrip(controller: controller, pills: true, onScrim: true),
      ],
    );
  }

  /// How many channels the current filter left, and how many of them the
  /// provider sent no guide for.
  String _count() {
    final String head = controller.countLabel;
    final String? note = controller.noGuideNote;

    return note == null ? head : '$head · $note';
  }

  /// The rails, in the order a returning viewer wants them.
  ///
  /// Favourites first, because a line-up this long is only usable through them.
  /// Then the provider's own sections, and last the channels the provider sent
  /// no schedule for. Those go in their own rail rather than being mixed in:
  /// a card with no still and no title beside one with both reads as a failed
  /// load, and grouping them turns that into a statement about the provider.
  ///
  /// There is no "Up Next" rail: resume state is per-device history we do not
  /// have yet, and faking it would make the layout look better than it will be.
  List<(String, List<Channel>)> _rails() {
    final List<Channel> favourites = controller.matches.where((Channel c) => c.favourite).toList();
    final List<(String, List<Channel>)> sections = <(String, List<Channel>)>[];
    final List<Channel> blind = <Channel>[];

    for (final (String, List<Channel>) section in controller.sections) {
      final List<Channel> withSchedule = section.$2.where((Channel c) => c.hasSchedule).toList();
      blind.addAll(section.$2.where((Channel c) => !c.hasSchedule));
      if (withSchedule.isNotEmpty) sections.add((section.$1, withSchedule));
    }

    return <(String, List<Channel>)>[
      if (favourites.isNotEmpty) ('Favorileriniz', favourites),
      ...sections,
      if (blind.isNotEmpty) ('Yayın akışı olmayan kanallar', blind),
    ];
  }

  Widget _billboard(BuildContext context) {
    final Channel channel = controller.channel;
    final Programme? now = controller.programme;
    // Netflix's billboard is most of the first screen. Held to 62% of the
    // viewport so the first rail peeks: a hero with nothing under it reads as
    // the whole app rather than as the top of a page.
    final double height = (MediaQuery.sizeOf(context).height * 0.62).clamp(280.0, 620.0);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Artwork(
            src: now?.imageUrl,
            fallback: const WDiv(className: 'bg-surface-container'),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: <Color>[Color(0x000E0F11), Color(0xCC0E0F11)],
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
                stops: <double>[0.0, 0.6, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          WDiv(
            className: 'flex flex-col justify-end gap-4 h-full px-6 md:px-12 pb-10 max-w-[720px]',
            children: <Widget>[
              WDiv(
                className: 'flex flex-row items-center gap-3',
                children: <Widget>[
                  ChannelMark(channel: channel),
                  WText(channel.name, className: 'text-sm font-bold text-fg-muted tracking-wide'),
                  StatusBadge(status: channel.status),
                ],
              ),
              WText(now?.title ?? channel.name, className: 'text-3xl md:text-5xl font-bold text-fg line-clamp-2'),
              if (now?.description != null)
                WDiv(
                  className: 'max-w-[640px]',
                  child: WText(now!.description!, className: 'text-sm md:text-base text-fg-muted line-clamp-3'),
                ),
              _actions(channel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(Channel channel) {
    return WDiv(
      className: 'flex flex-row items-center gap-3',
      children: <Widget>[
        WAnchor(
          onTap: () {},
          semanticLabel: '${channel.name} izle',
          child: const WDiv(
            className: '''
              flex flex-row items-center gap-2
              h-12 px-7 rounded
              bg-inverse
              text-on-inverse
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              WIcon(Icons.play_arrow_rounded, className: 'text-xl'),
              WText('İzle', className: 'text-base font-bold'),
            ],
          ),
        ),
        FavouriteButton(
          starred: channel.favourite,
          subject: channel.name,
          shape: 'pill',
          onToggle: () => controller.toggleFavourite(channel),
        ),
      ],
    );
  }

  Widget _rail(String title, List<Channel> channels) {
    return WDiv(
      className: 'flex flex-col gap-3 pt-6',
      children: <Widget>[
        MergeSemantics(
          child: WDiv(
            className: 'flex flex-row items-baseline gap-2 px-6 md:px-12',
            children: <Widget>[
              WText(title, className: 'text-base font-bold text-fg'),
              WText('${channels.length}', className: 'text-xs font-semibold text-fg-disabled'),
            ],
          ),
        ),
        SizedBox(
          // 158 of card plus the two label lines. Measured rather than
          // guessed: 220 clipped the second line by 35 pixels, and a rail that
          // clips its own labels is the failure mode of every one of these
          // built by hand.
          height: 256,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: channels.length,
            itemBuilder: (BuildContext context, int index) => _card(channels[index]),
          ),
        ),
      ],
    );
  }

  Widget _card(Channel channel) {
    final Programme? now = channel.programmeAt(GuideController.now);
    final bool selected = identical(channel, controller.channel);

    return WAnchor(
      onTap: () => controller.selectChannel(channel),
      semanticLabel: '${channel.name} ${now?.title ?? ''}',
      child: WDiv(
        className: '''
          flex flex-col gap-2
          w-[280px] shrink-0 mx-1.5
          focus:ring-2 focus:ring-focus-ring
        ''',
        states: selected ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          WDiv(
            // A Flutter `Stack`, not a WDiv carrying `relative`: a multi-child
            // WDiv composes a Column whatever its position class says, so the
            // overlays landed in a Flex and overflowed it by 34 pixels.
            className: '''
              h-[158px] rounded-md overflow-hidden
              bg-surface-container
              selected:bg-surface-container-high
            ''',
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // The fallback is the honest cost of this layout, rendered
                // rather than argued: a channel with no still gets its mark on
                // an empty card, and most of a real line-up looks like this.
                Artwork(
                  src: now?.imageUrl,
                  slotWidth: 280,
                  fallback: Center(child: _placeholder(channel)),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: ChannelMark(channel: channel, size: 'sm', className: 'bg-surface'),
                ),
                // Favouriting lives on the card, not only on the billboard.
                // A rail is where the user actually meets a channel here, and
                // an action reachable only after selecting something else is
                // an action nobody uses.
                Positioned(
                  right: 8,
                  top: 8,
                  child: FavouriteButton(
                    starred: channel.favourite,
                    subject: channel.name,
                    shape: 'badge',
                    onToggle: () => controller.toggleFavourite(channel),
                  ),
                ),
                if (now != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: WDiv(
                      className: 'h-0.5 bg-surface-container-high',
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: now.progressAt(GuideController.now),
                        child: const WDiv(className: 'h-0.5 bg-epg-now'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          WText(now?.title ?? channel.name, className: 'text-sm font-semibold text-fg-muted truncate selected:text-fg'),
          WText(
            now == null ? '${channel.numberLabel} · yayın akışı yok' : '${channel.name} · ${now.startLabel}',
            className: 'text-xs text-fg-disabled truncate',
          ),
        ],
      ),
    );
  }

  Widget _placeholder(Channel channel) => ChannelMark(channel: channel, size: 'xl', className: 'bg-surface-container');
}
