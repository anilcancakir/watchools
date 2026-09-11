import 'host_resolver.dart';

/// Why both rungs on this target refuse.
///
/// A browser owns DNS entirely: no JavaScript API exposes name resolution, and
/// `fetch` resolves a host inside the network stack where nothing reaches it.
/// The rung that could technically work, a DoH query over `fetch`, has nothing
/// to hand its answer to either: this feature exists to give an address to
/// libmpv, and no libmpv target is a browser.
///
/// So the rungs throw rather than pretend, [HostResolver.resolve] answers null,
/// and that null is the honest statement that this app cannot pick a resolver
/// in a browser.
const String _noResolverOnWeb = 'a browser owns DNS; no web API exposes name resolution';

/// The system rung on the web target, which cannot exist. See
/// [_noResolverOnWeb].
///
/// This file is not optional scaffolding. The app scaffolds a web target and
/// `host_resolver.dart` compiles the platform rungs in unconditionally, so
/// without this half of the conditional export the platform library reachable
/// from the other one would break `flutter build web`, which CI does not run
/// and would therefore not catch.
class SystemHostLookup implements HostLookup {
  const SystemHostLookup();

  @override
  Future<HostAnswer> lookup(String host) async => throw const HostLookupException(_noResolverOnWeb);
}

/// The DoH rung on the web target, which has nothing to serve. See
/// [_noResolverOnWeb].
class DohHostLookup implements HostLookup {
  /// The endpoint, kept so the constructor matches the one `HostResolver` calls
  /// on every target.
  final Uri endpoint;

  const DohHostLookup(this.endpoint);

  @override
  Future<HostAnswer> lookup(String host) async => throw const HostLookupException(_noResolverOnWeb);
}
