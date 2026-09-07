import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'favourite_button.dart';

/// Static preview for [FavouriteButton].
class FavouriteButtonPreview extends StatelessWidget {
  /// Creates the FavouriteButton preview.
  const FavouriteButtonPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 p-6',
      children: <Widget>[
        for (final bool starred in <bool>[false, true])
          WDiv(
            className: 'flex flex-row items-center gap-4',
            children: <Widget>[
              for (final String shape in <String>['bare', 'circle', 'pill', 'badge'])
                FavouriteButton(starred: starred, subject: 'TRT 1', shape: shape),
            ],
          ),
      ],
    );
  }
}
