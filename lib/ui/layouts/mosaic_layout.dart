import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../components/channel_mark/index.dart';
import '../components/favourite_button/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';

/// Direction four: the line-up as an index.
///
/// A uniform grid of square channel marks with a now-and-next strip pinned to
/// the bottom. 1:1 is the documented ratio for a channel logo, on both Apple's
/// and Android TV's guidance, and it is the only card shape that does not
/// promise artwork the provider never sends.
///
/// It is the densest of the four and the only one whose cost per channel does
/// not grow with the line-up: a mark, a number, and a status dot. What it gives
/// up is the programme. You can see two hundred channels at once and none of
/// what is on them, which is why the bottom strip exists.
///
/// The selection treatment borrows Apple's shadow and nothing else, and the
/// reason is worth recording because the first version of this file got it
/// wrong twice over.
///
/// The shadow IS Apple's, verified line for line against Re-Lax's
/// `ParallaxView.swift` (25% black at 5 blur 4 down at rest; 52.5% at 40 blur
/// 50 down when picked). That is also the part its own author identifies as
/// doing most of the perceptual work.
///
/// The scale is ours, at 1.06, and it is a taste call rather than an evidence
/// one. tvOS does grow a focused item by a constant 70 points on its largest
/// dimension, but three things make copying that number here wrong. It is one
/// term of a 3D matrix in Re-Lax, installed with a perspective tilt and a sheen
/// on `didUpdateFocus`; this app has no focus model at all yet, so the effect
/// would be keyed to SELECTION, which is the one distinction the status token
/// file argues must never collapse. And 70 points on a 132 pixel tile is 53%,
/// not the 22% a five-column Apple card gets, so it needs 35 points of gutter
/// a side that this grid does not have.
///
/// 1.06 is small enough to live inside the existing spacing and to read as
/// emphasis rather than as a jump. If the D-pad work lands and focus becomes a
/// state of its own, the constant is worth revisiting on a tile sized for it.
@immutable
class MosaicLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [MosaicLayout].
  const MosaicLayout({super.key, required this.controller});

  /// The maximum tile edge handed to the grid delegate.
  ///
  /// Not the rendered edge: `SliverGridDelegateWithMaxCrossAxisExtent` divides
  /// the width into `ceil(w / (max + spacing))` columns, so the real cell is
  /// usually narrower. Anything that has to be exact cannot be derived from
  /// this number, which is the second reason the tvOS constant did not survive
  /// (see the class comment).
  static const double tile = 132;

  /// How much a picked tile grows. Ours, not Apple's.
  static const double pickedLift = 1.06;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wScreenIs(context, 'md')) const NavRail(),
        WDiv(
          className: 'flex-1 flex flex-col min-w-0',
          children: <Widget>[
            _toolbar(),
            CategoryStrip(controller: controller, pills: true),
            WDiv(className: 'flex-1 min-w-0', child: _grid()),
            _strip(),
          ],
        ),
      ],
    );
  }

  Widget _toolbar() {
    return WDiv(
      className: 'flex flex-row items-center gap-3 px-6 pt-6',
      children: <Widget>[
        WDiv(
          className: 'flex-1 max-w-[420px] min-w-0',
          child: WInput(
            value: controller.query,
            onChanged: controller.search,
            placeholder: 'Kanal adı veya numara',
            className: '''
              border-0
              rounded-full px-4 py-2.5
              bg-surface-container
              text-sm text-fg
              hover:bg-surface-container-high
              focus:ring-2 focus:ring-focus-ring
            ''',
          ),
        ),
        WDiv(
          className: 'flex flex-col shrink-0',
          children: <Widget>[
            WText(controller.countLabel, className: 'text-xs text-fg-muted'),
            if (controller.noGuideNote != null) WText(controller.noGuideNote!, className: 'text-xs text-fg-disabled'),
          ],
        ),
      ],
    );
  }

  Widget _grid() {
    if (controller.matches.isEmpty) return GuideEmpty(controller: controller);

    // A real `GridView`, not Wind's `grid-cols-N`, which composes a static
    // `Wrap` and builds every cell. A two hundred channel category is already
    // more than a frame's worth.
    return GridView.builder(
      primary: true,
      // 36 of top padding, not 8. The focus lift grows a tile by a constant 70
      // points, so 35 of that lands above the first row and collided with the
      // category strip. Apple's own grid spec reserves 100 vertically for the
      // same reason.
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tile,
        // 20 either way, which the 1.06 lift fits inside with room to spare.
        // Apple's grid asks for 40 horizontal and 100 vertical, and that is
        // sized for a 70 point growth this deliberately does not use.
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        // Taller than square: the tile is 1:1 and the number and status line
        // sit under it rather than over the mark.
        childAspectRatio: 0.82,
      ),
      itemCount: controller.matches.length,
      itemBuilder: (BuildContext context, int index) => _tile(controller.matches[index]),
    );
  }

  Widget _tile(Channel channel) {
    final bool selected = identical(channel, controller.channel);
    final Programme? now = channel.programmeAt(GuideController.now);

    return WAnchor(
      onTap: () => controller.selectChannel(channel),
      semanticLabel: '${channel.numberLabel} ${channel.name}',
      child: WDiv(
        className: 'flex flex-col items-center gap-2 focus:ring-2 focus:ring-focus-ring',
        children: <Widget>[
          // The lift is drawn with a Transform rather than with a size change
          // so the cell keeps its slot and the grid never reflows. That is the
          // whole reason Apple can afford the effect on a grid at all.
          Expanded(
            child: AnimatedScale(
              scale: selected ? pickedLift : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  // Only the picked tile carries one.
                  //
                  // Re-Lax paints a resting shadow too (25% black, 5 blur, 4
                  // down), and copying it meant a blur per tile: on this grid
                  // that is twenty three blurs a frame for an effect invisible
                  // against `bg-surface`, and it repeatedly took CanvasKit's
                  // wasm heap down mid-rebuild (`memory access out of bounds`,
                  // then `Cannot dispose picture`) when a search shrank the
                  // grid. The picked tile's 52.5% at 40 blur 50 down is
                  // Re-Lax's exactly, and it is the part that does the work.
                  boxShadow: selected
                      ? const <BoxShadow>[BoxShadow(color: Color(0x86000000), blurRadius: 40, offset: Offset(0, 50))]
                      : null,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ChannelMark(channel: channel, size: 'xl', className: 'size-full rounded-xl'),
                      // Favourite state has to be legible in the grid itself.
                      // A wall of two hundred identical marks where the only
                      // difference is in a strip at the bottom is a wall the
                      // user cannot navigate by memory.
                      if (channel.favourite)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: FavouriteButton(
                            starred: true,
                            subject: channel.name,
                            shape: 'badge',
                            onToggle: () => controller.toggleFavourite(channel),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          WDiv(
            className: 'flex flex-row items-center gap-1.5',
            children: <Widget>[
              _dot(channel),
              WText(
                channel.numberLabel,
                className: selected ? 'text-[11px] font-bold text-fg' : 'text-[11px] font-semibold text-fg-disabled',
                textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
              ),
            ],
          ),
          // `akış yok` rather than the channel name again. Repeating the name
          // under the mark that already shows it says nothing, and it hides the
          // one fact the user needs: this channel has no guide.
          WText(
            now?.title ?? 'akış yok',
            className: now == null
                ? 'text-[11px] text-fg-disabled truncate'
                : selected
                ? 'text-[11px] text-fg truncate'
                : 'text-[11px] text-fg-muted truncate',
          ),
        ],
      ),
    );
  }

  Widget _dot(Channel channel) {
    final String tone = switch (channel.status) {
      ChannelStatus.live => 'bg-live',
      ChannelStatus.recording => 'bg-recording',
      ChannelStatus.catchup => 'bg-catchup',
      ChannelStatus.idle => 'bg-surface-container-high',
    };

    return WDiv(className: 'size-1.5 shrink-0 rounded-full $tone');
  }

  /// Now and next for the selected channel, pinned to the bottom.
  ///
  /// The vendors' own taxonomy calls this the minimal "now and next" bar, and
  /// it is what makes a grid of logos answer the question a grid of logos
  /// otherwise cannot.
  Widget _strip() {
    final Channel channel = controller.channel;
    final Programme? now = controller.programme;
    final Programme? next = channel.nextAfter(GuideController.now);

    // Two lines below `md`, one above it. At 414 pixels the single row put the
    // mark, three lines of text, a circular star and a labelled play button on
    // one axis: they overlapped into an unreadable pile. The mark also drops on
    // a phone, because the tile the user just tapped already showed it.
    return WDiv(
      className: '''
        flex flex-row items-center gap-3 md:gap-4
        h-[112px] md:h-[104px] shrink-0 px-4 md:px-6
        bg-surface-container
      ''',
      children: <Widget>[
        WDiv(
          className: 'hidden md:block',
          child: ChannelMark(channel: channel, size: 'lg'),
        ),
        WDiv(
          className: 'flex-1 min-w-0',
          child: WDiv(
            className: 'flex flex-col gap-1 min-w-0',
            children: <Widget>[
              WDiv(
                className: 'flex flex-row items-baseline gap-2 min-w-0',
                children: <Widget>[
                  // The strip had no heading, so a screen reader met a mark, a
                  // name and two times with nothing saying what they were
                  // about. Sighted it answers the question a grid of two
                  // hundred identical marks raises: which one is this about.
                  const WText(
                    'SEÇİLİ KANAL',
                    className: 'shrink-0 text-[10px] font-bold text-fg-disabled tracking-wide',
                  ),
                  WText(channel.name, className: 'text-sm font-bold text-fg'),
                  WText(channel.numberLabel, className: 'text-xs text-fg-disabled'),
                ],
              ),
              if (now == null)
                const WText('Yayın akışı yok', className: 'text-sm text-fg-disabled')
              else
                WDiv(
                  className: 'flex flex-row items-center gap-2 min-w-0',
                  children: <Widget>[
                    WText(
                      now.startLabel,
                      className: 'shrink-0 text-xs font-semibold text-epg-now',
                      textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                    ),
                    WDiv(
                      className: 'flex-1 min-w-0',
                      child: WText(now.title, className: 'text-sm text-fg truncate'),
                    ),
                  ],
                ),
              if (next != null)
                WDiv(
                  className: 'flex flex-row items-center gap-2 min-w-0',
                  children: <Widget>[
                    WText(
                      next.startLabel,
                      className: 'shrink-0 text-xs text-fg-disabled',
                      textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                    ),
                    WDiv(
                      className: 'flex-1 min-w-0',
                      child: WText(next.title, className: 'text-xs text-fg-muted truncate'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        FavouriteButton(
          starred: channel.favourite,
          subject: channel.name,
          shape: 'circle',
          onToggle: () => controller.toggleFavourite(channel),
        ),
        WAnchor(
          onTap: () {},
          semanticLabel: '${channel.name} izle',
          child: const WDiv(
            className: '''
              flex flex-row items-center justify-center gap-2 shrink-0
              size-11 md:size-auto md:h-11 md:px-6 rounded-full
              bg-primary
              text-on-primary
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
              // The word goes below `md`. A 44 pixel circle is a full-size
              // target and the icon is unambiguous; the label was what pushed
              // the row past the screen.
              WText('İzle', className: 'hidden md:block text-sm font-bold'),
            ],
          ),
        ),
      ],
    );
  }
}
