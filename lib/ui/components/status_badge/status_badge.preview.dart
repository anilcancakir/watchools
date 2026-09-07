import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import 'status_badge.dart';

/// Static variant-matrix preview for [StatusBadge].
class StatusBadgePreview extends StatelessWidget {
  /// Creates the StatusBadge preview.
  const StatusBadgePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-4 p-6',
      children: <Widget>[
        WText('soft', className: 'text-xs text-fg-muted'),
        WDiv(
          className: 'flex flex-row gap-2',
          children: <Widget>[
            StatusBadge(status: ChannelStatus.live),
            StatusBadge(status: ChannelStatus.recording),
            StatusBadge(status: ChannelStatus.catchup),
          ],
        ),
        WText('solid', className: 'text-xs text-fg-muted'),
        WDiv(
          className: 'flex flex-row gap-2',
          children: <Widget>[
            StatusBadge(status: ChannelStatus.live, solid: true),
            StatusBadge(status: ChannelStatus.recording, solid: true),
            StatusBadge(status: ChannelStatus.catchup, solid: true),
          ],
        ),
      ],
    );
  }
}
