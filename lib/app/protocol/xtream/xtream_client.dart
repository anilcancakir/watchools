import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import 'xtream_credentials.dart';
import 'xtream_json.dart';

/// One panel answer, kept in both the shape a caller can read and the shape it
/// arrived in.
///
/// [data] is the decoded payload for the action that asked for it: a JSON object
/// for the handshake and `get_vod_info`, the entry list for the catalogue
/// actions, the unwrapped `epg_listings` for the two EPG actions. It is `null`
/// whenever the body is not that shape, which is a state the panel reaches
/// routinely rather than an error: a refusal arrives as HTTP 200 carrying the
/// plain word `blocked`, and a transport failure arrives as [statusCode] `0`
/// with no body at all.
///
/// [body] is what came off the wire, unread. It is the half a caller needs to
/// tell those two apart, and it is why nothing in this layer throws on an
/// unreadable body: the session classifies a provider fault from the handshake,
/// and a parse exception thrown here would arrive as a different kind of
/// failure than the one it actually is.
@immutable
class XtreamResponse<T> {
  /// The HTTP status, or `0` when the request never completed.
  ///
  /// Xtream puts failure in the body rather than the status, so a 200 says
  /// nothing about success. A 3xx reaches a caller as itself: the provider
  /// driver follows no redirect.
  final int statusCode;

  /// The decoded payload, or `null` when the body was not the expected shape.
  final T? data;

  /// The body exactly as the driver handed it over: a decoded structure, a raw
  /// [String] when the panel typed a JSON payload `text/html`, or `null`.
  final Object? body;

  const XtreamResponse({required this.statusCode, required this.data, required this.body});
}

/// The only thing in this app that speaks to a user's Xtream Codes panel.
///
/// One method per action, no interpretation. The client sends the request,
/// decodes the body into the shape that action answers with, and hands back
/// both that and the raw body. It does not classify a fault, decide a retry,
/// or paginate: there is no pagination in this protocol (`category_id` is the
/// only narrowing parameter any of five independent clients sends, and a whole
/// catalogue arrives in one array), and a fault is the session's reading of the
/// handshake rather than the client's.
///
/// **It resolves [driverKey] and never the shared `network` driver.** That
/// driver carries magic's `AuthInterceptor`, which attaches the watchools
/// bearer token to every request with no host test and reads a 401 as a signal
/// to refresh the token, re-attach it and replay. Pointed at a stranger's panel
/// that hands our token to a third party over plaintext HTTP, twice. The driver
/// is resolved per call rather than held from construction so a test can
/// substitute the binding under the same key.
///
/// **Every URL is pinned to [XtreamCredentials.baseUrl].** The handshake's
/// `server_info.url` and a stream row's `direct_source` both name a host, and
/// both are the panel's choice rather than the user's; the credentials ride in
/// the path of a stream URL, so routing by a response field hands them to
/// whichever host the response names. Nothing here reads either field.
class XtreamClient {
  /// The container key of the dedicated provider driver.
  ///
  /// Registered in `AppServiceProvider.register()` with no interceptors, and
  /// named here because the client and the binding have to agree on it.
  static const String driverKey = 'provider_network';

  /// The single endpoint the whole action surface goes through.
  static const String _endpoint = '/player_api.php';

  /// The panel this client is pointed at, validated on the way in.
  final XtreamCredentials credentials;

  /// Binds the client to one panel. A second panel is a second client.
  XtreamClient(this.credentials);

  /// The handshake: `user_info` and `server_info`, with no `action` at all.
  ///
  /// The one call that says whether the subscription is alive, and the caller
  /// reads that out of the body rather than out of [XtreamResponse.statusCode];
  /// rejected credentials arrive as HTTP 200 carrying `{"auth": 0}`.
  Future<XtreamResponse<Map<String, dynamic>>> handshake() => _object();

  /// The live channel groups.
  Future<XtreamResponse<List<Map<String, dynamic>>>> liveCategories() => _entries('get_live_categories');

  /// The VOD groups.
  Future<XtreamResponse<List<Map<String, dynamic>>>> vodCategories() => _entries('get_vod_categories');

  /// The series groups.
  Future<XtreamResponse<List<Map<String, dynamic>>>> seriesCategories() => _entries('get_series_categories');

  /// The series catalogue. An empty array is a real answer here: one of the
  /// four captured panels answers exactly that.
  Future<XtreamResponse<List<Map<String, dynamic>>>> series() => _entries('get_series');

  /// The whole live catalogue in one array, thousands of rows on a real panel.
  Future<XtreamResponse<List<Map<String, dynamic>>>> liveStreams() => _entries('get_live_streams');

  /// The whole VOD catalogue in one array, tens of thousands of rows on a real
  /// panel.
  Future<XtreamResponse<List<Map<String, dynamic>>>> vodStreams() => _entries('get_vod_streams');

  /// One movie's detail: `{info, movie_data}`, the only place this protocol
  /// carries codec metadata.
  Future<XtreamResponse<Map<String, dynamic>>> vodInfo(int vodId) =>
      _object(action: 'get_vod_info', query: <String, dynamic>{'vod_id': vodId});

  /// One channel's now/next window.
  ///
  /// [limit] is genuinely honoured by this action, unlike most optional Xtream
  /// parameters, and four is what the panel itself defaults to.
  Future<XtreamResponse<List<Map<String, dynamic>>>> shortEpg(int streamId, {int limit = 4}) =>
      _listings('get_short_epg', streamId, limit: limit);

  /// One channel's full schedule, and the typo'd spelling behind it.
  ///
  /// `get_simple_date_table` ("date", not "data") is a real action that some
  /// panels implement *instead of* the documented one, so a client sending only
  /// the correct spelling gets nothing from them. The retry fires on an empty
  /// result and not on a failure: a status this layer does not own, or a body it
  /// could not read, is the session's to interpret, and a second request would
  /// only ask the same broken panel twice.
  ///
  /// When both spellings answer empty, the documented one's response is the one
  /// returned: an empty schedule is the truthful answer for a channel with no
  /// `epg_channel_id`.
  Future<XtreamResponse<List<Map<String, dynamic>>>> simpleDataTable(int streamId) async {
    final XtreamResponse<List<Map<String, dynamic>>> documented = await _listings('get_simple_data_table', streamId);

    if (documented.statusCode != 200 || (documented.data?.isNotEmpty ?? false)) {
      return documented;
    }

    final XtreamResponse<List<Map<String, dynamic>>> misspelt = await _listings('get_simple_date_table', streamId);

    return (misspelt.data?.isNotEmpty ?? false) ? misspelt : documented;
  }

  /// Sends one action and reads the body as a JSON object.
  Future<XtreamResponse<Map<String, dynamic>>> _object({
    String? action,
    Map<String, dynamic> query = const <String, dynamic>{},
  }) async {
    final MagicResponse response = await _send(action: action, query: query);

    return XtreamResponse<Map<String, dynamic>>(
      statusCode: response.statusCode,
      data: decodeBody(response.data),
      body: response.data,
    );
  }

  /// Sends one action and reads the body as a JSON array of entries.
  Future<XtreamResponse<List<Map<String, dynamic>>>> _entries(String action) async {
    final MagicResponse response = await _send(action: action);

    return XtreamResponse<List<Map<String, dynamic>>>(
      statusCode: response.statusCode,
      data: decodeEntries(response.data),
      body: response.data,
    );
  }

  /// Sends one EPG action and unwraps the `epg_listings` envelope.
  ///
  /// Both EPG actions answer with an object wrapping the array, which is why
  /// they read through both decoders rather than [decodeEntries] alone. An
  /// envelope with no `epg_listings` key reads as `null` rather than as an
  /// empty schedule: the two are the same to a screen and not to the retry in
  /// [simpleDataTable].
  Future<XtreamResponse<List<Map<String, dynamic>>>> _listings(String action, int streamId, {int? limit}) async {
    final MagicResponse response = await _send(
      action: action,
      query: <String, dynamic>{'stream_id': streamId, 'limit': ?limit},
    );

    return XtreamResponse<List<Map<String, dynamic>>>(
      statusCode: response.statusCode,
      data: decodeEntries(decodeBody(response.data)?['epg_listings']),
      body: response.data,
    );
  }

  /// The one place a request leaves for the panel.
  ///
  /// The credential goes in the query map and never into the URL string: the
  /// telescope integration records `RequestOptions.path`, which excludes the
  /// query, so a credential concatenated into the endpoint would be written
  /// into a debug record that is otherwise clean.
  ///
  /// `User-Agent` is spelled exactly that because resellers key access control
  /// to it and ExoPlayer's lookup is case sensitive. It is the only header sent:
  /// the driver declares no default headers, which is the only way to keep one
  /// off provider traffic, since `Options(headers:)` merges over
  /// `BaseOptions.headers` rather than replacing them.
  Future<MagicResponse> _send({String? action, Map<String, dynamic> query = const <String, dynamic>{}}) {
    return Magic.make<NetworkDriver>(driverKey).get(
      '${credentials.baseUrl}$_endpoint',
      query: <String, dynamic>{
        'username': credentials.username,
        'password': credentials.password,
        'action': ?action,
        ...query,
      },
      headers: <String, String>{'User-Agent': credentials.userAgent},
    );
  }
}
