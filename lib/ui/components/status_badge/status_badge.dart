import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import 'status_badge.recipe.dart';

/// The coloured half of the badge vocabulary: what a channel is doing now.
///
/// Live and recording deliberately share a red and are told apart by form. Live
/// carries the word, recording carries a dot. That is the broadcast convention,
/// and the two appear together often enough (you record a live programme) that
/// separating them by hue alone would not survive a real guide anyway.
///
/// Renders nothing for [ChannelStatus.idle]: a channel with no state does not
/// get an empty badge, it gets no badge.
@immutable
class StatusBadge extends StatelessWidget {
  /// What to announce.
  final ChannelStatus status;

  /// `soft` for a grid where many badges share the screen, `solid` for the one
  /// card the user is focused on.
  final bool solid;

  /// Optional className that overrides the recipe output entirely.
  final String? className;

  /// Creates a [StatusBadge].
  const StatusBadge({super.key, required this.status, this.solid = false, this.className});

  @override
  Widget build(BuildContext context) {
    if (status == ChannelStatus.idle) {
      return const SizedBox.shrink();
    }

    return WDiv(
      className:
          className ??
          statusBadgeRecipe()(variants: <String, String>{'status': status.name, 'tone': solid ? 'solid' : 'soft'}),
      children: <Widget>[
        if (status == ChannelStatus.recording)
          const WIcon(Icons.circle, className: 'size-2')
        else if (status == ChannelStatus.catchup)
          const WIcon(Icons.history_outlined, className: 'text-xs'),
        WText(_label(status), className: 'text-xs font-semibold'),
      ],
    );
  }

  static String _label(ChannelStatus status) => switch (status) {
    ChannelStatus.live => 'CANLI',
    ChannelStatus.recording => 'KAYIT',
    ChannelStatus.catchup => 'TEKRAR',
    ChannelStatus.idle => '',
  };
}
