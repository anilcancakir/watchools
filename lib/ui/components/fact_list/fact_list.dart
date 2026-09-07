import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// One labelled fact.
@immutable
class FactEntry {
  /// The label, rendered in small caps. Written in normal case at the call site
  /// and uppercased here, so the Turkish dotted `i` is handled in one place.
  final String label;

  /// The value.
  final String value;

  /// Set when the value is a control rather than a fact.
  ///
  /// Plex renders `Video 720p (H.264)` and `Altyazılar Hiçbiri ⌄` as the same
  /// row: two read-only facts and a picker, one shape. That is the observation
  /// worth copying, because a subtitle track is a fact right up until you want
  /// to change it, and giving it a different shape means hunting for it.
  final VoidCallback? onTap;

  /// Creates a [FactEntry].
  const FactEntry({required this.label, required this.value, this.onTap});
}

/// The label-value stack that carries technical truth.
///
/// The single most transplantable thing in the references, and the one this
/// product needs most. Plex puts codec, audio layout and subtitle track on the
/// page as plain labelled rows; our audience is the one that opens a detail
/// page specifically to find out whether a stream is really 1080p and whether
/// the audio track it ships is the one they can hear.
///
/// The label column is a fixed width rather than a shrink-wrap, because the
/// values are what the eye scans down and a ragged left edge on the values
/// defeats that.
@immutable
class FactList extends StatelessWidget {
  /// The rows, in the order they should be read.
  final List<FactEntry> entries;

  /// Appended to the outer column, for spacing at the call site.
  final String? className;

  /// Creates a [FactList].
  const FactList({super.key, required this.entries, this.className});

  @override
  Widget build(BuildContext context) {
    const String base = 'flex flex-col gap-2 w-full';

    return WDiv(className: className == null ? base : '$base $className', children: entries.map(_row).toList());
  }

  Widget _row(FactEntry entry) {
    final Widget value = entry.onTap == null
        ? WText(entry.value, className: 'text-sm text-fg line-clamp-2')
        : WAnchor(
            onTap: entry.onTap,
            semanticLabel: '${entry.label}: ${entry.value}',
            child: WDiv(
              className: 'flex flex-row items-center gap-1',
              children: <Widget>[
                WText(entry.value, className: 'text-sm font-medium text-primary'),
                const WIcon(Icons.expand_more, className: 'text-sm text-primary'),
              ],
            ),
          );

    return WDiv(
      className: 'flex flex-row items-start gap-4 w-full',
      children: <Widget>[
        WDiv(
          className: 'shrink-0 w-[104px]',
          child: WText(
            _upper(entry.label),
            className: 'text-xs font-semibold tracking-wide text-fg-muted line-clamp-1',
          ),
        ),
        WDiv(className: 'flex-1', child: value),
      ],
    );
  }

  /// Turkish-aware uppercase, for the same reason the channel mark carries one:
  /// Dart's `toUpperCase` is locale-independent and maps `i` to `I`, so a label
  /// written `Bilgi` comes out `BILGI` where Turkish orthography wants `BİLGİ`.
  static String _upper(String value) => value.replaceAll('i', 'İ').toUpperCase();
}
