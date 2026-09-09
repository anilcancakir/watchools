import '../../models/channel.dart';
import 'xtream_account.dart';
import 'xtream_credentials.dart';

/// Derives the URL a playback engine is handed, from a credential and a
/// catalogue entry alone.
///
/// Pure functions, no I/O: the panel is never asked where its streams live.
/// The credential rides in the **path** here, which is the exact opposite of
/// `XtreamClient._send`, where it rides in the query so `RequestOptions.path`
/// stays clean for the telescope interceptor. That inversion is not a
/// relaxation of the rule: the protocol has no other way to authenticate a
/// stream, so the URL itself is a secret, and everything downstream treats it
/// as one. `XtreamCredentials.describe` is the only way one of these becomes
/// printable.
///
/// The base URL comes from `XtreamCredentials.baseUrl` and from nowhere else.
/// A handshake also answers a `server_info.url` field and a live entry can
/// carry a `direct_source`, and both are refused: the mock takes
/// `server_info.url` straight off the request's `Host` header
/// (`tool/xtream-mock/server.mjs:179-181`), so trusting either hands the
/// user's subscription password to whichever host the response body named.
///
/// Live is the only shape built. The other two are `movie` and `series`, both
/// keyed on the item's own id and its `container_extension`; the segment for a
/// movie is `movie` and a `vod` segment answers 404
/// (`tool/xtream-mock/server.mjs:897` documents the parameter, `:904` branches
/// on it). Neither is written until a screen plays one.
abstract final class XtreamStreamUrl {
  /// The live containers this app can address over HTTP, best first.
  ///
  /// `ts` leads because the progressive endpoint is one continuous
  /// `ffmpeg -re -stream_loop -1 -c copy` (`tool/xtream-mock/README.md:259`)
  /// while the HLS window emits a `DISCONTINUITY` where the loop wraps
  /// (`:247`), and a discontinuity is the one thing measured to stop libmpv
  /// advancing. Ordering only, not policy: [live] takes it as an argument so a
  /// caller measuring the opposite on a real panel can invert it without
  /// touching this file.
  static const List<String> liveFormatPreference = <String>['ts', 'm3u8'];

  /// The playable URL for [channel], or null when no container satisfies both
  /// [account] and [channelFormats].
  ///
  /// Shape: `{baseUrl}/live/{username}/{password}/{streamId}.{extension}`, with
  /// every segment percent-encoded, so a credential containing a `/` cannot
  /// restructure the path.
  ///
  /// [channelFormats] is what THIS channel serves, from its live entry.
  /// [Channel] carries no format field, so an empty list is the ordinary case
  /// (any channel read back from the store) and means "unknown": the account's
  /// list then decides alone. Passing the channel's real list is what keeps the
  /// app off a request the panel refuses, since an unservable container answers
  /// 404 with a reason rather than falling back
  /// (`tool/xtream-mock/server.mjs:926-935`: AV1 has no MPEG-TS mapping, so
  /// channel 07 serves `.m3u8` only).
  ///
  /// Null rather than a guess in all three empty cases: no `Channel.streamId`
  /// (a fixture-built channel has no provider identity), an empty intersection,
  /// and an intersection [preferredFormats] does not name. That last one is
  /// deliberate rather than incidental: a panel permitting a container this app
  /// has never addressed says nothing about the path shape it needs, and
  /// appending an unmeasured extension is the guess this returns null instead
  /// of making.
  static Uri? live({
    required XtreamCredentials credentials,
    required XtreamAccount account,
    required Channel channel,
    List<String> channelFormats = const <String>[],
    List<String> preferredFormats = liveFormatPreference,
  }) {
    final int? streamId = channel.streamId;

    if (streamId == null) return null;

    final String? extension = _extension(
      allowed: account.allowedOutputFormats,
      served: channelFormats,
      preferred: preferredFormats,
    );

    if (extension == null) return null;

    return _url(credentials, <String>['live', credentials.username, credentials.password, '$streamId.$extension']);
  }

  /// The first [preferred] container that both [allowed] and [served] admit.
  ///
  /// An empty [served] is "unknown" and admits everything, which is the only
  /// asymmetry between the two lists: an empty [allowed] is a panel that
  /// permits nothing, and that is an answer rather than an absence.
  static String? _extension({
    required List<String> allowed,
    required List<String> served,
    required List<String> preferred,
  }) {
    for (final String format in preferred) {
      if (!allowed.contains(format)) continue;
      if (served.isNotEmpty && !served.contains(format)) continue;

      return format;
    }

    return null;
  }

  /// Appends [segments] to the panel root, keeping a panel path prefix.
  ///
  /// Rebuilt field by field rather than through `Uri.replace`, so a query or a
  /// fragment somebody left on the configured base URL cannot ride along into a
  /// stream request. `hasPort` rather than `port`, because `Uri.port` answers
  /// the scheme default and writing it back turns `http://host` into
  /// `http://host:80`.
  static Uri _url(XtreamCredentials credentials, List<String> segments) {
    final Uri base = Uri.parse(credentials.baseUrl);

    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: <String>[...base.pathSegments, ...segments],
    );
  }
}
