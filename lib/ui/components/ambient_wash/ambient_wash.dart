import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../artwork/index.dart';
import '../scrim/index.dart';

/// The tinted background a detail page sits on, pulled from its own artwork.
///
/// Plex washes a title's page with a colour taken out of the poster, darkening
/// toward the bottom. It is the single cheapest thing in the references: it
/// makes every title's page feel like that title without a single bespoke
/// asset, and it degrades to a plain dark page when the artwork is missing,
/// which for a provider-fed catalogue is a third of the time.
///
/// The blur is a decode, not a filter. `ImageFilter.blur` at the sigma this
/// needs is a full-surface convolution every frame, and this app has already
/// taken CanvasKit's heap down once over image handling. Decoding the backdrop
/// to 24 pixels and letting `BoxFit.cover` stretch it produces the same smear
/// for the cost of a thumbnail, and the bilinear upscale is the blur.
@immutable
class AmbientWash extends StatelessWidget {
  /// The artwork to pull the wash from. Null renders the plain page colour,
  /// which is the designed state rather than a fallback.
  final String? src;

  /// The page content.
  final Widget child;

  /// Creates an [AmbientWash].
  const AmbientWash({super.key, required this.src, required this.child});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'w-full h-full bg-surface',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (src != null)
            Artwork(
              src: src,
              // 24 logical pixels, before the device ratio Artwork applies. Any
              // smaller and a two-tone backdrop collapses to one flat colour.
              slotWidth: 24,
              fallback: const SizedBox.shrink(),
            ),
          Scrim.ambient,
          child,
        ],
      ),
    );
  }
}
