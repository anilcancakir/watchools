import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'support/page_gutter.dart';

/// Where the provider settings will live, and today only says so.
///
/// ### Why a placeholder is better than nothing here
///
/// `/saglayici` is the destination five layouts already send a user to, from
/// `ProviderNotice`'s action on the one fault that withholds a retry:
/// `expired` means the credential itself needs replacing, and retrying a
/// lapsed subscription fails identically every time. Until this file existed
/// the route was registered nowhere, so all five buttons fell through to `/`
/// and put the user back on the live screen showing the same dead catalogue,
/// with no way to tell that the button had done anything at all. Landing
/// somewhere that names the problem is the smaller failure.
///
/// ### What it deliberately is not
///
/// There is no form. Onboarding is a designed surface that does not exist yet
/// (`CLAUDE.md`), and a text field that wrote a credential to `Vault` from
/// here would be an undesigned screen shipped by accident, on the one flow in
/// this app where a mistake costs the user their subscription details. It
/// carries the two things a dead end must: what is happening, and the way
/// back.
class ProviderSettingsLayout extends StatelessWidget {
  /// Where the back affordance goes, defaulting to popping the route.
  ///
  /// A seam rather than a hardcoded `MagicRoute.back()`, for the same reason
  /// `PlaybackLayout` has one: `MagicRouter` throws `Router not initialized`
  /// without a `MaterialApp.router` above it, and a widget test has none. On a
  /// screen whose only affordance is the way out, an untestable way out is the
  /// whole screen untested.
  final VoidCallback? onBack;

  /// Creates the placeholder.
  const ProviderSettingsLayout({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      // `items-start`, and it is not cosmetic. A column stretches its children
      // across the cross axis by default, so the `size-10` disc below came out
      // as a pill spanning the whole window with the arrow centred in it. The
      // widget test could not see that: `findsOneWidget` on the semantics label
      // passes at either width. Found by looking at the running app.
      className: 'w-full h-full bg-surface ${PageGutter.x} ${PageGutter.top} flex flex-col items-start gap-6',
      children: <Widget>[
        WAnchor(
          onTap: () => (onBack ?? MagicRoute.back)(),
          semanticLabel: 'Geri',
          child: const WDiv(
            className: '''
              size-10 rounded-full items-center justify-center
              bg-surface-container text-fg
              hover:bg-surface-container-high
              focus:ring-2 focus:ring-focus-ring
            ''',
            child: WIcon(Icons.arrow_back, className: 'text-base'),
          ),
        ),
        // `w-full` back, because `items-start` above would otherwise shrink
        // this block to its widest line and the body would stop wrapping at
        // the page width.
        const WDiv(
          className: 'w-full flex flex-col gap-3',
          children: <Widget>[
            WText('Sağlayıcı ayarları', className: 'text-2xl font-bold text-fg'),
            WText(
              'Abonelik bilgilerinizi buradan güncelleyeceksiniz. Bu ekran '
              'henüz hazır değil, bu yüzden bilgileriniz şu an değiştirilemez.',
              className: 'text-base text-fg-muted',
            ),
          ],
        ),
      ],
    );
  }
}
