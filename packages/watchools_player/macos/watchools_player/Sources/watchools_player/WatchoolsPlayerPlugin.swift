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

        let events = FlutterEventChannel(name: "watchools_player/events", binaryMessenger: registrar.messenger)
        events.setStreamHandler(MpvEventForwarder(pump: factory.engine.events))
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String,
                  let viewId = args["viewId"] as? Int64 ?? (args["viewId"] as? NSNumber)?.int64Value
            else {
                result(FlutterError(code: "bad-args", message: "play needs a url and a viewId", details: nil))
                return
            }
            // A per-provider User-Agent is a hard product requirement: panels
            // behind Cloudflare challenge generic clients and allowlist player
            // signatures. It arrives from Dart because it is per provider, not
            // per app.
            let userAgent = args["userAgent"] as? String ?? "VLC/3.0.20 LibVLC/3.0.20"

            guard let view = factory.view(for: viewId) else {
                result(FlutterError(
                    code: "no-view",
                    message: "no platform view is registered for \(viewId)",
                    details: nil
                ))
                return
            }

            let failure = factory.engine.start(
                viewId: viewId,
                layerPointer: view.layerPointer,
                url: url,
                userAgent: userAgent
            )
            if let failure {
                result(FlutterError(code: "mpv", message: failure, details: nil))
                return
            }
            result(nil)

        case "dispose":
            guard let args = call.arguments as? [String: Any],
                  let viewId = args["viewId"] as? Int64 ?? (args["viewId"] as? NSNumber)?.int64Value
            else {
                result(FlutterError(code: "bad-args", message: "dispose needs a viewId", details: nil))
                return
            }
            factory.forget(viewId: viewId)
            result(nil)

        case "state":
            result(factory.engine.state())

        case "captureSelf":
            // A spike affordance, not product surface: proves Flutter composites
            // what mpv drew instead of covering it.
            //
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

/// Bridges the engine's event pump to the Dart stream.
///
/// The sink only exists between `onListen` and `onCancel`, and mpv keeps
/// producing events either side of that window, so the pump's callback is
/// attached and cleared here rather than living for the plugin's lifetime.
final class MpvEventForwarder: NSObject, FlutterStreamHandler {
    private let pump: MpvEventPump

    init(pump: MpvEventPump) {
        self.pump = pump
        super.init()
    }

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        pump.onEvent = { payload in eventSink(payload) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        pump.onEvent = nil
        return nil
    }
}

/// Hands Flutter the views it asks for and resolves one by its identifier.
///
/// Keyed by `viewId` rather than holding "the current view", because Flutter
/// builds a platform view before the widget that owns it settles and rebuilds
/// it on a route change: a single `currentView` silently points at whichever
/// one was created last, which during a push is the one about to be discarded.
///
/// Still one engine, because mpv allows one render context per core and this
/// provider allows one connection, so a second surface has nothing to show and
/// no bytes to show it with. `MpvEngine.start` refuses while a core is alive, so
/// a second `play` fails loudly instead of stealing the first one's layer.
final class WatchoolsPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    let engine = MpvEngine()

    /// Weak, so a view Flutter tore down without telling us cannot be handed to
    /// mpv as a live layer. Dart's `dispose` is what prunes the entry; this is
    /// what makes a missed `dispose` harmless rather than a dangling render
    /// target.
    private var views: [Int64: WeakView] = [:]

    private struct WeakView {
        weak var view: WatchoolsPlayerView?
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let view = WatchoolsPlayerView(frame: .zero)
        views[viewId] = WeakView(view: view)
        return view
    }

    func view(for viewId: Int64) -> WatchoolsPlayerView? {
        guard let view = views[viewId]?.view else {
            views.removeValue(forKey: viewId)
            return nil
        }
        return view
    }

    /// Drops the view and tears down the core if that view was the one playing.
    ///
    /// Without this the engine keeps rendering into a layer whose view is gone,
    /// which on macOS is a live Metal drawable belonging to a deallocated
    /// `NSView`.
    func forget(viewId: Int64) {
        views.removeValue(forKey: viewId)
        if engine.attachedViewId == viewId {
            engine.stop()
        }
    }
}
