import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:watchools/app/controllers/provider_setup_controller.dart';
import 'package:watchools/app/models/provider_fault.dart';
import 'package:watchools/app/network/resolver_setting.dart';
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
  _FakeProvider({
    this.fault,
    this.fieldError,
    this.hasCredential = false,
    this.busy = false,
    this.resolver = ResolverSetting.system,
    this.resolvedAddress,
  });

  @override
  ProviderFault? fault;

  @override
  bool busy;

  @override
  String? fieldError;

  @override
  bool hasCredential;

  @override
  ResolverSetting resolver;

  @override
  String? resolvedAddress;

  int signOuts = 0;

  ({String baseUrl, String username, String password, String userAgent, String? resolver})? submitted;

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
    String? resolver,
  }) async {
    submits++;
    submitted = (baseUrl: baseUrl, username: username, password: password, userAgent: userAgent, resolver: resolver);

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

  group('the resolver picker', () {
    /// Opens the picker and taps [optionLabel], the shape every test below
    /// shares: `WSelect` defers its overlay to the frame after the opening
    /// tap (`w_select.dart:361-369`), so a single `pump()` is not enough.
    Future<void> pickResolver(WidgetTester tester, String optionLabel) async {
      await tester.tap(find.bySemanticsLabel('DNS çözümleyici seçin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(optionLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('the custom resolver field is absent until the custom entry is picked', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      expect(find.bySemanticsLabel('Özel sunucu adresi'), findsNothing);

      await pickResolver(tester, 'Özel sunucu');

      expect(find.bySemanticsLabel('Özel sunucu adresi'), findsOneWidget);
    });

    testWidgets('a bare hostname typed into the custom field is refused, and nothing is submitted', (
      WidgetTester tester,
    ) async {
      // A hostname would have to be resolved by the resolver it is replacing,
      // which bootstraps the ladder on itself.
      final _FakeProvider provider = _FakeProvider();
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      await pickResolver(tester, 'Özel sunucu');

      await tester.enterText(find.bySemanticsLabel('Özel sunucu adresi'), 'dns.example.com');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();

      expect(find.text('Sunucu adı değil, IP adresi veya https adresi girin.'), findsOneWidget);
      expect(provider.submitted, isNull);
    });

    testWidgets('a custom address typed and then hidden again still reaches the facade', (WidgetTester tester) async {
      // The field unmounts with the disclosure, and `Form.save()` runs `onSaved`
      // only on a mounted field, so a value written at save time would be gone
      // by the time this submits. Found in the running app: typed, hidden,
      // submitted, and silently downgraded to the system resolver.
      final _FakeProvider provider = _FakeProvider();

      // `onSaved` supplied for the reason the three-field happy path records:
      // this submit succeeds, and the default would navigate through
      // `MagicRoute.to`, which `pumpScreen` never builds a router for.
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () {}));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      await pickResolver(tester, 'Özel sunucu');

      await tester.enterText(find.bySemanticsLabel('Özel sunucu adresi'), '9.9.9.9');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarları gizle'));
      await tester.pump();

      expect(find.bySemanticsLabel('Özel sunucu adresi'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();

      expect(provider.submitted?.resolver, '9.9.9.9');
    });

    testWidgets('an unusable custom address is refused even with the disclosure closed', (WidgetTester tester) async {
      // The validator cannot see an unmounted field, so `_submit` carries the
      // same refusal. Without it `parse` falls back to the system resolver and
      // the user is handed a setting they did not choose, with no reason why.
      final _FakeProvider provider = _FakeProvider();
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      await pickResolver(tester, 'Özel sunucu');

      await tester.enterText(find.bySemanticsLabel('Özel sunucu adresi'), 'dns.example.com');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarları gizle'));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();

      expect(find.text('Sunucu adı değil, IP adresi veya https adresi girin.'), findsOneWidget);
      expect(provider.submitted, isNull);
    });

    testWidgets('a resolver stored non-system reaches the facade even when the disclosure is never opened', (
      WidgetTester tester,
    ) async {
      // The trap this test exists to catch: `_baseUrl`, `_username` and
      // `_password` all start empty and the disclosure clears its own field
      // on close, but a resolver's default IS the system resolver, so an
      // unseeded picker would silently drop a working setting the moment a
      // user reopens this screen to fix something else. Proved to
      // discriminate at `.ac/plans/dns-connection-download/evidence/
      // 06-resolver-picker.txt` by removing the seeding in `initState` and
      // watching this go red with `resolver` arriving as null.
      final _FakeProvider provider = _FakeProvider(resolver: ResolverSetting.cloudflare);
      await pumpScreen(tester, ProviderSettingsLayout(provider: provider, onSaved: () {}));

      await tester.enterText(find.bySemanticsLabel('Panel adresi'), 'http://panel.example.com');
      await tester.enterText(find.bySemanticsLabel('Kullanıcı adı'), 'anilcan');
      await tester.enterText(find.bySemanticsLabel('Şifre'), 'topsecret');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Kaydet'));
      await tester.pump();
      await tester.pump();

      expect(provider.submitted!.resolver, 'cloudflare');
    });
  });

  group('the resolver scope note', () {
    testWidgets('states the resolver applies to panel requests, not the stream', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      // The consequence rather than the mechanism, and the mechanism this used
      // to name was wrong: the sentence blamed the panel's redirect, when a
      // stream URL is built on the panel's OWN host, so playback's first
      // request already goes to the name the user picked a resolver for.
      expect(find.textContaining('Oynatıcı adresleri kendi çözümler'), findsOneWidget);
      expect(find.textContaining('bir kanal yine de açılmayabilir'), findsOneWidget);
    });

    testWidgets('renders no address line when nothing has resolved yet', (WidgetTester tester) async {
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));

      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();

      expect(find.textContaining('Panel adresi:'), findsNothing);
    });

    testWidgets('adds exactly one line naming the resolved address', (WidgetTester tester) async {
      // Diffed against the no-address baseline rather than asserted by
      // `contains`, following the fault-sentence test above: a `contains`
      // check discriminates only by luck, as that test's own comment records.
      // Keyed distinctly, because two `ProviderSettingsLayout`s with no key in
      // the same slot keep the first's State (and its `_advancedOpen: true`)
      // across the second `pumpScreen`, which would make the second tap close
      // the disclosure it never reopened.
      await pumpScreen(tester, ProviderSettingsLayout(key: const ValueKey('a'), provider: _FakeProvider()));
      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();
      final Set<String> withoutAddress = tester
          .widgetList<WText>(find.byType(WText))
          .map((WText each) => each.data)
          .toSet();

      await pumpScreen(
        tester,
        ProviderSettingsLayout(
          key: const ValueKey('b'),
          provider: _FakeProvider(resolvedAddress: '203.0.113.9'),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Gelişmiş ayarlar'));
      await tester.pump();
      final Set<String> withAddress = tester
          .widgetList<WText>(find.byType(WText))
          .map((WText each) => each.data)
          .toSet();

      expect(withAddress.difference(withoutAddress), <String>{'Panel adresi: 203.0.113.9'});
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

    testWidgets('every fault whose recovery is the credential gets a sentence, and none gets a panel', (
      WidgetTester tester,
    ) async {
      // Load-bearing rather than a completeness test, and worth saying out
      // loud: `_faultPanel` wires BOTH of `ProviderNotice`'s callbacks to the
      // same `_run(_submit)`, so the sentence branch is the only thing keeping
      // a credential-recovery fault from rendering a button that reads
      // "Bilgileri güncelle" and resubmits the value that just failed.
      //
      // Walks `ProviderFault.values` rather than naming the two members, so a
      // sixth fault added to `needsCredentials` without a sentence on this
      // screen fails here. Without it the new member would render as a
      // `ProviderNotice` whose action reads "Bilgileri güncelle" and is wired
      // straight back to `_submit`, which is the defect this screen already
      // shipped once for `expired`.
      // Every sentence rendered with no fault at all, so the assertion below
      // is about what the FAULT added rather than about what the screen always
      // says. A `contains` over the whole screen was the first version and it
      // discriminated only by luck: the word it looked for happened to appear
      // nowhere else, so the first label containing it would have turned this
      // into a pass-always.
      await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider()));
      final Set<String> always = tester.widgetList<WText>(find.byType(WText)).map((WText each) => each.data).toSet();

      for (final ProviderFault fault in ProviderFault.values.where((ProviderFault each) => each.needsCredentials)) {
        await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(fault: fault)));

        expect(find.byType(ProviderNotice), findsNothing, reason: '$fault must not render a panel here');

        final Set<String> added = tester
            .widgetList<WText>(find.byType(WText))
            .map((WText each) => each.data)
            .toSet()
            .difference(always);

        expect(added, hasLength(1), reason: '$fault must add exactly one sentence of its own');
        expect(added.single, isNotEmpty);
      }
    });

    testWidgets('a fault whose recovery is a retry still gets the panel', (WidgetTester tester) async {
      for (final ProviderFault fault in ProviderFault.values.where((ProviderFault each) => !each.needsCredentials)) {
        await pumpScreen(tester, ProviderSettingsLayout(provider: _FakeProvider(fault: fault)));

        expect(find.byType(ProviderNotice), findsOneWidget, reason: '$fault renders as a panel');
      }
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
