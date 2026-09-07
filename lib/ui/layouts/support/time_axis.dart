import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/guide_controller.dart';

/// The half-hour ruler above a time-axis guide.
///
/// The slot containing the current minute is labelled `ŞİMDİ` rather than with
/// its own time. A guide's first question is "what is on now", and answering it
/// with `20:00` makes the reader do the arithmetic the screen already did.
@immutable
class TimeAxis extends StatelessWidget {
  /// How many pixels one minute of the window occupies.
  final double pixelsPerMinute;

  /// Creates the [TimeAxis].
  const TimeAxis({super.key, required this.pixelsPerMinute});

  /// Formats [minute] (minutes from midnight) as `HH:mm`.
  static String hhmm(int minute) =>
      '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const int start = GuideController.windowStart;
    const int now = GuideController.now;
    final List<Widget> ticks = <Widget>[];

    for (int m = start; m < start + GuideController.windowMinutes; m += 30) {
      final bool isNowSlot = now >= m && now < m + 30;

      ticks.add(
        Positioned(
          left: (m - start) * pixelsPerMinute,
          width: 30 * pixelsPerMinute - 4,
          top: 0,
          bottom: 0,
          child: WDiv(
            className: isNowSlot ? 'flex items-center px-3 rounded bg-epg-now-soft' : 'flex items-center px-3',
            child: WText(
              isNowSlot ? 'ŞİMDİ' : hhmm(m),
              className: isNowSlot
                  ? 'text-[11px] font-bold text-epg-now-soft-foreground'
                  : 'text-[11px] font-semibold text-fg-disabled',
              textStyle: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            ),
          ),
        ),
      );
    }

    return WDiv(
      className: 'flex flex-row gap-1 h-7',
      children: <Widget>[
        const WDiv(
          className: 'w-[112px] shrink-0 flex items-center',
          child: WText('BUGÜN', className: 'text-[11px] font-bold text-fg-disabled'),
        ),
        Expanded(child: Stack(children: ticks)),
      ],
    );
  }
}
