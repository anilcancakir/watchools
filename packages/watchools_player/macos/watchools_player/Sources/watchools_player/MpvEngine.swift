import Foundation
import Libmpv

/// The thinnest possible libmpv host: create a core, point it at a layer, load
/// a URL, report what happened.
///
/// Deliberately not a `PlaybackEngine`. That interface belongs in Dart, with
/// buffer, live offset, position, telemetry and fault as members, and this class
/// exists to answer one question first: does mpv render into a layer that
/// Flutter composites. Everything it does beyond that is what the spike needs to
/// prove it, and no more.
final class MpvEngine {
    private var mpv: OpaquePointer?

    /// The platform view whose layer this core renders into, so a teardown of
    /// that view can tell whether it owns this core.
    private(set) var attachedViewId: Int64?

    /// Where mpv's own events go, in place of polling `state()`.
    ///
    /// A poll cannot see the events that matter. `END_FILE` carries the reason a
    /// stream stopped and the measurement that motivated this package found the
    /// reason is `0`, a clean EOF, when a token lapses: by the time a poll
    /// notices, the fault code is gone. `VIDEO_RECONFIG` is the only moment the
    /// patched `moltenvk` context re-reads the drawable size.
    let events = MpvEventPump()

    /// Options the measurements settled on, rather than mpv's defaults.
    ///
    /// Zap on the real provider's channel: 3040 ms on mpv's defaults, 1658 ms on
    /// this shape, with an 18 s mean buffer either way and zero stalls across
    /// 135 s. The pairing that matters is `cache-pause=no` with a large
    /// readahead: a starved buffer plays through with artefacts instead of
    /// freezing, which turns a stall into a signal we read rather than a
    /// behaviour the viewer sees.
    private static let liveOptions: [String: String] = [
        "cache": "yes",
        // A cap, not a target. mpv's default reads back as 3,600,000 s, so the
        // only real limiter out of the box is `demuxer-max-bytes`, which on a
        // 2 Mbps channel would read close to an hour ahead of a live edge that
        // does not exist. 180 s is the deliberate ceiling; whichever of the two
        // binds first still wins.
        //
        // `demuxer-readahead-secs` is absent on purpose: with the cache on, mpv
        // uses the maximum of the two, so any value below 180 here would be
        // inert and any value above it would silently defeat this cap.
        "cache-secs": "180",
        "cache-pause": "no",
        "cache-pause-initial": "no",
        "cache-pause-wait": "0",
        "demuxer-max-bytes": "800MiB",
        "demuxer-max-back-bytes": "200MiB",
        // mpv's own default is 60 s, which is a minute of a viewer staring at a
        // dead channel before anything happens.
        "network-timeout": "10",
        // A key/value list, so the value has to be bracketed: mpv's
        // `read_subparam` accepts `[...]` and `"..."` and has no backslash
        // escape, so `4xx\,5xx` splits at the comma and produces a garbage key
        // instead of the option. `stream-lavf-o` silently ignores what FFmpeg
        // does not recognise, so nothing reports the loss.
        //
        // `reconnect_max_retries` is deliberate rather than defensive. Measured
        // against the mock's lapsing token with a starved cache: unbounded
        // retries keep the core alive and silent for the full 75 s deadline
        // while the demuxer reads 3 to 7 s of content, and `state()` still
        // reports `gpu-next` and a picture. A bounded failure is recoverable,
        // an indefinite silent stall is not.
        "stream-lavf-o": "reconnect=1,reconnect_streamed=1,reconnect_on_http_error=[4xx,5xx],reconnect_max_retries=3",
        // Nothing here is a YouTube URL and the hook costs a subprocess probe
        // on every load.
        "ytdl": "no",
    ]

    /// Renders into `layerPointer`, which must be a `CAMetalLayer`.
    ///
    /// Refuses a second call while a core is alive: overwriting `mpv` would leak
    /// the previous core, and two cores rendering into one `CAMetalLayer` fight
    /// over the same drawable. A failure part way through destroys the handle
    /// rather than leaving a half-configured core behind, which would make the
    /// retry report "already running" instead of the original fault.
    ///
    /// - Returns: nil on success, or a message describing what failed.
    func start(viewId: Int64, layerPointer: Int64, url: String, userAgent: String) -> String? {
        if mpv != nil {
            return "a core is already running, stop it first"
        }

        guard let handle = mpv_create() else {
            return "mpv_create returned nil"
        }

        func abandon(_ message: String) -> String {
            mpv_terminate_destroy(handle)
            return message
        }

        mpv_set_option_string(handle, "msg-level", "all=warn")

        // `moltenvk`, not upstream's `macvk`: it is the only gpu context that
        // reads `WinID`, and it comes from MPVKit's carried patch.
        mpv_set_option_string(handle, "vo", "gpu-next")
        mpv_set_option_string(handle, "gpu-api", "vulkan")
        mpv_set_option_string(handle, "gpu-context", "moltenvk")
        mpv_set_option_string(handle, "hwdec", "videotoolbox")
        mpv_set_option_string(handle, "user-agent", userAgent)

        for (key, value) in Self.liveOptions {
            if mpv_set_option_string(handle, key, value) < 0 {
                return abandon("could not set \(key)")
            }
        }

        var wid = layerPointer
        if mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid) < 0 {
            return abandon("mpv refused the layer pointer")
        }

        if mpv_initialize(handle) < 0 {
            return abandon("mpv_initialize failed")
        }

        // After `mpv_initialize`, because the log level is a client-side
        // subscription rather than an option. `terminal=yes` is deliberately
        // absent: it writes mpv's own messages to the process stdout, where a
        // Flutter app cannot read them and a release build should not carry
        // them. Warnings reach Dart over the event channel instead.
        mpv_request_log_messages(handle, "warn")

        mpv = handle
        attachedViewId = viewId
        events.attach(handle: handle)

        load(handle: handle, url: url)
        return nil
    }

    /// `mpv_command` over an argv rather than `mpv_command_string`.
    ///
    /// The string form is parsed as a command line, so a URL carrying a double
    /// quote closes the token and everything after it becomes further commands.
    /// mpv ships `run` and `subprocess`, and a stream URL comes from a
    /// provider's API, so this is untrusted input reaching a command parser.
    private func load(handle: OpaquePointer, url: String) {
        let command = strdup("loadfile")!
        let target = strdup(url)!
        defer {
            free(command)
            free(target)
        }

        var argv: [UnsafePointer<CChar>?] = [
            UnsafePointer(command),
            UnsafePointer(target),
            nil,
        ]
        argv.withUnsafeMutableBufferPointer { buffer in
            _ = mpv_command(handle, buffer.baseAddress)
        }
    }

    /// Reads back enough to tell a caller whether the renderer is running.
    ///
    /// `estimated-vf-fps` is deliberately absent: mpv documents it as decoder or
    /// filter-chain output, so it reads a healthy 25 on a build that presented
    /// nothing. The video output's own name and the decoded size are what say
    /// the renderer configured.
    func state() -> [String: Any] {
        guard let handle = mpv else { return ["running": false] }

        var width: Int64 = 0
        var height: Int64 = 0
        mpv_get_property(handle, "dwidth", MPV_FORMAT_INT64, &width)
        mpv_get_property(handle, "dheight", MPV_FORMAT_INT64, &height)

        var videoOutput = ""
        if let name = mpv_get_property_string(handle, "current-vo") {
            videoOutput = String(cString: name)
            mpv_free(name)
        }

        var cacheSeconds: Double = 0
        let cacheAvailable = mpv_get_property(handle, "demuxer-cache-duration", MPV_FORMAT_DOUBLE, &cacheSeconds) >= 0

        return [
            "running": true,
            "videoOutput": videoOutput,
            "width": width,
            "height": height,
            // Nullable on purpose: mpv's own docs call this guess "very
            // unreliable, and often the property will not be available at all".
            "cacheSeconds": cacheAvailable ? cacheSeconds : NSNull(),
        ]
    }

    func stop() {
        guard let handle = mpv else { return }
        mpv = nil
        attachedViewId = nil
        // Before the destroy, so no wakeup can enqueue a drain against a handle
        // that is about to go away.
        events.detach()
        mpv_terminate_destroy(handle)
    }
}

/// Turns mpv's event queue into a callback, so the Dart side reacts rather than
/// polls.
///
/// mpv's client API has one mechanism for this: `mpv_set_wakeup_callback` fires
/// on an arbitrary internal thread and forbids calling any mpv function from
/// inside it, so the callback only schedules a drain. The drain runs on the main
/// queue, which is where a `FlutterEventSink` has to be delivered from anyway,
/// and `mpv_wait_event` with a zero timeout returns immediately, so it costs a
/// dictionary per queued event and nothing when the queue is empty. This is the
/// shape mpv's own macOS client uses.
final class MpvEventPump {
    /// Set by the plugin from the event channel's `onListen`.
    var onEvent: (([String: Any]) -> Void)?

    private var handle: OpaquePointer?

    func attach(handle: OpaquePointer) {
        self.handle = handle
        mpv_set_wakeup_callback(
            handle,
            { context in
                guard let context else { return }
                let pump = Unmanaged<MpvEventPump>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { pump.drain() }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func detach() {
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
        }
        // Clearing this before the caller destroys the core is what makes a
        // drain already queued on the main thread a no-op instead of a use
        // after free.
        handle = nil
    }

    /// Reads every queued event, then returns.
    ///
    /// One wakeup does not mean one event, and mpv only wakes once for a burst,
    /// so draining until `MPV_EVENT_NONE` is the contract rather than an
    /// optimisation.
    private func drain() {
        guard let handle else { return }

        while true {
            guard let event = mpv_wait_event(handle, 0) else { return }
            if event.pointee.event_id == MPV_EVENT_NONE { return }
            if let payload = Self.describe(event) {
                onEvent?(payload)
            }
        }
    }

    /// The three events worth forwarding, flattened for the method channel.
    ///
    /// Deliberately not every event id: the rest are either about a feature this
    /// package does not use (playlists, chapters, hooks) or are duplicated by a
    /// property observer, and an event channel that carries everything is one
    /// nobody reads.
    private static func describe(_ event: UnsafeMutablePointer<mpv_event>) -> [String: Any]? {
        switch event.pointee.event_id {
        case MPV_EVENT_END_FILE:
            guard let data = UnsafeMutablePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data)) else {
                return nil
            }
            return [
                "event": "endFile",
                // `0` is EOF, and a lapsed stream token arrives as exactly that,
                // so Dart has to treat a clean end on a live stream as a fault.
                "reason": Int(data.pointee.reason.rawValue),
                "error": Int(data.pointee.error),
            ]

        case MPV_EVENT_VIDEO_RECONFIG:
            return ["event": "videoReconfig"]

        case MPV_EVENT_LOG_MESSAGE:
            guard let data = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) else {
                return nil
            }
            return [
                "event": "log",
                "prefix": String(cString: data.pointee.prefix),
                "level": String(cString: data.pointee.level),
                "text": String(cString: data.pointee.text).trimmingCharacters(in: .newlines),
            ]

        default:
            return nil
        }
    }
}
