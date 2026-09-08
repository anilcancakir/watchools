import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/ui/components/provider_notice/index.dart';

import '../../support/wind_test_app.dart';

/// Can a viewer tell the three provider faults apart, and does each one end in
/// the action that can actually fix it?
///
/// That is the whole reason [ProviderFault] is three values rather than one
/// error string. A provider refusing because it is busy and a provider refusing
/// because the subscription lapsed look identical over HTTP and are opposite
/// from where the user sits: one wants a minute, the other wants a new
/// password. Collapsing them into "bir şeyler ters gitti" is what makes people
/// re-type a working credential.
///
/// The exhaustiveness case is the one that keeps this true over time. It reads
/// `ProviderFault.values`, so a fourth fault added without copy or without an
/// action fails here rather than shipping as a blank panel.
void main() {
  setUp(WindParser.clearCache);

  /// Pumps the notice for [fault] and reports which callback fired.
  Future<({List<String> retries, List<String> settings})> pump(
    WidgetTester tester,
    ProviderFault fault, {
    String? detail,
  }) async {
    final List<String> retries = <String>[];
    final List<String> settings = <String>[];

    await tester.pumpWidget(
      wrapWithTheme(
        ProviderNotice(
          fault: fault,
          detail: detail,
          onRetry: () => retries.add(fault.name),
          onOpenSettings: () => settings.add(fault.name),
        ),
        brightness: Brightness.dark,
      ),
    );

    return (retries: retries, settings: settings);
  }

  /// The one anchor that carries the tap.
  ///
  /// There are two. A `WDiv` whose className contains `hover:` or `focus:`
  /// wraps itself in a `WAnchor` to track those states, so the action button is
  /// an explicit anchor around a styled div that grew its own. Only the outer
  /// one has an `onTap`, and that is the one a user presses.
  Finder action() {
    return find.byWidgetPredicate((Widget w) => w is WAnchor && w.onTap != null);
  }

  /// Every string the notice put on screen.
  List<String> texts(WidgetTester tester) {
    return tester.widgetList<WText>(find.byType(WText)).map((WText w) => w.data).toList();
  }

  testWidgets('every fault says something different, and says it in three parts', (tester) async {
    final Set<String> titles = <String>{};

    for (final ProviderFault fault in ProviderFault.values) {
      await pump(tester, fault);

      final List<String> lines = texts(tester);

      // A title, an explanation and an action label. Two lines would mean one
      // of them is missing, and the missing one is always the explanation.
      expect(lines.length, greaterThanOrEqualTo(3), reason: '${fault.name} is missing a part');
      expect(lines.first.trim(), isNotEmpty, reason: '${fault.name} has no title');
      titles.add(lines.first);
    }

    expect(titles.length, ProviderFault.values.length, reason: 'two faults share a title');
  });

  testWidgets('a lapsed subscription sends the user to their credentials, not to a retry', (tester) async {
    // The load-bearing distinction. Retrying an expired credential fails the
    // same way every time, so offering a retry here teaches the user that the
    // app is broken rather than that their subscription is.
    final ({List<String> retries, List<String> settings}) fired = await pump(tester, ProviderFault.expired);

    await tester.tap(action());
    await tester.pump();

    expect(fired.settings, <String>['expired']);
    expect(fired.retries, isEmpty);
  });

  testWidgets('a host that did not answer offers a retry', (tester) async {
    final ({List<String> retries, List<String> settings}) fired = await pump(tester, ProviderFault.unreachable);

    await tester.tap(action());
    await tester.pump();

    expect(fired.retries, <String>['unreachable']);
    expect(fired.settings, isEmpty);
  });

  testWidgets('so does a provider that is refusing for now', (tester) async {
    // Throttling is transient by definition, so the action is the same as an
    // unreachable host even though the copy is not.
    final ({List<String> retries, List<String> settings}) fired = await pump(tester, ProviderFault.throttled);

    await tester.tap(action());
    await tester.pump();

    expect(fired.retries, <String>['throttled']);
    expect(fired.settings, isEmpty);
  });

  testWidgets('the technical line shows exactly what the provider said', (tester) async {
    // Doctrine rule 7. The user cannot act on `HTTP 502` but the person they
    // ask for help can, and a panel that hides it makes that conversation start
    // with "it says something went wrong".
    await pump(tester, ProviderFault.unreachable, detail: 'HTTP 502, tr.example-provider.com');

    expect(texts(tester), contains('HTTP 502, tr.example-provider.com'));
  });

  testWidgets('and is absent rather than empty when the provider said nothing', (tester) async {
    await pump(tester, ProviderFault.unreachable);

    expect(
      texts(tester).where((String line) => line.trim().isEmpty),
      isEmpty,
      reason: 'an empty detail line still occupies its slot and reads as a render fault',
    );
  });
}
