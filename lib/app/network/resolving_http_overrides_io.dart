import 'dart:io';

import 'host_resolver.dart';

/// Installs [ResolvingHttpOverrides] for the whole process.
///
/// The platform-free entry point `app_service_provider.dart` calls, so the
/// composition root never names a `dart:io` type and the web half can be a
/// no-op. [panelHost] is a callback rather than a value because the override
/// lives for the process while the credential under it can be replaced.
void installResolvingHttpOverrides({required HostResolver resolver, required String? Function() panelHost}) {
  HttpOverrides.global = ResolvingHttpOverrides(resolver: resolver, panelHost: panelHost);
}

/// Connects the user's panel through the address [HostResolver] chose, and
/// everything else exactly as `dart:io` would have.
///
/// ## Why an override rather than a driver adapter
///
/// The provider's traffic goes out through a `DioNetworkDriver`, and the driver
/// hands `configureDriver` a `Dio` whose type this app never names: `dio` is not
/// a direct dependency and `CLAUDE.md` forbids reaching for it. Its IO adapter
/// builds a plain `HttpClient()`, and that constructor consults
/// `HttpOverrides.current` (`dart-sdk/lib/_http/http.dart:1348-1354`), so
/// installing here reaches the same sockets with no new dependency and no
/// sibling release. It also covers the DoH rung's own client and anything else
/// in the process that opens an `HttpClient`, which is why the panel-host test
/// below is not optional.
///
/// ## The two traps, both of which fail open
///
/// **`super.createHttpClient(context)`, never `HttpClient()`.** The factory at
/// the line above reads `HttpOverrides.current` and delegates to this method, so
/// constructing one here recurses until the stack dies.
///
/// **A `connectionFactory` skips the TLS branch entirely.** With one installed,
/// `dart:io` uses the returned socket as it is and never upgrades it
/// (`dart-sdk/lib/_http/http_impl.dart:2684-2703`), so handing a plain socket
/// back for an `https` URL would put the subscription password on the wire in
/// cleartext against port 443. [_connect] secures it here instead, and secures
/// it with the ORIGINAL hostname so that SNI and certificate validation both run
/// against the name while the connection goes to the address we chose.
///
/// ## What it deliberately does not do
///
/// It resolves the configured panel host and nothing else. This is process
/// wide, and silently redirecting unrelated traffic is not what a user agreed to
/// when they picked a resolver for their provider.
///
/// It reproduces neither `badCertificateCallback` nor `keyLog`, which
/// `dart:io` would have wired into a direct https connect. Nothing in this app
/// sets either, and a factory that honoured the first would be a way to turn
/// certificate validation off from a distance.
class ResolvingHttpOverrides extends HttpOverrides {
  /// The one resolver in the process. The settings screen reads the same
  /// instance's cache, so a second one would show the user an address the
  /// requests never used.
  final HostResolver resolver;

  /// The host of the panel currently configured, or null when the user has no
  /// credential loaded.
  ///
  /// Read per connection rather than captured, because `ProviderSession.adopt`
  /// can replace the credential at any point in the process's life.
  final String? Function() panelHost;

  ResolvingHttpOverrides({required this.resolver, required this.panelHost});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpClient client = super.createHttpClient(context);

    // Captured per client rather than read off a field: a caller that built its
    // client with its own [SecurityContext] (a pinned root, a client
    // certificate) must keep it through the upgrade below, which is the one
    // place TLS now starts.
    client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) =>
        _connect(url: url, proxyHost: proxyHost, proxyPort: proxyPort, context: context);

    return client;
  }

  /// Opens one connection for [url].
  ///
  /// 1. Ask [_addressFor], which answers null for everything this override has
  ///    no business touching.
  /// 2. Null means the default connect, byte for byte what `dart:io` would have
  ///    done. A resolver that cannot answer therefore degrades to the behaviour
  ///    the user had before this feature existed rather than taking the app
  ///    offline, which is the deliberate handling of a failed lookup and the
  ///    reason nothing here throws.
  /// 3. An address means a plain socket to it, upgraded for an `https` URL with
  ///    the name the caller asked for. See the class doc for why the upgrade
  ///    cannot be left to `dart:io`.
  ///
  /// Cancellation is forwarded to the underlying connect, so a client that gives
  /// up on the socket still stops the attempt it started.
  Future<ConnectionTask<Socket>> _connect({
    required Uri url,
    required String? proxyHost,
    required int? proxyPort,
    required SecurityContext? context,
  }) async {
    final String? address = await _addressFor(url, proxyHost);

    if (address == null) {
      return _defaultConnect(url: url, proxyHost: proxyHost, proxyPort: proxyPort, context: context);
    }

    final ConnectionTask<Socket> task = await Socket.startConnect(address, url.port);

    if (!url.isScheme(_https)) return task;

    return ConnectionTask.fromSocket<Socket>(
      task.socket.then<Socket>((Socket socket) => SecureSocket.secure(socket, host: url.host, context: context)),
      task.cancel,
    );
  }

  /// The address to connect to instead of [url]'s host, or null to leave this
  /// connection alone.
  ///
  /// Null in four cases, and the caller treats them alike because they mean the
  /// same thing: this override has no address to offer. A proxied connection is
  /// addressed to the proxy rather than to the panel, so pinning it would send
  /// the request to the wrong machine. A host that is not the configured panel
  /// is somebody else's traffic. And a [HostResolver] that answered null has
  /// already exhausted its ladder.
  ///
  /// The fourth is the resolver's own DoH request, and leaving it out is not a
  /// tidiness: the DoH rung opens a plain `HttpClient`, which this override
  /// intercepts like any other, so a user whose custom endpoint happens to sit
  /// on the panel's own host would have `resolve` re-enter itself once per
  /// level, forever, building a client each time. Narrow, because it needs the
  /// endpoint and the panel to share a host, and unbounded when it happens.
  Future<String?> _addressFor(Uri url, String? proxyHost) async {
    if (proxyHost != null) return null;

    final String? panel = panelHost();

    if (panel == null || url.host != panel) return null;
    if (url.host == resolver.setting.dohEndpoint?.host) return null;

    return resolver.resolve(url.host);
  }

  /// What `dart:io` does when no factory is installed
  /// (`dart-sdk/lib/_http/http_impl.dart:2694-2703`).
  ///
  /// TLS is started by the connect itself on a direct `https` connection. A
  /// proxied one gets a plain socket to the proxy either way, because the client
  /// tunnels through it with `CONNECT` after the socket is up.
  static Future<ConnectionTask<Socket>> _defaultConnect({
    required Uri url,
    required String? proxyHost,
    required int? proxyPort,
    required SecurityContext? context,
  }) {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);

    if (url.isScheme(_https)) return SecureSocket.startConnect(url.host, url.port, context: context);

    return Socket.startConnect(url.host, url.port);
  }

  /// The one scheme that has to be upgraded after the connect.
  static const String _https = 'https';
}
