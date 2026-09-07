import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/title_item.dart';
import '../artwork/index.dart';
import 'episode_row.recipe.dart';

/// One episode of a series.
///
/// The progress bar under the still is the one thing here that has to be read
/// correctly. On every streaming platform a bar under a thumbnail means
/// "resumable, and this far in", which is exactly what it means here, so it
/// appears only on an episode the viewer actually started. An episode at zero
/// gets no bar rather than an empty one: a rail of empty troughs reads as a
/// loading state.
@immutable
class EpisodeRow extends StatelessWidget {
  /// The episode to render.
  final Episode episode;

  /// Recipe density axis: `compact` or `full`.
  final String density;

  /// Whether this is the episode the play button would resume.
  final bool selected;

  /// Fired when the row is picked.
  final VoidCallback? onTap;

  /// Creates an [EpisodeRow].
  const EpisodeRow({super.key, required this.episode, this.density = 'compact', this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = episodeRowRecipe()(variants: <String, String?>{'density': density});
    final bool full = density == 'full';

    return WAnchor(
      onTap: onTap,
      semanticLabel: '${episode.code} ${episode.title}',
      child: WDiv(
        className: '${slots['box']} focus:ring-2 focus:ring-focus-ring',
        states: selected ? const <String>{'selected'} : const <String>{},
        children: <Widget>[
          if (full) _still(slots) else WText(episode.code, className: slots['code'] ?? ''),
          WDiv(
            className: 'flex-1 min-w-0',
            child: WDiv(
              className: 'flex flex-col gap-1 min-w-0',
              children: <Widget>[
                WDiv(
                  className: 'flex flex-row items-baseline gap-2 min-w-0',
                  children: <Widget>[
                    if (full) WText(episode.code, className: slots['code'] ?? ''),
                    WDiv(
                      className: 'flex-1 min-w-0',
                      child: WText(episode.title, className: slots['title'] ?? ''),
                    ),
                  ],
                ),
                if (full && episode.synopsis != null) WText(episode.synopsis!, className: slots['synopsis'] ?? ''),
                if (episode.inProgress) _resumeNote(),
              ],
            ),
          ),
          WText(episode.runtimeLabel, className: slots['runtime'] ?? ''),
          if (selected) const WIcon(Icons.play_arrow_rounded, className: 'shrink-0 text-lg text-primary'),
        ],
      ),
    );
  }

  Widget _still(Map<String, String> slots) {
    return WDiv(
      className: '${slots['still']} w-[128px]',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Artwork(
              src: episode.imageUrl,
              slotWidth: 128,
              fallback: const WDiv(
                className: 'size-full flex items-center justify-center',
                child: WIcon(Icons.image_not_supported_outlined, className: 'text-sm text-fg-disabled'),
              ),
            ),
            if (episode.inProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: WDiv(
                  className: 'h-1 bg-scrim-strong',
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: episode.progress,
                    child: const WDiv(className: 'h-1 bg-primary'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// How much is left, in words.
  ///
  /// A bar alone says "you are somewhere in this"; the minutes say whether it
  /// is worth starting now. On a compact row this is the only progress signal,
  /// because a one pixel trough beside a runtime is noise.
  Widget _resumeNote() {
    final int left = (episode.minutes * (1 - episode.progress)).round();

    return WText('$left dk kaldı', className: 'text-xs font-semibold text-primary');
  }
}
