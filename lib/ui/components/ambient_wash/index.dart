// AmbientWash component folder-local barrel.
//
// Re-exports the public surface. The preview is intentionally NOT re-exported:
// `previews:refresh` discovers `*.preview.dart` files directly and the preview
// must stay out of the release barrel.

export 'ambient_wash.dart';
