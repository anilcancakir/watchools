import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'fact_chip.dart';

/// Static variant-matrix preview for [FactChip].
class FactChipPreview extends StatelessWidget {
  /// Creates the FactChip preview.
  const FactChipPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-row wrap gap-1 p-6',
      children: <Widget>[
        FactChip(label: '1080p'),
        FactChip(label: 'H.265'),
        FactChip(label: '5.1'),
        FactChip(label: 'HDR'),
      ],
    );
  }
}
