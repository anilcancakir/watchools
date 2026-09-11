import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:magic_devtools/preview.dart';
import 'package:watchools/_previews.g.dart';

import '../support/screen.dart';

/// Does every preview in the catalogue still render?
///
/// A preview is a static variant matrix a person reads, so there is nothing in
/// one to assert about behaviour. There is one thing worth gating, and it is the
/// reason this file exists rather than the previews being excluded from the
/// coverage denominator: a preview composes real components in arrangements no
/// screen uses, so it is where a layout fault surfaces first.
///
/// It caught one on the way in. `ProviderNoticePreview` put its three panels in
/// a row with `items-stretch`, which hands each panel the row's unbounded
/// cross-axis extent, and the `h-full` inside the notice then had no height to
/// be a fraction of: `RenderBox was not laid out: _RenderFullHeight`, and the
/// whole page painted white. Ten passing widget tests said nothing, and it took
/// a screenshot in a browser to see it.
///
/// `pumpScreen` is what does the work here. It collects through
/// `FlutterError.onError` and fails on anything that is not an overflow, and
/// overflow is exactly what a preview is allowed to do: it packs a variant
/// matrix into one screen under a test font whose every glyph is a square of the
/// font size.
void main() {
  setUp(WindParser.clearCache);

  /// Every entry `previews:refresh` generated, which is the same list the
  /// `/preview` catalogue renders. Reading it from the generated index rather
  /// than naming the previews here is what makes a tenth component covered the
  /// moment it is created.
  final List<PreviewEntry> entries = previewEntries();

  test('the generated catalogue is not empty', () {
    // Without this the loop below passes by iterating nothing, which is how the
    // catalogue came to be unregistered and unnoticed in the first place.
    expect(entries, isNotEmpty);
  });

  for (final PreviewEntry entry in entries) {
    testWidgets('${entry.label} renders at desktop', (WidgetTester tester) async {
      await pumpScreen(tester, Builder(builder: entry.builder));
    });

    testWidgets('${entry.label} renders on a phone', (WidgetTester tester) async {
      // The width four separate layout bugs were found at, and a preview is
      // laid out in one column there rather than the row it was drawn as.
      await pumpScreen(tester, Builder(builder: entry.builder), size: mobile);
    });
  }
}
