import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/title_item.dart';
import 'guide_fixture.dart';
import 'scale_fixture.dart';
import 'vod_fixture.dart';

/// How large a provider the fixtures should pretend to be.
///
/// Read from `?scale=N` on the route, so a measurement run is
/// `dusk:navigate --route "/?scale=5000"` followed by a hot restart, which is
/// the sequence the end-to-end walks already perform between cases. Nothing
/// else in the app writes it.
///
/// A query parameter rather than a `--dart-define`, and that is not the first
/// choice. `artisan`'s `fsa start` assembles a fixed argv for `flutter run`
/// (`start_command.dart:385` and `:583`) with no passthrough, so a define
/// cannot reach the app through the tooling that also gives dusk its session
/// state. Nor an `.env` key: `.env` is a real asset during `flutter test`, so a
/// scale left set there would silently generate five thousand channels under
/// every widget test. The URL is the one channel that reaches a running app,
/// survives a hot restart, and cannot leak into another gate.
///
/// Read off [Uri.base] rather than through `MagicRouter.queryParameter`, and
/// that is measured rather than stylistic. Under the hash strategy the browser
/// sat on `http://localhost:3210/#/?scale=5000` while the router reported its
/// location as `/`, so the query never reached a caller asking the router for
/// it. [Uri.base] carries the whole URL, fragment included, needs no router to
/// be built yet, and works on the first frame as well as after a restart.
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
/// A release build reads zero whatever the URL says.
abstract final class FixtureScale {
  /// Resolved once, so two controllers built at different moments cannot
  /// disagree about how large the provider is.
  static int? _resolved;

  /// The requested channel count, or zero for the hand-written fixtures.
  static int get channels {
    final int? cached = _resolved;
    if (cached != null) return cached;

    if (kReleaseMode) return _resolved = 0;

    final Uri base = Uri.base;
    // Query first, then the fragment: `/?scale=N` is what a path strategy
    // gives and `/#/?scale=N` is what the hash strategy gives, and the app is
    // served under the second.
    final String? raw = base.queryParameters['scale'] ?? Uri.parse(base.fragment).queryParameters['scale'];
    final int parsed = raw == null ? 0 : (int.tryParse(raw) ?? 0);

    // Clamped rather than trusted. `?scale=99999999` is a typo away from
    // `?scale=9999999`, and the difference is a tab that never paints against
    // one that paints slowly, which is the measurement.
    return _resolved = parsed.clamp(0, 50000);
  }

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
