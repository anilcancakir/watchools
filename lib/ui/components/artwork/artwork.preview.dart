import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'artwork.dart';

/// Static preview for [Artwork].
class ArtworkPreview extends StatelessWidget {
  /// Creates the Artwork preview.
  const ArtworkPreview({super.key});

  static const Widget _fallback = WDiv(
    className: 'size-full flex items-center justify-center bg-surface-container-high',
    child: WIcon(Icons.image_not_supported_outlined, className: 'text-fg-disabled'),
  );

  @override
  Widget build(BuildContext context) {
    // A URL that resolves, a URL that will not, and no URL at all. The last two
    // have to look identical: a provider that sent a dead link and one that
    // sent nothing are the same thing to the viewer.
    return WDiv(
      className: 'flex flex-row items-start gap-4 p-6',
      children: <Widget>[
        for (final String? src in <String?>[
          'https://picsum.photos/seed/artwork/400/600',
          'https://example.invalid/missing.jpg',
          null,
        ])
          WDiv(
            className: 'w-[160px] rounded-lg overflow-hidden bg-surface-container',
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Artwork(src: src, fallback: _fallback, slotWidth: 160),
            ),
          ),
      ],
    );
  }
}
