import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/protocol/xtream/xtream_account.dart';
import 'package:watchools/app/protocol/xtream/xtream_credentials.dart';
import 'package:watchools/app/protocol/xtream/xtream_stream_url.dart';

/// The credential every case below builds from.
XtreamCredentials _credentials({String baseUrl = 'http://panel.example:8080', String password = 's3cret'}) =>
    XtreamCredentials(baseUrl: baseUrl, username: 'bob', password: password, userAgent: 'Watchools/1.0');

/// An account permitting exactly what the measured panel permits
/// (`tool/xtream-mock/server.mjs:174`).
XtreamAccount _account({List<String> formats = const <String>['m3u8', 'ts']}) => XtreamAccount(
  auth: true,
  status: 'Active',
  expiresAt: null,
  maxConnections: 2,
  activeConnections: 1,
  allowedOutputFormats: formats,
  panelTimestamp: null,
  panelTime: null,
);

/// Channel 02 of the mock. [Channel.streamId] is the provider identity the
/// path is keyed on; the channel number is not.
const Channel _channel = Channel(
  number: 2,
  name: '02 H.264 AAC | RAW TS',
  group: 'RAW TS',
  status: ChannelStatus.live,
  streamId: 10002,
);

/// A channel built from a fixture, which honestly has no provider identity.
const Channel _fixtureChannel = Channel(number: 2, name: 'TRT 1', group: 'Ulusal', status: ChannelStatus.live);

void main() {
  group('live', () {
    test('builds /live/<user>/<pass>/<id>.ts against the account and the channel', () {
      final Uri? url = XtreamStreamUrl.live(
        credentials: _credentials(),
        account: _account(),
        channel: _channel,
        channelFormats: const <String>['m3u8', 'ts'],
      );

      expect(url, Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.ts'));
      expect(url.toString(), 'http://panel.example:8080/live/bob/s3cret/10002.ts');
    });

    test('keeps a panel path prefix, since the credential rides after it', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(baseUrl: 'http://panel.example:8080/panel'),
          account: _account(),
          channel: _channel,
        ),
        Uri.parse('http://panel.example:8080/panel/live/bob/s3cret/10002.ts'),
      );
    });

    test('a trailing slash on the base URL cannot produce a double slash', () {
      // The constructor already strips it. This asserts the property rather
      // than re-implementing the strip here.
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(baseUrl: 'http://panel.example:8080/'),
          account: _account(),
          channel: _channel,
        ),
        Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.ts'),
      );
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(baseUrl: 'http://panel.example:8080/panel//'),
          account: _account(),
          channel: _channel,
        ),
        Uri.parse('http://panel.example:8080/panel/live/bob/s3cret/10002.ts'),
      );
    });

    test('encodes a credential segment rather than letting it restructure the path', () {
      final Uri? url = XtreamStreamUrl.live(
        credentials: _credentials(password: 'a/b c'),
        account: _account(),
        channel: _channel,
      );

      expect(url?.pathSegments, <String>['live', 'bob', 'a/b c', '10002.ts']);
      expect(url.toString(), 'http://panel.example:8080/live/bob/a%2Fb%20c/10002.ts');
    });
  });

  group('extension', () {
    test('prefers ts when the account and the channel both serve it', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(),
          channel: _channel,
          channelFormats: const <String>['ts', 'm3u8'],
        )?.pathSegments.last,
        '10002.ts',
      );
    });

    test('yields m3u8 when the channel excludes ts, as channel 07 does', () {
      // AV1 has no MPEG-TS mapping, so a `.ts` request 404s with a reason
      // (`tool/xtream-mock/server.mjs:926-935`). The intersection is the only
      // thing that keeps the app off that request.
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(),
          channel: _channel,
          channelFormats: const <String>['m3u8'],
        ),
        Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.m3u8'),
      );
    });

    test('falls back to the account list alone on an empty channel list', () {
      // What a cached channel produces: `Channel` carries no format field, so
      // "unknown" is the normal case rather than an error.
      expect(
        XtreamStreamUrl.live(credentials: _credentials(), account: _account(), channel: _channel),
        Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.ts'),
      );
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(formats: const <String>['m3u8']),
          channel: _channel,
        ),
        Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.m3u8'),
      );
    });

    test('is null when the channel and the account share no format', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(formats: const <String>['ts']),
          channel: _channel,
          channelFormats: const <String>['m3u8'],
        ),
        isNull,
      );
    });

    test('is null when the account permits nothing this app can address', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(formats: const <String>[]),
          channel: _channel,
        ),
        isNull,
      );
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(formats: const <String>['rtmp']),
          channel: _channel,
        ),
        isNull,
      );
    });

    test('follows the caller preference order rather than a hardcoded one', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(),
          channel: _channel,
          preferredFormats: const <String>['m3u8', 'ts'],
        ),
        Uri.parse('http://panel.example:8080/live/bob/s3cret/10002.m3u8'),
      );
    });

    test('honours the preference order even when it names one format only', () {
      expect(
        XtreamStreamUrl.live(
          credentials: _credentials(),
          account: _account(),
          channel: _channel,
          channelFormats: const <String>['m3u8'],
          preferredFormats: const <String>['ts'],
        ),
        isNull,
      );
    });
  });

  group('stream id', () {
    test('is null for a channel with no provider identity', () {
      expect(XtreamStreamUrl.live(credentials: _credentials(), account: _account(), channel: _fixtureChannel), isNull);
    });
  });
}
