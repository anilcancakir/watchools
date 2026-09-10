import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/provider_setup_controller.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/ui/components/provider_notice/provider_notice.dart';
import 'package:watchools/ui/layouts/provider_settings_layout.dart';

import '../../support/screen.dart';

/// A stand-in for `ProviderSetupController`, so the layout is tested against
/// the contract it reads rather than against a container, a vault and a
/// panel.
///
/// Records what [submit] was called with, because the assertion that matters
/// most on this screen is that the four typed values crossed the boundary
/// intact, not that some request happened.
class _FakeProvider implements ProviderSetupFacade {
  _FakeProvider({this.fault, this.hasCredential = false});

  @override
  ProviderFault? fault;

  @override
  bool busy = false;

  @override
  String? fieldError;

  @override
  bool hasCredential;

  int signOuts = 0;

  ({String baseUrl, String username, String password, String userAgent})? submitted;

  @override
  Future<void> submit({
    required String baseUrl,
    required String username,
    required String password,
    required String userAgent,
  }) async {
    submitted = (baseUrl: baseUrl, username: username, password: password, userAgent: userAgent);
  }

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  setUp(WindParser.clearCache);

  /// The field's own `EditableText`, found by descending from its Semantics
  /// label rather than by `find.byType(EditableText)` alone, because this
  /// screen carries more than one text field.
  Finder editableTextOf(String label) {
    return find.descendant(of: find.bySemanticsLabel(label), matching: find.byType(EditableText));
  }

  group('the heading and the way out', () {
    testWidgets('names the screen and offers a way back', (WidgetTester tester) async {
      int backs = 0;

      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(), onBack: () => backs++));

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Geri'));
      await tester.pump();

      expect(backs, 1);
    });

    testWidgets('the back affordance is a disc, not a pill spanning the window', (WidgetTester tester) async {
      // `size-10` is 40 logical pixels on Wind's four pixel scale. The first
      // version of this screen shipped the disc stretched across the full
      // window width because a column stretches its children across the
      // cross axis by default. A size rather than text, so the square test
      // font does not make this meaningless the way it makes an overflow
      // assertion meaningless.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(tester.getSize(find.bySemanticsLabel('Geri')), const Size(40, 40));
    });

    testWidgets('renders at a mobile width as well as a desktop one', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()), size: mobile);

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsOneWidget);
    });
  });

  group('the three visible fields', () {
    testWidgets('are exactly three, before the disclosure ever opens', (WidgetTester tester) async {
      // Inverted from the placeholder's own guard, which asserted zero:
      // onboarding was an undesigned surface then and a text field here would
      // have shipped one by accident. It is a designed surface now, with
      // exactly three fields visible until the disclosure opens a fourth.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(find.byType(WInput), findsNWidgets(3));
    });

    testWidgets('carry autocorrect and enableSuggestions both off, and the password field is obscured', (
      WidgetTester tester,
    ) async {
      // Both default to `true` (`w_form_input.dart:108-109`), and the IME
      // would otherwise learn the user name, half of `CatalogueStore.
      // accountKey`. Read off the real `WInput` each field renders, which is
      // the widget these props actually reach.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      for (final String label in <String>['Panel adresi', 'Kullanıcı adı', 'Şifre']) {
        final WInput input = tester.widget<WInput>(
          find.descendant(of: find.bySemanticsLabel(label), matching: find.byType(WInput)),
        );

        expect(input.autocorrect, isFalse, reason: '$label must not autocorrect');
        expect(input.enableSuggestions, isFalse, reason: '$label must not offer suggestions');
      }

      final WInput password = tester.widget<WInput>(
        find.descendant(of: find.bySemanticsLabel('Şifre'), matching: find.byType(WInput)),
      );

      // `type: InputType.password` is the only route to `obscureText`
      // (`w_input.dart:744`), which is what keeps the password out of the
      // semantics tree.
      expect(password.type, InputType.password);
    });

    testWidgets('entering three values and submitting reaches the facade intact', (WidgetTester tester) async {
      final _FakeProvider provider = _FakeProvider();
      int saves = 0;

      // `onSaved` supplied rather than left to its `MagicRoute.to('/')`
      // default: `MagicRouter` is never built under `pumpScreen`, the same
      // reason `PlaybackLayout`'s tests always supply `onBack`.
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () => saves++));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();
      await tester.pump();

      expect(provider.submitted, isNotNull);
      expect(saves, 1, reason: 'a successful submit navigates on');
      expect(provider.submitted!.baseUrl, 'http://panel.example.com');
      expect(provider.submitted!.username, 'anilcan');
      expect(provider.submitted!.password, 'topsecret');

      // Never opened the disclosure, so the screen supplies the default
      // itself rather than the controller inventing one.
      expect(provider.submitted!.userAgent, 'Watchools/1.0');
    });

    testWidgets('an empty user name blocks submit, shows a message, and never reaches the facade', (
      WidgetTester tester,
    ) async {
      final _FakeProvider provider = _FakeProvider();
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();

      expect(find.text('Kullanıcı adı gerekli.'), findsOneWidget);
      expect(provider.submitted, isNull);
    });
  });

  group('the advanced disclosure', () {
    testWidgets('the user agent field is absent until the disclosure is opened', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(find.bySemanticsLabel('Kullanıcı aracı (User-Agent)'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      expect(find.bySemanticsLabel('Kullanıcı aracı (User-Agent)'), findsOneWidget);
      expect(find.byType(WInput), findsNWidgets(4));
    });

    testWidgets('the revealed field keeps the same FocusNode instance across a rebuild from typing', (
      WidgetTester tester,
    ) async {
      // What matters is node IDENTITY, not merely that something holds focus
      // afterwards: a rebuilt field gets a fresh node, and a fresh node that
      // happens to be focused would pass a weaker assertion while the defect
      // `search_focus_test.dart` guards against was still there.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      final FocusNode before = tester.widget<EditableText>(editableTextOf('Kullanıcı aracı (User-Agent)')).focusNode;

      await tester.enterText(find.bySemanticsLabel('Kullanıcı aracı (User-Agent)'), 'Custom/2.0');
      await tester.pump();

      final FocusNode after = tester.widget<EditableText>(editableTextOf('Kullanıcı aracı (User-Agent)')).focusNode;

      expect(identical(before, after), isTrue);
    });
  });

  group('sign-out', () {
    testWidgets('is absent when there is no credential to sign out of', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(find.bySemanticsLabel('Çıkış yap'), findsNothing);
    });

    testWidgets('is present and reaches the facade when a credential exists', (WidgetTester tester) async {
      final _FakeProvider provider = _FakeProvider(hasCredential: true);
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider));

      expect(find.bySemanticsLabel('Çıkış yap'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Çıkış yap'));
      await tester.pump();

      expect(provider.signOuts, 1);
    });
  });

  group('faults', () {
    testWidgets('the panel renders a ProviderNotice for the controller\'s fault', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(fault: ProviderFault.unreachable)));

      expect(find.byType(ProviderNotice), findsOneWidget);
    });
  });
}
