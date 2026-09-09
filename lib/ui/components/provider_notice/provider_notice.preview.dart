import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/provider_fault.dart';
import 'provider_notice.dart';

/// Static variant-matrix preview for [ProviderNotice].
///
/// The three faults side by side, which is the only way to check the thing the
/// component exists for: that a viewer meeting one of them can tell which one
/// it is and what to do about it. Read them as a set rather than one at a time,
/// because the failure mode is three panels that say the same thing in
/// different words.
///
/// The middle column carries a technical line and the outer two do not, so both
/// shapes are visible at once. It is the only surface these render on until the
/// Xtream client can produce a fault.
class ProviderNoticePreview extends StatelessWidget {
  /// Creates the ProviderNotice preview.
  const ProviderNoticePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: <Widget>[
        const WText(
          'Tek başına, gerçek genişlikte: ekranda bir seferde yalnızca biri çıkar',
          className: 'text-xs text-fg-muted',
        ),
        WDiv(
          className: 'w-full h-[320px] rounded-lg bg-surface-container',
          child: ProviderNotice(
            fault: ProviderFault.expired,
            detail: 'HTTP 401, tr.example-provider.com',
            onRetry: () {},
            onOpenSettings: () {},
          ),
        ),
        const WText(
          'Dördü yan yana: her biri ne olduğunu, neden olduğunu ve tek eylemi söyler',
          className: 'text-xs text-fg-muted',
        ),
        // `items-start`, never `items-stretch`. Stretch hands each panel the
        // row's own cross-axis extent, which is unbounded inside this scrolling
        // column, and the `h-full` in the notice's box then has no height to be
        // a fraction of: measured, it threw `RenderBox was not laid out:
        // _RenderFullHeight` and the whole page painted white. Each panel's own
        // fixed height is what bounds it.
        WDiv(
          className: 'flex flex-row items-start gap-4 w-full',
          children: <Widget>[
            _panel(ProviderFault.unreachable),
            _panel(ProviderFault.expired, detail: 'HTTP 401, tr.example-provider.com'),
            _panel(ProviderFault.throttled),
            _panel(ProviderFault.evicted),
          ],
        ),
      ],
    );
  }

  /// One fault in a card the size of a body branch.
  ///
  /// The height is fixed and the width is a flex share, because the panel's box
  /// is `h-full w-full`: handed an unbounded height it would size to its
  /// content and stop showing how it sits in the space a real screen gives it.
  Widget _panel(ProviderFault fault, {String? detail}) {
    return WDiv(
      className: 'flex-1 min-w-0 h-[360px] rounded-lg bg-surface-container',
      child: ProviderNotice(fault: fault, detail: detail, onRetry: () {}, onOpenSettings: () {}),
    );
  }
}
