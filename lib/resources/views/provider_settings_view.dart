import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../ui/layouts/provider_settings_layout.dart';

/// The provider settings screen.
///
/// A plain [StatelessWidget] rather than a `MagicStatefulView`, because there
/// is nothing below the widget to resolve: the screen reads no state, drives no
/// controller and writes nothing. The other four screens each carry a
/// controller and take the `MagicStatefulView` shape; this one would be
/// declaring a dependency it does not have.
///
/// The mounting half is thin here for the same reason it is thin on the other
/// four: `lib/resources/views/` is excluded from the CI coverage denominator,
/// so the screen's behaviour lives in `ProviderSettingsLayout` where a test can
/// reach it.
class ProviderSettingsView extends StatelessWidget {
  /// Creates the [ProviderSettingsView].
  const ProviderSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: ProviderSettingsLayout());
  }
}
