import 'package:flutter/widgets.dart';

/// Every remote image in the app.
///
/// One component because provider artwork is the one asset class this product
/// does not control: a logo may 404, a poster may be the wrong aspect, a
/// backdrop may be a 1280 pixel JPEG going into a 200 pixel slot, and any HTTP
/// call to a provider has to carry a per-provider `User-Agent`. Eleven
/// `Image.network` call sites cannot honour any of that; one can.
///
/// `cacheWidth` is why this exists today rather than when the protocol layer
/// lands. Without it Flutter decodes at the source resolution and keeps the
/// full bitmap: fifteen 400 by 600 posters in a grid of 200 pixel cells, plus a
/// 1280 by 720 backdrop, repeatedly took CanvasKit's wasm heap down mid-rebuild
/// (`RuntimeError: memory access out of bounds`, then `Cannot dispose
/// picture`). Decoding to the slot cuts that by the square of the ratio.
///
/// It is also the single place the provider `User-Agent` will go. ExoPlayer's
/// header lookup is case sensitive, so the key has to be exactly `User-Agent`,
/// and that is a mistake worth being able to make once.
@immutable
class Artwork extends StatelessWidget {
  /// The image URL, or null when the provider sent none.
  final String? src;

  /// What to draw when [src] is null or the fetch fails.
  ///
  /// Required and not defaulted. A missing poster is the common case in a real
  /// catalogue, so every call site has to have decided what it looks like; the
  /// default that would otherwise creep in is a blank box.
  final Widget fallback;

  /// How the image fills its box.
  final BoxFit fit;

  /// The layout width of the slot, in logical pixels.
  ///
  /// Used only to size the decode. Pass the real slot width or leave it null
  /// for a full-bleed image, where the viewport is the slot and there is
  /// nothing to save.
  final double? slotWidth;

  /// Creates an [Artwork].
  const Artwork({
    super.key,
    required this.src,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.slotWidth,
  });

  @override
  Widget build(BuildContext context) {
    final String? url = src;
    if (url == null) return fallback;

    final double? width = slotWidth;
    final double ratio = MediaQuery.devicePixelRatioOf(context);

    return Image.network(
      url,
      fit: fit,
      cacheWidth: width == null ? null : (width * ratio).round(),
      // Deliberately not a silent `SizedBox.shrink()`. Five of the call sites
      // this replaces did exactly that, which left a hole where the row beside
      // them showed an initial, and made a failed fetch indistinguishable from
      // a layout bug.
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
