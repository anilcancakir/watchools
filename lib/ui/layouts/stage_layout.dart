import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/guide_controller.dart';
import '../../app/models/channel.dart';
import '../../app/models/programme.dart';
import '../components/channel_mark/index.dart';
import '../components/fact_chip/index.dart';
import '../components/favourite_button/index.dart';
import '../components/status_badge/index.dart';
import 'support/category_strip.dart';
import 'support/guide_empty.dart';
import 'support/nav_rail.dart';

/// Direction three: the line-up as one object you move through.
///
/// The archetype the evidence points at for this product. A dense, text-led,
/// sectioned index on the left; one large preview on the right that follows the
/// selection. It is the only layout of the four where a channel with no logo
/// and no EPG degrades into a shorter row rather than into a grey rectangle.
///
/// Three decisions here come straight from published guidance and are worth
/// keeping if this direction wins.
///
/// Focus is a colour inversion, never a scale. Apple's tvOS lift is a constant
/// 70 points on an item's largest dimension (`1.0 + 70/max(w,h)`, verified in
/// Re-Lax against Apple's own focused/unfocused Top Shelf table), which is why
/// Apple's grid spec reserves 40 points horizontally and 100 vertically. A lift
/// that big on a 44 pixel row would either overlap its neighbours or force
/// gutters that halve the density this layout exists for.
///
/// The sections are the provider's own `group-title` values, not initial
/// letters, and the jump rail lists sections rather than the alphabet. Apple's
/// index is alphabetical because a music library is sorted that way; a line-up
/// is not, and re-sorting it discards the only structure the provider sent.
///
/// The trailing edge of a row carries nothing. Apple's guidance is explicit
/// that an index and a trailing row control fight each other, so favouriting
/// moved into the preview pane, where the object it acts on is unambiguous.
@immutable
class StageLayout extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [StageLayout].
  const StageLayout({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Below `lg` there is no room for two panes. The phone gets the index and
    // reaches the preview by tapping, which is the same information in two
    // steps rather than a two-pane layout squeezed into one column.
    final bool split = wScreenIs(context, 'lg');

    return WDiv(
      className: 'flex flex-row h-full bg-surface',
      children: <Widget>[
        if (wScreenIs(context, 'md')) const NavRail(expanded: true),
        WDiv(
          className: split ? 'w-[420px] shrink-0 flex flex-col min-w-0' : 'flex-1 flex flex-col min-w-0',
          children: <Widget>[
            _search(),
            // The strip and the scope chip are not redundant. The strip is how
            // you change scope; the chip is how you learn what the scope
            // currently is and get back out of it in one press, which is
            // Apple's rule: default broad, let the user narrow, keep the
            // narrowing visible.
            CategoryStrip(controller: controller, pills: true),
            WDiv(className: 'flex-1 min-w-0', child: _index(split)),
          ],
        ),
        if (split) WDiv(className: 'flex-1 min-w-0', child: _preview()),
      ],
    );
  }

  Widget _search() {
    return WDiv(
      className: 'flex flex-col gap-2 px-4 pt-5 pb-3',
      children: <Widget>[
        WInput(
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
        WDiv(
          className: 'flex flex-row items-baseline gap-2 px-1',
          children: <Widget>[
            WText('${controller.matches.length} kanal', className: 'text-xs text-fg-muted'),
            if (controller.noGuideNote != null)
              WText(controller.noGuideNote!, className: 'text-xs text-fg-disabled'),
            if (controller.group != 'Tümü')
              // The scope is stated rather than implied. Apple's rule is to
              // default to the broader scope and let the user narrow it, which
              // only works if the current scope is visible and one press wide.
              WAnchor(
                onTap: () => controller.selectGroup('Tümü'),
                semanticLabel: 'Kapsamı tüm kanallara genişlet',
                child: WDiv(
                  className: '''
                    flex flex-row items-center gap-1 px-2 py-0.5 rounded-full
                    bg-surface-container-high
                    text-xs text-fg-muted
                    hover:text-fg
                    focus:ring-2 focus:ring-focus-ring
                  ''',
                  children: <Widget>[
                    WText(controller.group, className: 'text-xs font-semibold'),
                    const WIcon(Icons.close_rounded, className: 'text-xs'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The index, with the jump rail only where it earns its width.
  ///
  /// On one column the rail is dropped: it costs 44 of 414 pixels, its
  /// three-letter labels are a poor touch target, and a phone has flick
  /// scrolling and a search field that a D-pad remote does not. The rail
  /// exists for the surface that has neither.
  Widget _index(bool split) {
    if (controller.matches.isEmpty) return GuideEmpty(controller: controller);

    if (!split) return _rows(showStar: true);

    return WDiv(
      className: 'flex flex-row h-full min-w-0',
      children: <Widget>[
        WDiv(className: 'flex-1 min-w-0', child: _rows(showStar: false)),
        _jumpRail(),
      ],
    );
  }

  Widget _rows({required bool showStar}) {
    // One flat list of headers and rows rather than nested builders: a
    // `ListView` per section builds every section eagerly, which is exactly
    // what a ten thousand channel line-up cannot afford.
    final List<Widget> items = <Widget>[];

    for (final (String, List<Channel>) section in controller.sections) {
      items.add(_header(section.$1, section.$2.length));
      for (final Channel channel in section.$2) {
        items.add(_row(channel, showStar: showStar));
      }
    }

    return ListView.builder(
      primary: true,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) => items[index],
    );
  }

  Widget _header(String group, int count) {
    return WDiv(
      className: 'flex flex-row items-baseline gap-2 px-4 pt-5 pb-2',
      children: <Widget>[
        WText(group.toUpperCase(), className: 'text-[11px] font-bold text-fg-muted tracking-wide'),
        WText('$count', className: 'text-[11px] font-semibold text-fg-disabled'),
      ],
    );
  }

  Widget _row(Channel channel, {required bool showStar}) {
    final Programme? now = channel.programmeAt(GuideController.now);
    final bool selected = identical(channel, controller.channel);
    final Set<String> states = selected ? const <String>{'selected'} : const <String>{};

    final Widget body = WAnchor(
      onTap: () => controller.selectChannel(channel),
      semanticLabel: '${channel.numberLabel} ${channel.name}',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-3
          h-11 px-4
          text-fg
          focus:ring-2 focus:ring-focus-ring
        ''',
        states: states,
        children: <Widget>[
          WText(
            channel.numberLabel,
            className: selected ? 'w-9 shrink-0 text-xs text-on-inverse' : 'w-9 shrink-0 text-xs text-fg-disabled',
            textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
          ),
          WDiv(
            className: 'flex-1 min-w-0',
            child: WText(channel.name, className: 'text-sm font-semibold truncate'),
          ),
          // Now-playing is the start time alone, not the title. The title is
          // three lines high in the preview pane, and repeating it here at
          // eleven pixels costs the width the channel name needs.
          if (now != null)
            WText(
              now.startLabel,
              className: selected ? 'shrink-0 text-xs text-on-inverse' : 'shrink-0 text-xs text-epg-now',
              textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            )
          else
            // A word, not a dot. A coloured dot with no label is invisible to a
            // screen reader and ambiguous to everyone else: it could mean
            // offline, muted, or unread. The row has the width to say it.
            WText(
              'akış yok',
              className: selected ? 'shrink-0 text-xs text-on-inverse' : 'shrink-0 text-xs text-fg-disabled',
            ),
        ],
      ),
    );

    // The star is a sibling of the row's anchor, never a descendant. Nested,
    // the row's own semantics node absorbs it and a screen reader can never
    // reach the star: the end-to-end walk reported the control missing on a
    // screen whose screenshot plainly showed one.
    return WDiv(
      className: '''
        flex flex-row items-center
        hover:bg-surface-container
        selected:bg-inverse selected:text-on-inverse
      ''',
      states: states,
      children: <Widget>[
        WDiv(className: 'flex-1 min-w-0', child: body),
        if (showStar)
          FavouriteButton(
            starred: channel.favourite,
            subject: channel.name,
            onToggle: () => controller.toggleFavourite(channel),
          ),
      ],
    );
  }

  /// The section jump rail, on the trailing edge of the index and nowhere near
  /// a row control.
  ///
  /// A D-pad remote has no equivalent of the touch-surface gesture that opens
  /// tvOS's own accelerated-scroll index, and neither Android TV nor Tizen
  /// inherits one, so the jump affordance has to be a real focusable target.
  Widget _jumpRail() {
    return WDiv(
      className: 'flex flex-col justify-center gap-0.5 w-11 shrink-0 py-4',
      children: <Widget>[
        for (final (String, List<Channel>) section in controller.sections)
          WAnchor(
            onTap: () => controller.selectGroup(section.$1),
            semanticLabel: '${section.$1} bölümüne git',
            child: WDiv(
              className: '''
                h-5 rounded
                flex items-center justify-center
                text-[10px] font-bold text-fg-disabled
                hover:bg-surface-container hover:text-fg
                focus:ring-2 focus:ring-focus-ring
              ''',
              child: WText(_abbreviate(section.$1), className: 'text-[10px] font-bold'),
            ),
          ),
      ],
    );
  }

  /// Three letters, not one. A provider's sections collide on their initial
  /// far too often to index by it: `Spor`, `Sinema` and `Sanat` all read `S`,
  /// and an index whose entries are indistinguishable is decoration.
  static String _abbreviate(String group) =>
      (group.length <= 3 ? group : group.substring(0, 3)).toUpperCase();

  Widget _preview() {
    final Channel channel = controller.channel;
    final Programme? now = controller.programme;
    final Programme? next = channel.nextAfter(GuideController.now);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (now?.imageUrl != null)
          Image.network(now!.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        // Two scrims rather than one. A single flat overlay dims the image
        // everywhere including the part carrying no text; a gradient keeps the
        // top of the frame bright and buys contrast only where the words are.
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
        WDiv(
          className: 'flex flex-col justify-end gap-4 h-full p-8 xl:p-12',
          children: <Widget>[
            WDiv(
              className: 'flex flex-row items-center gap-3',
              children: <Widget>[
                ChannelMark(channel: channel, size: 'lg'),
                WDiv(
                  className: 'flex flex-col gap-1 min-w-0',
                  children: <Widget>[
                    WText(channel.name, className: 'text-lg font-bold text-fg truncate'),
                    WDiv(
                      className: 'flex flex-row items-center gap-2',
                      children: <Widget>[
                        StatusBadge(status: channel.status),
                        WText(channel.group, className: 'text-xs text-fg-muted'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (now == null)
              const WText('Bu kanal için yayın akışı yok', className: 'text-sm text-fg-muted')
            else
              _programme(now),
            if (next != null)
              WDiv(
                className: 'flex flex-row items-baseline gap-2',
                children: <Widget>[
                  const WText('SONRA', className: 'text-[11px] font-bold text-fg-disabled tracking-wide'),
                  WText(next.startLabel, className: 'text-xs font-semibold text-fg-muted'),
                  WDiv(
                    className: 'flex-1 min-w-0',
                    child: WText(next.title, className: 'text-xs text-fg-muted truncate'),
                  ),
                ],
              ),
            _actions(channel),
            if (channel.facts.isNotEmpty)
              WDiv(
                className: 'flex flex-row gap-1',
                children: <Widget>[for (final String fact in channel.facts) FactChip(label: fact)],
              ),
          ],
        ),
      ],
    );
  }

  Widget _programme(Programme now) {
    // The bar is labelled `kaldı`, and the label is the point. A bar under a
    // thumbnail is a platform primitive that users read as "resumable, and I am
    // this far in" (tvOS exposes it as `playbackProgress`), which is the wrong
    // reading for a live channel. Naming what is left makes it about the
    // programme rather than about the viewer.
    final int remaining = now.endMinute - GuideController.now;

    return WDiv(
      className: 'flex flex-col gap-2 max-w-[560px]',
      children: <Widget>[
        WText(now.title, className: 'text-2xl font-bold text-fg'),
        if (now.subtitle != null) WText(now.subtitle!, className: 'text-sm text-fg-muted'),
        WDiv(
          className: 'flex flex-row items-center gap-3',
          children: <Widget>[
            WText(
              '${now.startLabel} - ${now.endLabel}',
              className: 'text-xs text-fg-muted',
              textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            ),
            WDiv(
              className: 'flex-1 h-0.5 rounded-full bg-surface-container-high overflow-hidden',
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: now.progressAt(GuideController.now),
                child: const WDiv(className: 'h-0.5 rounded-full bg-epg-now'),
              ),
            ),
            WText('$remaining dk kaldı', className: 'text-xs font-semibold text-epg-now'),
          ],
        ),
        if (now.description != null) WText(now.description!, className: 'text-sm text-fg-muted n-3'),
      ],
    );
  }

  Widget _actions(Channel channel) {
    return WDiv(
      className: 'flex flex-row items-center gap-2',
      children: <Widget>[
        WAnchor(
          onTap: () {},
          semanticLabel: '${channel.name} izle',
          child: const WDiv(
            className: '''
              flex flex-row items-center gap-2
              h-11 px-6 rounded-full
              bg-primary
              text-on-primary
              hover:bg-primary-hover
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              WIcon(Icons.play_arrow_rounded, className: 'text-lg'),
              WText('İzle', className: 'text-sm font-bold'),
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
}
