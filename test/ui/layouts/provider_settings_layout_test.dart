import 'dart:async';

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
  _FakeProvider({this.fault, this.fieldError, this.hasCredential = false, this.busy = false});

  @override
  ProviderFault? fault;

  @override
  bool busy;

  @override
  String? fieldError;

  @override
  bool hasCredential;

  int signOuts = 0;

  ({String baseUrl, String username, String password, String userAgent})? submitted;

  int submits = 0;

  /// When set, [submit] sets [busy] and hangs on this future, which is what a
  /// real handshake does. The only way to reach the one-frame window where the
  /// controller is busy and the button has not yet repainted into
  /// `isDisabled`.
  Completer<void>? gate;

  @override
  Future<void> submit({
    required String baseUrl,
    required String username,
    required String password,
    required String userAgent,
  }) async {
    submits++;
    submitted = (baseUrl: baseUrl, username: username, password: password, userAgent: userAgent);

    final Completer<void>? pending = gate;
    if (pending == null) return;

    busy = true;
    await pending.future;
    busy = false;
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

      await pumpScreen(
        tester,
        ProviderSettingsLayout(provider: _FakeProvider(hasCredential: true), onBack: () => backs++),
      );

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Geri'));
      await tester.pump();

      expect(backs, 1);
    });

    testWidgets('offers no way back when there is no credential, because there is nowhere to go', (
      WidgetTester tester,
    ) async {
      // `EnsureProvider`'s boot redirect is a `redirectTarget`, not a
      // `MagicRoute.to`, so nothing is recorded in `MagicRouter._history` and
      // `canPop()` is false. `back()` then falls through all three of its
      // branches (`magic_router.dart:578-603`) and does nothing at all,
      // silently, which is the state a user redirected here on launch would
      // have found the control in.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(find.text('Sağlayıcı ayarları'), findsOneWidget);
      expect(find.bySemanticsLabel('Geri'), findsNothing);
    });

    testWidgets('the back affordance is a disc, not a pill spanning the window', (WidgetTester tester) async {
      // `size-10` is 40 logical pixels on Wind's four pixel scale. The first
      // version of this screen shipped the disc stretched across the full
      // window width because a column stretches its children across the
      // cross axis by default. A size rather than text, so the square test
      // font does not make this meaningless the way it makes an overflow
      // assertion meaningless.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(hasCredential: true)));

      expect(tester.getSize(find.bySemanticsLabel('Geri')), const Size(40, 40));
    });

    testWidgets('renders at a mobile width as well as a desktop one', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(hasCredential: true)), size: mobile);

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

    testWidgets('a second Kaydet while the first handshake is out sends nothing and navigates nowhere', (
      WidgetTester tester,
    ) async {
      // The one-frame window `isDisabled` cannot cover: the button can only
      // refuse from the frame after `refreshUI` repaints, and inside that
      // frame the controller's own `submit` returns immediately having cleared
      // both verdicts, so the navigation would fire while the first handshake
      // is still out and take the user off the form.
      //
      // Two taps with no pump between them, which is what makes the window
      // reachable at all: a pump would repaint the button into its disabled
      // state and the second tap would never arrive.
      final _FakeProvider provider = _FakeProvider();
      provider.gate = Completer<void>();
      int saves = 0;

      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () => saves++));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'), warnIfMissed: false);
      await tester.tap(find.bySemanticsLabel('Kaydet'), warnIfMissed: false);

      expect(provider.submits, 1);
      expect(saves, 0, reason: 'nothing may navigate while the first handshake is still out');

      provider.gate!.complete();
      await tester.pump();
      await tester.pump();
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

    testWidgets('the revealed field keeps the same FocusNode instance across an unmount and remount', (
      WidgetTester tester,
    ) async {
      // What matters is node IDENTITY, not merely that something holds focus
      // afterwards: a rebuilt field gets a fresh node, and a fresh node that
      // happens to be focused would pass a weaker assertion while the defect
      // `search_focus_test.dart` guards against was still there.
      //
      // Across a CLOSE and REOPEN, not across typing, and the difference is
      // the whole test. The first version typed between the two reads and
      // could not fail: `WFormInput` builds a keyless `WInput`
      // (`w_form_input.dart:438-440`), `WInput` mints its node in `initState`
      // and keeps it in State (`w_input.dart:360-368`), and typing rebuilds
      // the same element, so the node is identical with or without
      // `focusNode:` being passed at all. Only an unmount destroys that State,
      // which is what the disclosure does and what the external node exists
      // for. Proved by deleting `focusNode: _userAgentFocusNode` from the
      // layout and watching this fail.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      final FocusNode before = tester.widget<EditableText>(editableTextOf('Kullanıcı aracı (User-Agent)')).focusNode;

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarları gizle'));
      await tester.pump();
      expect(find.bySemanticsLabel('Kullanıcı aracı (User-Agent)'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      final FocusNode after = tester.widget<EditableText>(editableTextOf('Kullanıcı aracı (User-Agent)')).focusNode;

      expect(identical(before, after), isTrue);
    });

    testWidgets('a user agent saved once and then hidden again is not sent', (WidgetTester tester) async {
      // `_userAgent` is only ever written by the field's `onSaved`, so without
      // a reset on the way closed the screen keeps sending a value it is no
      // longer showing and the default fallback never fires.
      //
      // The submit BEFORE the close is what makes this discriminate, and the
      // first version left it out: `onSaved` only runs from `Form.save()`
      // while the field is mounted, so typing and closing without saving
      // never writes `_userAgent` at all and the assertion held either way.
      final _FakeProvider provider = _FakeProvider();
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () {}));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Kullanıcı aracı (User-Agent)'), 'Custom/2.0');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();
      await tester.pump();
      expect(provider.submitted!.userAgent, 'Custom/2.0', reason: 'the typed value reaches the facade while shown');

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarları gizle'));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();
      await tester.pump();

      expect(provider.submitted!.userAgent, 'Watchools/1.0');
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

    testWidgets('cannot be tapped while a submit is in flight', (WidgetTester tester) async {
      // Without this, a sign-out during a handshake clears the credential and
      // the session, and then the submit resumes at its adopt and puts the
      // credential straight back: the sign-out silently undoes itself. The
      // submit control was already gated on `busy` and this one was not.
      final _FakeProvider provider = _FakeProvider(hasCredential: true, busy: true);
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider));

      await tester.tap(find.bySemanticsLabel('Çıkış yap'));
      await tester.pump();

      expect(provider.signOuts, 0);
    });
  });

  group('faults and field errors', () {
    testWidgets('the panel renders a ProviderNotice for the controller\'s fault', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(fault: ProviderFault.unreachable)));

      expect(find.byType(ProviderNotice), findsOneWidget);
    });

    testWidgets('expired is a sentence about the two fields, not the panel that offers a pointless retry', (
      WidgetTester tester,
    ) async {
      // `expired` is the only fault whose `ProviderNotice` action is
      // `onOpenSettings` (`provider_notice.dart:125`), and on this screen the
      // settings are what the user is already looking at: the panel would
      // offer "Bilgileri güncelle" over copy saying a retry will not help,
      // wired to a resubmit of the same rejected credential. It is also the
      // most likely fault here, since it is what a mistyped password returns.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(fault: ProviderFault.expired)));

      expect(find.byType(ProviderNotice), findsNothing);
      expect(find.textContaining('kabul etmedi'), findsOneWidget);
    });

    testWidgets('a field error renders, and nothing navigates on', (WidgetTester tester) async {
      // Neither this banner nor the guard below it was rendered by any test,
      // so deleting the guard and always navigating kept the suite green.
      final _FakeProvider provider = _FakeProvider(fieldError: 'Kimlik bilgisi yazılamadı.');
      int saves = 0;

      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () => saves++));

      expect(find.text('Kimlik bilgisi yazılamadı.'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();
      await tester.pump();

      expect(provider.submitted, isNotNull, reason: 'the submit still happens');
      expect(saves, 0, reason: 'a submit that left a field error must not navigate away from the form');
    });
  });

  group('the plaintext transport', () {
    testWidgets('says the connection is unencrypted and the password should not be reused', (
      WidgetTester tester,
    ) async {
      // Xtream puts the credential in the query string and then in the stream
      // URL's path, so there is nothing to encrypt around: the sentence is the
      // whole of what a client that cannot fix the transport can honestly do.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      expect(find.textContaining('şifrelenmez'), findsOneWidget);
      expect(find.textContaining('Başka bir yerde kullandığınız'), findsOneWidget);
    });
  });
}
