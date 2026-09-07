import 'package:flutter/widgets.dart';

import '../../../app/support/guide_fixture.dart';
import 'hero_billboard.dart';

/// Static preview for [HeroBillboard].
class HeroBillboardPreview extends StatelessWidget {
  /// Creates the HeroBillboard preview.
  const HeroBillboardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const int now = 20 * 60 + 12;

    return HeroBillboard(channel: guideFixture.first, programme: guideFixture.first.programmeAt(now), nowMinute: now);
  }
}
