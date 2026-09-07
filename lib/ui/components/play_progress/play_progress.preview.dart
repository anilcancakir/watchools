import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'play_progress.dart';

/// Static variant-matrix preview for [PlayProgress].
class PlayProgressPreview extends StatelessWidget {
  /// Creates the PlayProgress preview.
  const PlayProgressPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6 w-[320px]',
      children: <Widget>[
        PlayProgress(value: 0.37),
        PlayProgress(value: 0.68, tone: 'live'),
        PlayProgress(value: 0.05, size: 'lg'),
        PlayProgress(value: 0.5, size: 'sm'),
        // Both ends, because a zero-width and a full-width fill are the two
        // cases a fractional box gets wrong.
        PlayProgress(value: 0),
        PlayProgress(value: 1),
      ],
    );
  }
}
