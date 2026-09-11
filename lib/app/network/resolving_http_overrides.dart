/// The process-wide hook that makes a chosen resolver apply to real requests.
///
/// Conditionally exported because everything the implementation needs
/// (`HttpOverrides`, `HttpClient`, `SecureSocket`, `ConnectionTask`) is
/// `dart:io`, while the only caller, `AppServiceProvider.register()`, is on the
/// web build path. The same seam `host_lookup_io.dart` sits behind, and the
/// shape magic itself uses at `magic/lib/src/storage/magic_file_extensions.dart:26`.
///
/// `flutter build web` is the only gate on this: CI never builds web and
/// `flutter analyze` does not see a platform-library violation.
library;

export 'resolving_http_overrides_io.dart' if (dart.library.js_interop) 'resolving_http_overrides_web.dart';
