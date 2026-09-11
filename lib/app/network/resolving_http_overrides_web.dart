import 'host_resolver.dart';

/// Installs nothing, because a browser owns DNS.
///
/// No JavaScript API exposes name resolution and `fetch` resolves a host inside
/// the network stack, so there is no socket to point anywhere and no
/// `HttpOverrides` to install: the whole class is `dart:io`. The web rungs of
/// [HostResolver] already refuse for the same reason
/// (`host_lookup_web.dart`), so this half is consistent with them rather than a
/// second, quieter failure.
///
/// The arguments are accepted and dropped so that `app_service_provider.dart`,
/// which is on the web build path, can call one function on every target.
void installResolvingHttpOverrides({required HostResolver resolver, required String? Function() panelHost}) {}
