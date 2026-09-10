import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/provider_setup_controller.dart';
import '../../ui/layouts/provider_settings_layout.dart';

/// The provider settings screen.
///
/// A `MagicStatefulView<ProviderSetupController>` like the other four
/// screens, now that the layout reads a real controller rather than naming a
/// screen that is not ready yet.
class ProviderSettingsView extends MagicStatefulView<ProviderSetupController> {
  /// Creates the [ProviderSettingsView].
  const ProviderSettingsView({super.key});

  @override
  State<ProviderSettingsView> createState() => _ProviderSettingsViewState();
}

class _ProviderSettingsViewState extends MagicStatefulViewState<ProviderSetupController, ProviderSettingsView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: ProviderSettingsLayout(provider: controller));
  }
}
