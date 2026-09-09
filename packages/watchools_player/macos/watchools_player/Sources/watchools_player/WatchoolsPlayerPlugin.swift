import Cocoa
import FlutterMacOS

/// Registers the platform view and the one channel that drives it.
///
/// This is a spike with a narrow question: does libmpv render into a
/// `CAMetalLayer` that Flutter composites? So the API is `play`, `state` and
/// `stop` rather than anything shaped like the `PlaybackEngine` the research
/// calls for. That interface belongs in Dart and gets written once this
/// question is answered.
public class WatchoolsPlayerPlugin: NSObject, FlutterPlugin {
    private let factory: WatchoolsPlayerViewFactory

    init(factory: WatchoolsPlayerViewFactory) {
        self.factory = factory
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = WatchoolsPlayerViewFactory()
        registrar.register(factory, withId: "watchools_player/view")

        let channel = FlutterMethodChannel(name: "watchools_player", binaryMessenger: registrar.messenger)
        let instance = WatchoolsPlayerPlugin(factory: factory)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String
            else {
                result(FlutterError(code: "bad-args", message: "play needs a url", details: nil))
                return
            }
            // A per-provider User-Agent is a hard product requirement: panels
            // behind Cloudflare challenge generic clients and allowlist player
            // signatures. It arrives from Dart because it is per provider, not
            // per app.
            let userAgent = args["userAgent"] as? String ?? "VLC/3.0.20 LibVLC/3.0.20"

            guard let view = factory.currentView else {
                result(FlutterError(code: "no-view", message: "the platform view is not built yet", details: nil))
                return
            }

            if let failure = factory.engine.start(layerPointer: view.layerPointer, url: url, userAgent: userAgent) {
                result(FlutterError(code: "mpv", message: failure, details: nil))
                return
            }
            result(nil)

        case "state":
            result(factory.engine.state())

        case "captureSelf":
            // A spike affordance, not product surface: proves Flutter composites
            // what mpv drew instead of covering it.
            let args = call.arguments as? [String: Any] ?? [:]
            let path = args["path"] as? String ?? NSTemporaryDirectory() + "window.png"
            result(SelfCapture.measureMotion(pngPath: path, after: 0.6))

        case "stop":
            factory.engine.stop()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Hands Flutter the view and keeps a reference to the one it built.
///
/// One view and one engine, because mpv allows one render context per core and
/// this provider allows one connection, so a second surface has nothing to show
/// and no bytes to show it with.
final class WatchoolsPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    let engine = MpvEngine()
    private(set) var currentView: WatchoolsPlayerView?

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let view = WatchoolsPlayerView(frame: .zero)
        currentView = view
        return view
    }
}
