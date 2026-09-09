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
    /// Writes a PNG of the app's own window and reports how much of it changed
    /// against a capture taken `after` seconds earlier.
    ///
    /// Motion is the proof rather than pixel variety, because a window's own
    /// chrome supplies plenty of variety and none of it moves.
    static func measureMotion(pngPath: String, after seconds: Double) -> [String: Any] {
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

        var changed = 0
        var sampled = 0
        for i in stride(from: 0, to: firstBytes.count, by: 13) {
            sampled += 1
            if firstBytes[i] != secondBytes[i] { changed += 1 }
        }

        var wrote = false
        if let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: pngPath) as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) {
            CGImageDestinationAddImage(destination, second, nil)
            wrote = CGImageDestinationFinalize(destination)
        }

        return [
            "width": first.width,
            "height": first.height,
            "changed": changed,
            "sampled": sampled,
            "wrotePng": wrote,
        ]
    }
}
