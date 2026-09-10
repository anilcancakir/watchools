import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/ui/layouts/provider_settings_layout.dart';

import '../../support/screen.dart';

void main() {
  setUp(WindParser.clearCache);

  group('the placeholder', () {
    testWidgets('names what is happening rather than showing an empty screen', (WidgetTester tester) async {
      await pumpScreen(tester, const ProviderSettingsLayout());

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);

      // The copy has to say the screen is not ready. A heading alone reads as a
      // screen that failed to load, which is the reading this exists to avoid:
      // the user arrived here from a fault panel and is already being told
      // something is wrong.
      expect(
        find.byWidgetPredicate((Widget widget) => widget is WText && (widget.data.contains('henüz hazır değil'))),
        findsOneWidget,
      );
    });

    testWidgets('offers a way out, which is the whole point of it existing', (WidgetTester tester) async {
      int backs = 0;

      await pumpScreen(tester, ProviderSettingsLayout(onBack: () => backs++));

      // The only affordance on the screen. Without it this route is a dead end
      // reached from a fault panel, which is worse than the fall-through to `/`
      // it replaces.
      await tester.tap(find.bySemanticsLabel('Geri'));
      await tester.pump();

      expect(backs, 1);
    });

    testWidgets('writes no credential, because there is nothing to write it with', (WidgetTester tester) async {
      await pumpScreen(tester, const ProviderSettingsLayout());

      // Asserted rather than assumed. Onboarding is an undesigned surface, and
      // a text field here would be it shipped by accident on the one flow
      // where a mistake costs the user their subscription details. This fails
      // the moment somebody adds an input without designing the screen.
      expect(find.byType(WInput), findsNothing);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('the back affordance is a disc, not a pill spanning the window', (WidgetTester tester) async {
      await pumpScreen(tester, const ProviderSettingsLayout());

      // `size-10` is 40 logical pixels on Wind's four pixel scale. Asserted
      // because the first version of this screen shipped the disc stretched
      // across the full window width with the arrow centred in it: a column
      // stretches its children across the cross axis, and every other
      // assertion in this file passes at either width. Found by looking at the
      // running app, which is the only thing that could see it.
      //
      // A size rather than text, so the square test font does not make this
      // meaningless the way it makes an overflow assertion meaningless.
      expect(tester.getSize(find.bySemanticsLabel('Geri')), const Size(40, 40));
    });

    testWidgets('renders at a mobile width as well as a desktop one', (WidgetTester tester) async {
      await pumpScreen(tester, const ProviderSettingsLayout(), size: mobile);

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsOneWidget);
    });
  });
}
