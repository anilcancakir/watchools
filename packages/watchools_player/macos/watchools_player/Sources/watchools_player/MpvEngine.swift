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
    /// - Returns: nil on success, or a message describing what failed.
    func start(layerPointer: Int64, url: String, userAgent: String) -> String? {
        guard let handle = mpv_create() else {
            return "mpv_create returned nil"
        }
        mpv = handle

        mpv_set_option_string(handle, "terminal", "yes")
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
                return "could not set \(key)"
            }
        }

        var wid = layerPointer
        if mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid) < 0 {
            return "mpv refused the layer pointer"
        }

        if mpv_initialize(handle) < 0 {
            return "mpv_initialize failed"
        }

        mpv_command_string(handle, "loadfile \"\(url)\"")
        return nil
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
        mpv_terminate_destroy(handle)
    }
}
