import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'play_progress.recipe.dart';

/// How far through something the viewer is, as a bar flush with the bottom edge
/// of the artwork it belongs to.
///
/// The form is not a preference. Netflix, Plex and Apple all express progress
/// as a two to four pixel bar along the bottom edge of the image, and none of
/// them writes a percentage anywhere, because the bar is read pre-attentively
/// and the number is not: a wall of forty cards is scannable with bars and
/// unreadable with numbers.
///
/// Two tones, and they mean different things. `primary` is elapsed playback,
/// the thing the viewer chose to leave half finished. `live` is elapsed
/// broadcast, which nobody chose and which keeps moving whether or not the app
/// is open. Both are an accent colour because the accent is reserved for
/// exactly three jobs and progress is one of them.
@immutable
class PlayProgress extends StatelessWidget {
  /// Elapsed fraction, 0 to 1. Values outside the range are clamped rather than
  /// asserted: a provider's `stop` timestamp can precede its `start` one, and a
  /// guide that throws on bad EPG is worse than one that draws an empty bar.
  final double value;

  /// `primary` for playback progress, `live` for elapsed broadcast.
  final String tone;

  /// `sm` on a small card, `md` by default, `lg` under a hero.
  final String size;

  /// Creates a [PlayProgress].
  const PlayProgress({super.key, required this.value, this.tone = 'primary', this.size = 'md'});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = playProgressRecipe()(variants: <String, String>{'size': size, 'tone': tone});

    return WDiv(
      className: slots['track'],
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: WDiv(className: slots['fill']),
      ),
    );
  }
}
