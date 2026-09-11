import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Captures the app's own window, so a spike can prove that Flutter composites
/// what mpv drew rather than covering it.
///
/// An app may always capture its own window; capturing another app's needs
/// Screen Recording permission, which is why this lives in the plugin rather
/// than in a test harness outside it. That distinction cost an hour: a helper
/// binary found the window, reported its size, and then got nil from the
/// capture with no error to explain it.
enum SelfCapture {
    /// Writes a PNG of the app's own window and reports how much changed inside
    /// the platform view against how much changed in the Flutter chrome above
    /// it, over `seconds`.
    ///
    /// Motion is the proof rather than pixel variety, because a window's own
    /// chrome supplies plenty of variety and none of it moves. Two rects rather
    /// than one whole-window number, because the whole-window number cannot
    /// tell video from a repainting text label: the first version of this
    /// reported "21,648 of 155,570 bytes changed" and a moving frame counter in
    /// the overlay would have produced the same claim.
    ///
    /// The two rects also check their own coordinate mapping. Window images are
    /// top-left origin in pixels and `NSView` geometry is bottom-left origin in
    /// points, so a mapping error shifts both rects by the same amount and shows
    /// up as motion in the chrome rect, which is expected to be still.
    static func measureMotion(pngPath: String, after seconds: Double, view: NSView?) -> [String: Any] {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            return ["error": "no visible window"]
        }
        let id = CGWindowID(window.windowNumber)

        func grab() -> CGImage? {
            CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                id,
                [.boundsIgnoreFraming, .bestResolution]
            )
        }

        guard let first = grab(), let firstBytes = first.dataProvider?.data as Data? else {
            return ["error": "capture returned nil"]
        }

        // A blank capture is the trap this measurement has to refuse. On macOS
        // 26 `CGWindowListCreateImage` returns an image of the correct size
        // filled with one colour when the process is not entitled to capture,
        // and entitlement follows the *responsible* process rather than the
        // app: the same bundle measured real motion when launched from a
        // terminal that holds Screen Recording permission and returns white
        // when launched through LaunchServices. Nothing errors, `wrotePng` is
        // true, the dimensions are right, and the motion reads zero, which is
        // indistinguishable from a video that is not playing.
        if isUniform(firstBytes) {
            return [
                "error": "the window capture came back uniform, so this process is not entitled to capture it",
                "width": first.width,
                "height": first.height,
            ]
        }

        // Spin the run loop rather than sleeping: this runs on the platform
        // thread and a sleep would stall the compositor being measured.
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard let second = grab(), let secondBytes = second.dataProvider?.data as Data?,
              secondBytes.count == firstBytes.count
        else {
            return ["error": "second capture did not match shape"]
        }

        var report: [String: Any] = [
            "width": first.width,
            "height": first.height,
            "wrotePng": write(image: second, to: pngPath),
        ]
        report.merge(motion(firstBytes, secondBytes, label: "window")) { current, _ in current }

        // The two scoped rects, when a view was resolved. Absent rather than
        // zeroed when it was not: a zero here would read as "the video did not
        // move", which is the opposite of "nobody asked about a view".
        if let view, let rect = pixelRect(of: view, in: window, capturedAs: first) {
            report["viewRect"] = ["x": rect.minX, "y": rect.minY, "w": rect.width, "h": rect.height]

            if let videoPatch = crop(first, second, to: rect) {
                report.merge(motion(videoPatch.0, videoPatch.1, label: "video")) { current, _ in current }
            }

            // Everything above the platform view is Flutter's own painting. It
            // is the control: still, while the video rect moves.
            let chrome = CGRect(x: 0, y: 0, width: CGFloat(first.width), height: rect.minY.rounded(.down))
            if chrome.height >= 8, let chromePatch = crop(first, second, to: chrome) {
                report.merge(motion(chromePatch.0, chromePatch.1, label: "chrome")) { current, _ in current }
            }
        }

        return report
    }

    /// Whether every sampled byte matches the first one.
    ///
    /// True for a real window only if it is a single flat colour edge to edge,
    /// which a window with chrome in it never is.
    private static func isUniform(_ bytes: Data) -> Bool {
        guard let reference = bytes.first else { return true }

        for i in stride(from: 0, to: bytes.count, by: 13) where bytes[i] != reference {
            return false
        }
        return true
    }

    /// Samples every thirteenth byte, which is deliberately coprime with the
    /// row stride so the sample does not land on one column.
    private static func motion(_ before: Data, _ after: Data, label: String) -> [String: Any] {
        var changed = 0
        var sampled = 0
        for i in stride(from: 0, to: min(before.count, after.count), by: 13) {
            sampled += 1
            if before[i] != after[i] { changed += 1 }
        }

        return [
            "\(label)Changed": changed,
            "\(label)Sampled": sampled,
        ]
    }

    private static func crop(_ first: CGImage, _ second: CGImage, to rect: CGRect) -> (Data, Data)? {
        guard let a = first.cropping(to: rect), let b = second.cropping(to: rect),
              let aBytes = a.dataProvider?.data as Data?, let bBytes = b.dataProvider?.data as Data?
        else {
            return nil
        }
        return (aBytes, bBytes)
    }

    /// Where `view` sits inside the captured window image, in image pixels.
    ///
    /// Goes through screen coordinates because that is the one space both sides
    /// agree on: `kCGWindowBounds` is top-left origin in points and so is CG's
    /// display space, while `NSView` and `NSWindow` are bottom-left origin. The
    /// scale is taken from the image against the window bounds rather than from
    /// `backingScaleFactor`, so a capture that came back at a different
    /// resolution than the display still maps correctly.
    private static func pixelRect(of view: NSView, in window: NSWindow, capturedAs image: CGImage) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo(
            .optionIncludingWindow,
            CGWindowID(window.windowNumber)
        ) as? [[String: Any]],
            let boundsDictionary = info.first?[kCGWindowBounds as String] as? NSDictionary,
            let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
            windowBounds.width > 0,
            view.bounds.width > 0
        else {
            return nil
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let inScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
        let topLeft = CGRect(
            x: inScreen.minX - windowBounds.minX,
            y: (screenHeight - inScreen.maxY) - windowBounds.minY,
            width: inScreen.width,
            height: inScreen.height
        )

        let scale = CGFloat(image.width) / windowBounds.width
        let scaled = CGRect(
            x: (topLeft.minX * scale).rounded(.down),
            y: (topLeft.minY * scale).rounded(.down),
            width: (topLeft.width * scale).rounded(.down),
            height: (topLeft.height * scale).rounded(.down)
        )

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        return scaled.intersection(bounds)
    }

    private static func write(image: CGImage, to path: String) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
