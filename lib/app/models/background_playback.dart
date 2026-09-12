/// What a playing stream does when the app leaves the foreground.
///
/// Backgrounding a Flutter app does not dispose a [State]: the libmpv core,
/// the account's single connection slot and the wakelock all survive the
/// user pressing Home unless something acts on the lifecycle event. This
/// enum is the user's choice of what that something does, read by an
/// app-lifecycle observer that is not part of this step.
///
/// Lives in `lib/app/models/` rather than `lib/app/playback/`, the way
/// `ProviderFault` does: `ProviderSetupController` must not import the
/// playback layer (`app_service_provider.dart:114-115`), and this enum is
/// read by the setup facade as well as the engine, so its home has to be one
/// neither depends on the other through.
enum BackgroundPlayback {
  /// Tear the core down: stop the stream, release the account's connection
  /// slot, drop the wakelock. The default, and the first member, because it
  /// is what every existing install already does in effect (nothing keeps
  /// the connection alive on purpose today) and it costs the provider's
  /// single connection slot the least.
  stop,

  /// Keep the stream open and audible with the video surface torn down.
  audio,

  /// Hand the video surface to the platform's picture-in-picture window.
  pictureInPicture;

  /// Parses [stored], the raw value out of `XtreamCredentials.backgroundPlayback`.
  ///
  /// Returns [stop] for null and for a name that is none of `stop`, `audio`
  /// or `pictureInPicture`. Both are the same outcome on purpose, mirroring
  /// `ResolverSetting.parse` (`lib/app/network/resolver_setting.dart:52-75`):
  /// a value this cannot make sense of means "tear the core down", the
  /// behaviour a user who never touches this feature already has, never a
  /// thrown exception over a setting nobody is forced to touch. A value
  /// written by a newer build must not make an older one fail to boot.
  static BackgroundPlayback parse(String? stored) {
    switch (stored) {
      case 'audio':
        return audio;
      case 'pictureInPicture':
        return pictureInPicture;
      default:
        return stop;
    }
  }

  /// The string `XtreamCredentials.backgroundPlayback` should carry, or null
  /// for [stop] so a user who never touches this feature keeps writing the
  /// same credential blob every existing install already writes.
  ///
  /// Mirrors `ResolverSetting.storedValue`
  /// (`lib/app/network/resolver_setting.dart:76-90`), the shape that makes
  /// the `'key': ?value` omission in `XtreamCredentials._toJson()` reachable
  /// at all.
  String? get storedValue => this == stop ? null : name;
}
