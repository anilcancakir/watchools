import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/models/programme.dart';
import '../fact_chip/index.dart';
import '../status_badge/index.dart';

/// The billboard: whatever the user is pointed at, at full size.
///
/// Netflix fixes its hero by aspect (`padding-bottom: 40%`, a 2.5:1 band)
/// rather than by viewport height, so a short window does not crush it. That is
/// copied here.
///
/// Two scrims, on different axes, also from Netflix. The left-to-right one is
/// opaque at the left edge and clear by the middle, so the whole readable half
/// sits over solid colour and the text never fights the picture. The top-down
/// one fades the page colour into the artwork so the billboard has no seam.
///
/// The artwork bleeds to the right edge with no rounded corner on that side.
/// A provider's backdrop is whatever resolution it happens to be, and a hard
/// edge advertises the crop; bleeding hides it.
@immutable
class HeroBillboard extends StatelessWidget {
  /// The channel the billboard is describing.
  final Channel channel;

  /// The programme on air, or null when the guide has a hole.
  final Programme? programme;

  /// Minutes from midnight, for the progress readout.
  final int nowMinute;

  /// Creates a [HeroBillboard].
  const HeroBillboard({super.key, required this.channel, required this.programme, required this.nowMinute});

  @override
  Widget build(BuildContext context) {
    // Netflix fixes its hero by aspect rather than by a pixel height, so a
    // short window does not crush it. The floor and ceiling keep a phone from
    // spending its whole screen on the billboard and a wide monitor from
    // stretching it into a band.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => SizedBox(
        height: (constraints.maxWidth * 0.34).clamp(200.0, 360.0),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[_artwork(), _horizontalScrim(), _bottomScrim(), _content(), _clock()],
        ),
      ),
    );
  }

  Widget _artwork() {
    final String? url = programme?.imageUrl;

    if (url == null) {
      return const WDiv(className: 'bg-surface-container-high');
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      // A backdrop that fails to load must not leave a white hole in a
      // dark-first UI. Providers serve broken logo and still URLs constantly.
      errorBuilder: (_, _, _) => const WDiv(className: 'bg-surface-container-high'),
    );
  }

  Widget _horizontalScrim() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // Opaque to the left of the text, clear by the middle. Netflix's
          // `#000 0, transparent 50%` with our page colour instead of black.
          colors: <Color>[Color(0xFF0E0F11), Color(0xE60E0F11), Color(0x000E0F11)],
          stops: <double>[0, 0.32, 0.72],
        ),
      ),
    );
  }

  Widget _bottomScrim() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x000E0F11), Color(0x000E0F11), Color(0xFF0E0F11)],
          stops: <double>[0, 0.55, 1],
        ),
      ),
    );
  }

  Widget _content() {
    final Programme? now = programme;

    return WDiv(
      className: 'flex flex-col justify-end h-full px-4 md:px-8 pb-5 md:pb-7 max-w-[720px]',
      children: <Widget>[
        WDiv(
          className: 'flex flex-row items-center gap-2 mb-3',
          children: <Widget>[
            StatusBadge(status: channel.status, solid: true),
            WText(channel.name, className: 'text-xs font-semibold text-fg-muted'),
            const WText('·', className: 'text-xs text-fg-disabled'),
            WText(
              channel.numberLabel,
              className: 'text-xs text-fg-muted',
              textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            ),
          ],
        ),
        WText(now?.title ?? channel.name, className: 'text-2xl md:text-4xl font-bold text-fg leading-tight'),
        if (now?.subtitle != null) WText(now!.subtitle!, className: 'hidden sm:block text-base text-fg-muted mt-1'),
        if (now != null) _meta(now),
        if (now?.description != null)
          WText(
            now!.description!,
            className: 'hidden md:block text-sm text-fg-muted leading-relaxed mt-3 line-clamp-2',
          ),
        _actions(),
      ],
    );
  }

  Widget _meta(Programme now) {
    final int left = now.endMinute - nowMinute;

    return WDiv(
      className: 'flex flex-row items-center wrap gap-2 mt-2',
      children: <Widget>[
        if (now.episode != null) FactChip(label: now.episode!),
        WText(
          '${now.startLabel} - ${now.endLabel}',
          className: 'text-xs text-fg-muted',
          textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
        ),
        if (left > 0) WText('$left dk kaldı', className: 'text-xs font-semibold text-epg-now'),
        for (final String fact in channel.facts) FactChip(label: fact),
      ],
    );
  }

  Widget _actions() {
    return WDiv(
      className: 'flex flex-row items-center gap-3 mt-4 md:mt-5',
      children: <Widget>[
        WAnchor(
          onTap: () {},
          child: const WDiv(
            className: '''
              flex flex-row items-center gap-2
              rounded-full pl-4 pr-5 py-2.5
              bg-primary
              hover:bg-accent
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              WIcon(Icons.play_arrow_rounded, className: 'text-on-primary'),
              WText('İzle', className: 'text-sm font-bold text-on-primary'),
            ],
          ),
        ),
        WAnchor(
          onTap: () {},
          child: const WDiv(
            className: '''
              flex flex-row items-center gap-2
              rounded-full px-5 py-2.5
              bg-surface-container-high
              border border-color-border
              hover:bg-surface-container
              focus:ring-2 focus:ring-focus-ring
            ''',
            children: <Widget>[
              WIcon(Icons.info_outline, className: 'text-fg text-sm'),
              WText('Bilgi', className: 'text-sm font-semibold text-fg'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _clock() {
    final String label =
        '${(nowMinute ~/ 60).toString().padLeft(2, '0')}:'
        '${(nowMinute % 60).toString().padLeft(2, '0')}';

    return Align(
      alignment: Alignment.topRight,
      child: WDiv(
        className: 'px-4 md:px-8 pt-5 md:pt-6',
        child: WText(
          label,
          className: 'text-sm font-semibold text-fg',
          textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}
