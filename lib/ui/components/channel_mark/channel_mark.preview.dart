import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import 'channel_mark.dart';

/// Static preview for [ChannelMark].
class ChannelMarkPreview extends StatelessWidget {
  /// Creates the ChannelMark preview.
  const ChannelMarkPreview({super.key});

  /// Names chosen for what they break: a provider prefix, a technical suffix,
  /// a single word, a number in the name, and one that is nothing but noise.
  static const List<String> _names = <String>['TRT 1', 'TR: BEIN SPORTS 1 HD', 'Discovery Channel', 'NTV', 'HD'];

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: <Widget>[
        for (final String size in <String>['sm', 'md', 'lg', 'xl'])
          WDiv(
            className: 'flex flex-row items-center gap-3',
            children: <Widget>[
              for (final String name in _names)
                ChannelMark(
                  channel: Channel(number: 1, name: name, group: 'Ulusal', status: ChannelStatus.live),
                  size: size,
                ),
            ],
          ),
      ],
    );
  }
}
