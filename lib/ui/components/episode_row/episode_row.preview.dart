import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/title_item.dart';
import '../../../app/support/vod_fixture.dart';
import 'episode_row.dart';

/// Static preview for [EpisodeRow].
class EpisodeRowPreview extends StatelessWidget {
  /// Creates the EpisodeRow preview.
  const EpisodeRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final TitleItem series = vodFixture.firstWhere((TitleItem t) => t.name == 'Bozkır Hattı');
    // Finished, part-watched, untouched, and one the provider sent no still or
    // real title for. The last is the one a design forgets.
    final List<Episode> sample = <Episode>[
      series.episodes[0],
      series.episodes[4],
      series.episodes[5],
      series.episodes.last,
    ];

    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: <Widget>[
        for (final String density in <String>['compact', 'full'])
          WDiv(
            className: 'flex flex-col gap-1 max-w-[560px]',
            children: <Widget>[
              for (final Episode episode in sample)
                EpisodeRow(
                  episode: episode,
                  density: density,
                  selected: identical(episode, series.upNext),
                ),
            ],
          ),
      ],
    );
  }
}
