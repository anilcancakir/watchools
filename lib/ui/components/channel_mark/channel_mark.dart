import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/channel.dart';
import 'channel_mark.recipe.dart';

/// The channel's identity in a box: its `tvg-logo` when the provider sent one,
/// its initials when it did not.
///
/// A real line-up answers "no logo" often enough that the fallback is the
/// common case rather than the exception, so it is a designed state and not a
/// grey square. Initials also survive what a logo does not: they are legible at
/// 32 pixels, they never load, and they never fail.
///
/// The fallback deliberately carries no per-channel tint. A hashed colour would
/// have to come from a scale value picked by hand, which this project's styling
/// rules do not allow, and a wall of randomly tinted tiles reads as noise next
/// to a status system where colour already means something.
@immutable
class ChannelMark extends StatelessWidget {
  /// The channel whose mark this is.
  final Channel channel;

  /// Recipe size axis: `sm`, `md`, `lg` or `xl`.
  final String size;

  /// Appended to the recipe output, for spacing and state at the call site.
  final String? className;

  /// Creates a [ChannelMark].
  const ChannelMark({
    super.key,
    required this.channel,
    this.size = 'md',
    this.className,
  });

  /// Words a provider bolts onto half a line-up. Dropping them is what makes
  /// the initials distinguish one channel from another: without this, every row
  /// of a Turkish line-up shows `TR`.
  ///
  /// `TV` is deliberately absent. It is a real part of a great many names
  /// (Show TV, Doğa TV, Diyanet TV) and treating it as noise turns "Show TV"
  /// into `SH`, which reads as a truncation rather than as a mark.
  static const Set<String> _noise = <String>{'TR', 'HD', 'FHD', 'UHD', '4K', 'SD', 'VIP'};

  /// Up to two initials for [name].
  ///
  /// Falls back to the noise words when a name is nothing else, because a
  /// provider that really sent a channel called `HD` is better served by an
  /// odd-looking mark than by an empty box that reads as a failed load.
  static String initialsOf(String name) {
    final List<String> words = name
        .split(RegExp(r'[\s:_|/-]+'))
        .map((String word) => word.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
        .where((String word) => word.isNotEmpty)
        .toList();

    final List<String> meaningful = words.where((String word) => !_noise.contains(_upper(word))).toList();
    final List<String> source = meaningful.isEmpty ? words : meaningful;

    if (source.isEmpty) return '?';
    if (source.length == 1) {
      final String word = source.first;

      return _upper(word.length == 1 ? word : word.substring(0, 2));
    }

    return _upper(source[0][0] + source[1][0]);
  }

  /// Turkish-aware uppercase.
  ///
  /// Dart's `toUpperCase` is locale-independent, so it maps `i` to `I` and a
  /// channel called "istanbul" gets the mark `IS` where Turkish orthography
  /// wants `İS`. The dotless pair already works (`ı` maps to `I`), so only the
  /// dotted `i` needs replacing, and it has to happen before the call rather
  /// than after: `I` is indistinguishable from a correctly-cased one afterwards.
  static String _upper(String value) => value.replaceAll('i', 'İ').toUpperCase();

  @override
  Widget build(BuildContext context) {
    final String base = channelMarkRecipe()(variants: <String, String?>{'size': size});
    final String? logoUrl = channel.logoUrl;

    return WDiv(
      className: className == null ? base : '$base $className',
      child: logoUrl == null
          ? WText(initialsOf(channel.name), className: 'font-bold text-fg-muted')
          : Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => WText(initialsOf(channel.name), className: 'font-bold text-fg-muted'),
            ),
    );
  }
}
