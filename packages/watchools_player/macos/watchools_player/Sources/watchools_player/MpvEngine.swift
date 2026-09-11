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
        // `seekable` belongs to `http.c`, the protocol, not `hls.c`, the
        // demuxer, so it rides on this key rather than the demuxer
        // passthrough below. Nothing here is ever seekable, so this saves
        // the initial probe request FFmpeg would otherwise issue to check.
        "stream-lavf-o": "reconnect=1,reconnect_streamed=1,reconnect_on_http_error=[4xx,5xx],reconnect_max_retries=3,seekable=0",
        // Nothing here is a YouTube URL and the hook costs a subprocess probe
        // on every load.
        "ytdl": "no",
        // `http_multiple` belongs to `hls.c`, the HLS demuxer, not `http.c`,
        // the protocol, so it rides on `demuxer-lavf-o` rather than
        // `stream-lavf-o`; swapping the two is not an error, it is a silent
        // drop (see the `stream-lavf-o` comment above), which is exactly how
        // this would go unnoticed. FFmpeg's HLS demuxer defaults it to -1,
        // which resolves to ON for any HTTP/1.1 or HTTP/2 server, and once on
        // it opens the NEXT segment on a SECOND connection while the current
        // one is still live. This account's `max_connections` is 1 and the
        // panel evicted the older stream at 5.79 s when a second connection
        // opened, so on an m3u8 channel this option is what stops the player
        // evicting itself. Latent rather than live today: `ts` leads the
        // container preference, so most channels never reach the HLS
        // demuxer at all.
        "demuxer-lavf-o": "http_multiple=0",
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

    /// Pauses or resumes playback.
    ///
    /// The single command surface this spike exposes past `start` and `stop`:
    /// no seek, no volume, no speed, no track selection, because the
    /// `PlaybackEngine` this class is a step toward promises none of them yet.
    /// The actual write happens on `events`' own serial queue, the same one
    /// every other mpv call this plugin makes is confined to.
    ///
    /// - Returns: nil on success, or a message describing what failed.
    func setPaused(_ paused: Bool) -> String? {
        events.setPaused(paused)
    }
}

/// Turns mpv's event queue into a callback, so the Dart side reacts rather than
/// polls.
///
/// mpv's client API has one mechanism for this: `mpv_set_wakeup_callback` fires
/// on an arbitrary internal thread and forbids calling any mpv function from
/// inside it, so the callback only schedules work.
///
/// **Every mpv call this class makes happens on `sampler`, one serial queue.**
/// That is not tidiness. `mpv_wait_event` may only be called from one thread,
/// the synchronous property reads are not marked "Safe to be called from mpv
/// render API threads" in `client.h` while the `_async` variants are, and
/// `handle` and `session` would otherwise be written from main and read from a
/// timer. Confining all three to one queue settles the thread rule, keeps the
/// blocking reads off the thread the video output presents on, and removes the
/// race, in one decision. Only the sink delivery hops to main, because that is
/// where a `FlutterEventSink` has to be called from.
final class MpvEventPump {
    /// How often the counters go out. Fast enough for a three second stall
    /// threshold to have six samples behind it, slow enough to be two channel
    /// messages a second.
    private static let tickInterval = DispatchTimeInterval.milliseconds(500)

    /// Set by the plugin from the event channel's `onListen`, and only ever
    /// touched on the main queue: the sampler builds a payload and hands it over
    /// rather than reading this itself.
    var onEvent: (([String: Any]) -> Void)?

    private var handle: OpaquePointer?
    private var ticker: DispatchSourceTimer?

    /// Where the synchronous property reads happen, off the thread the video
    /// output presents on.
    private let sampler = DispatchQueue(label: "com.watchools.player.sampler")

    /// mpv's `playlist_entry_id` for the file currently loading or playing.
    ///
    /// Stamped on every event so a reader can tell which load it is about. A
    /// ladder that reopens during a stall otherwise receives the previous
    /// variant's `END_FILE` after the new open and steps again immediately,
    /// which walks it to the bottom of the ladder on one fault.
    private var session: Int64 = 0

    func attach(handle: OpaquePointer) {
        sampler.async { self.handle = handle }
        mpv_set_wakeup_callback(
            handle,
            { context in
                guard let context else { return }
                let pump = Unmanaged<MpvEventPump>.fromOpaque(context).takeUnretainedValue()
                pump.sampler.async { pump.drain() }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        // A timer rather than property observers, and that is measured rather
        // than chosen. mpv sends a change event "only if the property value
        // changes" (`client.h`), so a counter that freezes is invisible to an
        // observer, and a frozen counter is exactly how a lapsed provider token
        // presents. `core-idle` was the candidate fast path and reads `no`
        // through an entire lapse, flipping only after `END_FILE`, so there is
        // nothing to subscribe to. The tick is the detector.
        //
        // On its own queue, not the main one, and that is load-bearing. The
        // first version ticked on the main queue for the convenience of
        // delivering straight to a `FlutterEventSink`, and playback froze at
        // `time-pos` 0.08 for the entire run: 95 ticks, buffer full, `underrun`
        // false, `demuxerIdle` true. Only the `_async` property calls and
        // `mpv_get_time_ns` carry "Safe to be called from mpv render API
        // threads" in `client.h`; the synchronous read this tick makes does
        // not, and twice a second on the thread the video output needs is
        // enough to starve it. The payload hops to main for the sink instead.
        let timer = DispatchSource.makeTimerSource(queue: sampler)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        ticker = timer
    }

    /// Stops sampling and forgets the handle, before the caller destroys it.
    ///
    /// Synchronous on the sampler on purpose: it has to return with no drain or
    /// tick in flight, because the next thing the caller does is
    /// `mpv_terminate_destroy`. Safe from main because the sampler only ever
    /// hops to main with `async`.
    func detach() {
        ticker?.cancel()
        ticker = nil

        sampler.sync {
            if let handle {
                mpv_set_wakeup_callback(handle, nil, nil)
            }
            handle = nil
        }
    }

    /// Writes mpv's `pause` property, the first property write this plugin has
    /// ever made; every prior call on `handle` has been a read.
    ///
    /// `mpv_set_property_string` rather than the `MPV_FORMAT_FLAG` form: every
    /// other write in this file (`start()`'s options) is already a string, and
    /// `pause` accepts `yes`/`no` the same way, so this stays consistent
    /// instead of introducing the only flag-typed set call in the plugin.
    ///
    /// `sync`, not `async`: the method channel's `FlutterResult` has to reflect
    /// whether the write actually reached mpv, which means the caller blocks
    /// on `sampler` until it has, the same shape `detach()` uses to return only
    /// after mpv work completes.
    ///
    /// - Returns: nil on success, or a message when no core is attached, or
    ///   when mpv itself refuses the write.
    func setPaused(_ paused: Bool) -> String? {
        sampler.sync {
            guard let handle else {
                return "no core is running, start one first"
            }
            let status = mpv_set_property_string(handle, "pause", paused ? "yes" : "no")
            return status < 0 ? "mpv refused the pause write" : nil
        }
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

            // Before `describe`, so the event that opens a session is already
            // stamped with it rather than with the previous one.
            if event.pointee.event_id == MPV_EVENT_START_FILE,
               let data = UnsafeMutablePointer<mpv_event_start_file>(OpaquePointer(event.pointee.data)) {
                session = data.pointee.playlist_entry_id
            }

            if var payload = Self.describe(event) {
                payload["session"] = session
                emit(payload)
            }
        }
    }

    /// Hands a payload to the sink on the main queue.
    ///
    /// `async`, never `sync`: `detach` blocks the caller's thread on the sampler
    /// and that caller is usually main, so a `sync` here would deadlock the two
    /// against each other.
    private func emit(_ payload: [String: Any]) {
        DispatchQueue.main.async { self.onEvent?(payload) }
    }

    /// One sample of everything the stall detector and the mini player need.
    ///
    /// No thresholds and no verdict: Dart owns the policy, because the
    /// thresholds are user-exposed settings and because CI builds no native
    /// target, so a decision made here would never be exercised by an
    /// automated run on any platform.
    private func tick() {
        guard let handle else { return }

        var payload: [String: Any] = [
            "event": "tick",
            "session": session,
            // mpv's own monotonic clock. A tick that arrives late because the
            // platform thread was blocked in a synchronous mpv call looks
            // exactly like a stalled stream from Dart, and this is what tells
            // the two apart.
            "monotonicNs": mpv_get_time_ns(handle),
        ]

        for (key, name) in [("timePos", "time-pos"), ("playbackTime", "playback-time")] {
            var value = 0.0
            if mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 {
                payload[key] = value
            }
        }

        for (key, name) in [("paused", "pause"), ("coreIdle", "core-idle")] {
            var value: Int32 = 0
            if mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 {
                payload[key] = value == 1
            }
        }

        payload.merge(Self.cacheState(handle)) { current, _ in current }
        emit(payload)
    }

    /// Reads `demuxer-cache-state` as one node.
    ///
    /// One read rather than several properties: `cache-speed` "is the same as
    /// `demuxer-cache-state/raw-input-rate`" per mpv's manual, and
    /// `demuxer-cache-duration` is in here as `cache-duration` too, so reading
    /// them separately would be the same bytes fetched two and three times.
    ///
    /// `underrun`, `idle` and `eof` sit under the manual's "Other fields (might
    /// be changed or removed in the future)" heading, so a missing key is left
    /// absent rather than defaulted to false: absent means unknown, and false
    /// would claim the stream is healthy.
    private static func cacheState(_ handle: OpaquePointer) -> [String: Any] {
        var node = mpv_node()
        guard mpv_get_property(handle, "demuxer-cache-state", MPV_FORMAT_NODE, &node) >= 0 else {
            return [:]
        }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else {
            return [:]
        }

        let wanted = [
            "fw-bytes": "forwardBytes",
            "raw-input-rate": "inputRate",
            "cache-end": "cacheEnd",
            "reader-pts": "readerPts",
            "underrun": "underrun",
            "idle": "demuxerIdle",
            "eof": "demuxerEof",
        ]

        var found: [String: Any] = [:]
        for i in 0..<Int(list.pointee.num) {
            guard let raw = list.pointee.keys?[i].map({ String(cString: $0) }),
                  let key = wanted[raw]
            else {
                continue
            }

            let value = list.pointee.values![i]
            switch value.format {
            case MPV_FORMAT_INT64: found[key] = value.u.int64
            case MPV_FORMAT_DOUBLE: found[key] = value.u.double_
            case MPV_FORMAT_FLAG: found[key] = value.u.flag == 1
            default: break
            }
        }

        return found
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

        // The one event that means "you did not see some events". mpv's own
        // header: it fires when the per-handle ring buffer overflows "and at
        // least 1 event had to be dropped", which on a fault channel is the
        // difference between a quiet stream and a lost fault. Forwarded so Dart
        // distrusts its own history rather than concluding nothing happened.
        case MPV_EVENT_QUEUE_OVERFLOW:
            return ["event": "eventsLost"]

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
