import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/title_item.dart';
import '../../../app/support/vod_fixture.dart';
import 'title_poster.dart';

/// Static preview for [TitlePoster].
class TitlePosterPreview extends StatelessWidget {
  /// Creates the TitlePoster preview.
  const TitlePosterPreview({super.key});

  @override
  Widget build(BuildContext context) {
    // A film with everything, a part-watched film, a film with no poster, and a
    // series. The third is the one that quietly regresses.
    final List<TitleItem> sample = <TitleItem>[
      vodFixture[0],
      vodFixture[4],
      vodFixture[2],
      vodFixture.firstWhere((TitleItem t) => t.isSeries),
    ];

    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: <Widget>[
        for (final String size in <String>['sm', 'md', 'lg'])
          WDiv(
            className: 'flex flex-row items-start gap-4',
            children: <Widget>[
              for (final TitleItem title in sample)
                TitlePoster(title: title, size: size, selected: identical(title, sample.first)),
            ],
          ),
      ],
    );
  }
}
