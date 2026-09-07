import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import '../../../app/support/guide_fixture.dart';
import 'channel_row.dart';

/// Static preview for [ChannelRow].
class ChannelRowPreview extends StatelessWidget {
  /// Creates the ChannelRow preview.
  const ChannelRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const int now = 20 * 60 + 12;

    return WDiv(
      className: 'flex flex-col gap-1 p-6',
      children: <Widget>[
        // The first two carry a schedule, the last two do not. Both cases are
        // in the preview because the EPG-less row is the one that quietly
        // regresses.
        for (final Channel channel in <Channel>[
          guideFixture[0],
          guideFixture[3],
          guideFixture[guideFixture.length - 3],
          guideFixture[guideFixture.length - 1],
        ])
          ChannelRow(channel: channel, nowMinute: now),
      ],
    );
  }
}
