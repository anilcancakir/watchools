import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/title_item.dart';
import 'guide_fixture.dart';
import 'scale_fixture.dart';
import 'vod_fixture.dart';

/// How large a provider the fixtures should pretend to be.
///
/// Set at compile time:
///
/// ```
/// ./bin/fsa start --flutter-arg=--dart-define=WATCHOOLS_SCALE=5000
/// ```
///
/// `tool/dusk/perf.sh` passes it; nothing else in the app writes it, and no
/// other value in the app reads it.
///
/// A define rather than the `?scale=N` query parameter this used to read off
/// [Uri.base], and the swap is worth the churn for one reason: a query
/// parameter only exists on web. `Uri.base` on macOS, Android or iOS is a file
/// URI with no query at all, so the scale switch silently did nothing on every
/// target except the browser, and a run on a real device would have measured 23
/// channels and reported it as fast. A define reaches every platform.
///
/// It could not be a define until now. `artisan`'s `fsa start` assembled a
/// fixed argv for `flutter run` with no passthrough, so nothing could reach the
/// app through the tooling that also gives dusk its session state. That gap is
/// `fluttersdk/artisan#53`, and `--flutter-arg` is what closed it.
///
/// Not an `.env` key either: `.env` is a real asset during `flutter test`, so a
/// scale left set there would silently generate five thousand channels under
/// every widget test.
///
/// Gated on [kReleaseMode] rather than on `kDebugMode`, and the difference is
/// the whole point of the harness. A debug build carries assertions, no
/// inlining and, once a perf session opens, timeline instrumentation that
/// `dusk:perf_end` itself warns "costs time that is significant relative to the
/// work it measures". Numbers from it rank causes; they do not describe a
/// device. A profile build is the only one worth quoting, and `kDebugMode` is
/// false there, so gating on it would have silently handed a profile run the 23
/// channel fixture and reported it as fast.
///
/// A release build reads zero whatever the define says.
abstract final class FixtureScale {
  /// The raw define, before the release gate and the clamp.
  ///
  /// `const` so a release build tree-shakes the generator out entirely rather
  /// than carrying a few thousand lines of fixture nobody can reach.
  static const int _requested = int.fromEnvironment('WATCHOOLS_SCALE');

  /// The requested channel count, or zero for the hand-written fixtures.
  ///
  /// Clamped rather than trusted. `WATCHOOLS_SCALE=99999999` is a typo away
  /// from `9999999`, and the difference is a run that never paints against one
  /// that paints slowly, which is the measurement.
  static int get channels => kReleaseMode ? 0 : _requested.clamp(0, 50000);

  /// Whether the generated fixtures are in use at all.
  static bool get active => channels > 0;

  /// Provider `group-title` values. One per twenty five channels, which is the
  /// ratio a real playlist lands near, capped so the strip stays a strip.
  static int get groups => (channels ~/ 25).clamp(1, 400);

  /// A catalogue is smaller than a line-up on every provider I have seen.
  static int get titles => channels ~/ 2;

  /// Catalogue categories, on the same ratio as [groups].
  static int get categories => (titles ~/ 25).clamp(1, 400);

  /// The line-up to render.
  static List<Channel> get channelList =>
      active ? ScaleFixture.channels(channels, groups) : List<Channel>.of(guideFixture);

  /// The group tabs to render.
  static List<String> get groupList => active ? ScaleFixture.groups(groups) : guideGroups;

  /// The catalogue to render.
  static List<TitleItem> get titleList =>
      active ? ScaleFixture.titles(titles, categories) : List<TitleItem>.of(vodFixture);

  /// The category tabs to render.
  static List<String> get categoryList => active ? ScaleFixture.categories(categories) : vodCategories;
}
