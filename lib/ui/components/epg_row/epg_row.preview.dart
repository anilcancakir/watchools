import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/support/guide_fixture.dart';
import 'epg_row.dart';

/// Static preview for [EpgRow].
class EpgRowPreview extends StatelessWidget {
  /// Creates the EpgRow preview.
  const EpgRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-1 p-6',
      children: <Widget>[
        for (final Channel channel in guideFixture.take(4))
          EpgRow(
            channel: channel,
            windowStart: 19 * 60 + 30,
            windowMinutes: 210,
            pixelsPerMinute: 3.2,
            nowMinute: 20 * 60 + 12,
          ),
      ],
    );
  }
}
