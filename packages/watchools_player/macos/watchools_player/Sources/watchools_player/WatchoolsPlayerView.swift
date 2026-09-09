import Cocoa
import QuartzCore

/// The surface libmpv draws into, handed to Flutter as a platform view.
///
/// Modelled on `video_player_avfoundation`'s `FVPNativeVideoView.m`, which is
/// twenty five lines and does the same thing with an `AVPlayerLayer`: return an
/// externally drawn `CALayer` from `makeBackingLayer` and let Core Animation
/// composite it. Flutter's own engine forces only `wantsLayer` on a platform
/// view ("Flutter compositing requires CALayer-backed platform views") and never
/// creates or inspects the layer itself, so a `CAMetalLayer` is exactly the
/// supported shape.
///
/// Two things are ours to maintain rather than Flutter's. It sets this view's
/// frame on every present and derives its own scale from the superview, so
/// `contentsScale` and `drawableSize` have to be kept in step here. And mpv is
/// never told a resize happened: the patched `moltenvk` context answers every
/// VOCTRL with `VO_NOTIMPL`, so no `VO_EVENT_RESIZE` reaches the video output
/// and only a video reconfig re-reads `drawableSize`. Measured: growing the
/// layer leaves the swapchain at the old size, and forcing a reconfig through
/// the client API does not fix it. The real fix is a patch to
/// `moltenvk_control`; until then this view keeps `drawableSize` honest so the
/// day that patch lands there is nothing else to change.
final class WatchoolsPlayerView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        // Opaque and bottom-left anchored: the video fills the view and there is
        // nothing behind it worth blending against.
        layer.isOpaque = true
        layer.contentsGravity = .resizeAspect
        return layer
    }

    /// The layer mpv is handed, as an integer for `mpv_set_option`.
    var layerPointer: Int64 {
        guard let layer = layer else { return 0 }
        return Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        syncDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDrawableSize()
    }

    /// Keeps the Metal drawable at the backing-store resolution.
    ///
    /// Flutter never sets `contentsScale` on a platform view's layer, so without
    /// this the video renders at logical size and Core Animation upscales it,
    /// which on a Retina display is a visibly soft picture.
    private func syncDrawableSize() {
        guard let layer = layer as? CAMetalLayer else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer.contentsScale = scale

        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if pixels.width > 0 && pixels.height > 0 && layer.drawableSize != pixels {
            layer.drawableSize = pixels
        }
    }
}
