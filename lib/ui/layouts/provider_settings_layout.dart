import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show PlatformException, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/controllers/provider_setup_controller.dart';
import '../../app/models/provider_fault.dart';
import '../components/provider_notice/provider_notice.dart';
import 'support/page_gutter.dart';

/// The screen a user enters their Xtream credentials on: the one place this
/// app ever asks for a password.
///
/// ### Why no field keeps a `TextEditingController`
///
/// `Form.save()` reads every field through its own `onSaved`, and this state
/// keeps nothing else beside it. Passing no `controller:` to `WFormInput`
/// leaves it in charge of its own, disposed the moment the field unmounts
/// (`w_form_input.dart:417-423`), which is what keeps the password's typed
/// text from surviving anywhere but that one internal, short-lived object.
///
/// ### Why the fourth field alone gets a persistent `FocusNode`
///
/// The user-agent field is the one field on this screen that mounts and
/// unmounts, behind the "Gelişmiş ayarlar" disclosure. `search_focus_test.
/// dart` is the record of what a rebuild does to a focusable field with no
/// external node: `WInput` mints its own the moment none is supplied
/// (`w_input.dart:360-366`), and a field that has just been given one starts
/// over with a fresh one on the very next rebuild that happens to touch it.
/// Creating the node once in [State.initState] and threading the SAME
/// instance into every `WFormInput(focusNode:)` this widget ever builds is
/// what keeps it stable; the three fields that never unmount need no such
/// node.
///
/// ### Why the default user agent lives here, not in the controller
///
/// [ProviderSetupController.submit] takes `userAgent` as a required parameter
/// with no default of its own: a reseller keys access control to the header,
/// so a silently-invented value one layer down would make a rejection
/// unexplainable. `Watchools/1.0` is supplied here instead, where the user can
/// see and change it, the moment the disclosure was never opened or was
/// opened and left blank.
class ProviderSettingsLayout extends StatefulWidget {
  /// What this screen reads and drives.
  final ProviderSetupFacade provider;

  /// Where the back affordance goes, defaulting to popping the route.
  ///
  /// A seam rather than a hardcoded `MagicRoute.back()`, for the same reason
  /// `PlaybackLayout.onBack` is one: `MagicRouter` throws `Router not
  /// initialized` without a `MaterialApp.router` above it, and a widget test
  /// has none.
  final VoidCallback? onBack;

  /// Where a confirmed submit goes, defaulting to the live screen.
  ///
  /// The same seam shape as [onBack] and for the same reason: `MagicRouter`
  /// is never built under `pumpScreen`.
  final VoidCallback? onSaved;

  /// Creates the form.
  const ProviderSettingsLayout({super.key, required this.provider, this.onBack, this.onSaved});

  @override
  State<ProviderSettingsLayout> createState() => _ProviderSettingsLayoutState();
}

class _ProviderSettingsLayoutState extends State<ProviderSettingsLayout> {
  /// What this screen sends when the disclosure was never opened, or was
  /// opened and left blank. See the class doc block.
  static const String _defaultUserAgent = 'Watchools/1.0';

  /// The one visual shape every field on this screen shares.
  static const String _fieldClassName = '''
    w-full h-11 px-3 rounded-lg
    bg-surface-container
    border border-color-border-subtle
    text-sm text-fg
    focus:ring-2 focus:ring-focus-ring
  ''';

  static const String _labelClassName = 'text-sm font-medium text-fg mb-1';

  /// What the form says when the panel rejected the credential just typed.
  ///
  /// Rendered instead of `expired`'s [ProviderNotice] on this one screen; see
  /// the call site for why. Names both fields, because a wrong user name and a
  /// wrong password are indistinguishable on the wire: an Xtream panel answers
  /// HTTP 200 with `{"auth": 0}` either way.
  static const String _credentialRejected =
      'Panel bu kullanıcı adı ve şifreyi kabul etmedi. İkisini de kontrol edip '
      'tekrar kaydedin.';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final FocusNode _userAgentFocusNode;

  bool _advancedOpen = false;

  String _baseUrl = '';
  String _username = '';
  String _password = '';
  String _userAgent = '';

  @override
  void initState() {
    super.initState();
    _userAgentFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _userAgentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProviderFault? fault = widget.provider.fault;
    final String? fieldError = widget.provider.fieldError;

    return WDiv(
      className: 'w-full h-full bg-surface ${PageGutter.x} ${PageGutter.top} flex flex-col items-start gap-6',
      children: <Widget>[
        // Hidden with no credential, because with no credential there is
        // nowhere to go back TO and the control would be dead. This screen is
        // now reached two ways: `MagicRoute.to` from a layout, which leaves a
        // history entry, and `EnsureProvider`'s boot redirect, which does not.
        // `MagicRouter.back()` falls through all three of its branches when
        // `canPop()` is false (`magic_router.dart:578-603`) and does nothing
        // at all, silently.
        if (widget.provider.hasCredential) _backButton(),
        const WText('Sağlayıcı ayarları', className: 'text-2xl font-bold text-fg'),
        WDiv(
          className: 'w-full flex-1 min-w-0',
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: WDiv(
                className: 'w-full flex flex-col gap-4 pb-6',
                children: <Widget>[
                  _visibleField(
                    label: 'Panel adresi',
                    type: InputType.text,
                    validator: _validateBaseUrl,
                    onSaved: (String? value) => _baseUrl = value?.trim() ?? '',
                  ),
                  _plaintextWarning(),
                  _visibleField(
                    label: 'Kullanıcı adı',
                    type: InputType.text,
                    validator: _validateRequired('Kullanıcı adı gerekli.'),
                    onSaved: (String? value) => _username = value?.trim() ?? '',
                  ),
                  _visibleField(
                    label: 'Şifre',
                    type: InputType.password,
                    validator: _validateRequired('Şifre gerekli.'),
                    onSaved: (String? value) => _password = value ?? '',
                  ),
                  _disclosure(),
                  if (_advancedOpen) _userAgentField(),
                  if (fieldError != null) _fieldErrorBanner(fieldError),
                  // `expired` is the only fault whose `ProviderNotice` action
                  // is `onOpenSettings` rather than `onRetry`
                  // (`provider_notice.dart:125`), and on THIS screen the
                  // settings are the thing the user is already looking at. Its
                  // panel would offer a button reading "Bilgileri güncelle"
                  // over copy saying that retrying will not help, wired to a
                  // resubmit of the same rejected credential. It is also the
                  // most likely fault here, because it is what a mistyped
                  // password returns, so it gets the sentence that names the
                  // two fields instead.
                  if (fault == ProviderFault.expired) _fieldErrorBanner(_credentialRejected),
                  if (fault != null && fault != ProviderFault.expired) _faultPanel(fault),
                  _submitButton(),
                  if (widget.provider.hasCredential) _signOutButton(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The three settings every visible field on this screen shares.
  ///
  /// `autocorrect: false` and `enableSuggestions: false` on all three, because
  /// both default to `true` (`w_form_input.dart:108-109`) and the IME would
  /// otherwise learn the user name, which is half of
  /// `CatalogueStore.accountKey`. No `controller:` is passed, so each field
  /// owns and disposes its own; see the class doc block for why that matters
  /// most on the password field.
  Widget _visibleField({
    required String label,
    required InputType type,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
  }) {
    return WFormInput(
      type: type,
      label: label,
      labelClassName: _labelClassName,
      validator: validator,
      onSaved: onSaved,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      className: _fieldClassName,
    );
  }

  /// The user agent field, behind the disclosure.
  ///
  /// Carries the persistent [_userAgentFocusNode] rather than leaving
  /// `WFormInput` to mint its own; see the class doc block.
  ///
  /// `autocorrect` and `enableSuggestions` are off here too, and the reason is
  /// not secrecy: this value is a header a reseller keys access control to, so
  /// an IME that autocorrects `VLC/3.0.20 LibVLC/3.0.20` into something else
  /// silently changes what the panel is asked with, and the rejection that
  /// follows is unexplainable.
  Widget _userAgentField() {
    return WFormInput(
      focusNode: _userAgentFocusNode,
      label: 'Kullanıcı aracı (User-Agent)',
      labelClassName: _labelClassName,
      placeholder: _defaultUserAgent,
      onSaved: (String? value) => _userAgent = value ?? '',
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      className: _fieldClassName,
    );
  }

  /// The one thing a client that cannot fix the transport can honestly say.
  ///
  /// Xtream Codes puts the credential in the query string and then in the
  /// stream URL's PATH, so there is nothing to encrypt around and no header to
  /// move it into that would be any less readable. The provider this app was
  /// measured against is `http://` on port 8080 and the whole category is like
  /// that, so refusing `http://` would refuse the category.
  ///
  /// What is therefore deliberately NOT built: a lock badge, certificate
  /// pinning against a certificate that does not exist, hashing a password the
  /// panel needs in cleartext, or probing `https://` and falling back
  /// silently. That last one is the most tempting and the most harmful, since
  /// it teaches the user the connection was secured while leaving a downgrade
  /// anyone on the path can force.
  ///
  /// The second sentence is the only real mitigation available, because it is
  /// the only one that reduces the blast radius of a password the protocol
  /// will keep sending in the clear.
  Widget _plaintextWarning() {
    return const WText(
      'Adres https:// ile başlamıyorsa bağlantı şifrelenmez ve ağdaki '
      'herkes bu şifreyi okuyabilir. Başka bir yerde kullandığınız bir '
      'şifreyi buraya girmeyin.',
      className: 'text-xs text-fg-muted',
    );
  }

  /// Wind ships no disclosure or accordion widget, so this is one built
  /// inline: a `WAnchor` toggling a bool held in this state, with the field
  /// rendered only while it is true. Not extracted into a reusable component,
  /// because there is exactly one caller.
  Widget _disclosure() {
    final String label = _advancedOpen ? 'Gelişmiş ayarları gizle' : 'Gelişmiş ayarlar';

    return WAnchor(
      onTap: () => setState(() {
        _advancedOpen = !_advancedOpen;

        // Cleared on the way closed, because `_userAgent` is only ever
        // written by the field's `onSaved`: opening the disclosure, typing a
        // value and closing it again would otherwise keep sending that value
        // while the screen shows nothing, and the fallback to
        // [_defaultUserAgent] in `_submit` would never fire.
        if (!_advancedOpen) _userAgent = '';
      }),
      semanticLabel: label,
      child: WDiv(
        className: 'flex flex-row items-center gap-2 py-2',
        children: <Widget>[
          WText(label, className: 'text-sm font-semibold text-fg'),
          WIcon(_advancedOpen ? Icons.expand_less : Icons.expand_more, className: 'text-base text-fg'),
        ],
      ),
    );
  }

  /// What is wrong with the form itself: a panel URL `XtreamCredentials`
  /// refused, or a vault that would not store what the panel accepted.
  /// [ProviderSetupController]'s own escape hatch for the two failures that
  /// are not statements about the provider, so this is the one member of the
  /// facade rendered as plain text rather than through [ProviderNotice].
  Widget _fieldErrorBanner(String message) {
    return WDiv(
      className: 'w-full px-3 py-2 rounded-lg bg-destructive-container',
      child: WText(message, className: 'text-sm text-fg'),
    );
  }

  /// The panel for a statement about the PROVIDER, as opposed to
  /// [_fieldErrorBanner]'s statement about the form.
  ///
  /// Wrapped in a fixed height rather than left to `ProviderNotice`'s own
  /// `h-full` box (`provider_notice.recipe.dart:39`): a `Column` gives its
  /// children unbounded height, the same trap CLAUDE.md's `h-full` note
  /// records elsewhere in this app, and here the box would otherwise fall
  /// back to the full window height inside a scrolling form.
  ///
  /// `expired` never reaches here, so `onOpenSettings` is unreachable and
  /// wired to the same retry rather than left null: the remaining three faults
  /// all take `onRetry` (`provider_notice.dart:125`), and retrying is what
  /// this screen can offer for all three.
  Widget _faultPanel(ProviderFault fault) {
    return WDiv(
      className: 'w-full h-72',
      child: ProviderNotice(fault: fault, onRetry: () => _run(_submit), onOpenSettings: () => _run(_submit)),
    );
  }

  Widget _submitButton() {
    return WAnchor(
      onTap: () => _run(_submit),
      isDisabled: widget.provider.busy,
      semanticLabel: 'Kaydet',
      child: const WDiv(
        className: '''
          flex flex-row w-full h-11 items-center justify-center rounded-full
          bg-primary text-on-primary
          hover:bg-primary-hover
          focus:ring-2 focus:ring-focus-ring
          disabled:opacity-50
        ''',
        child: WText('Kaydet', className: 'text-sm font-bold'),
      ),
    );
  }

  /// Shown only when there is something to sign out of: `hasCredential` is
  /// the facade's own read of `ProviderSession`, not a guess made here.
  ///
  /// Disabled while a submit is in flight, for a reason the submit button's
  /// own `isDisabled` does not cover: without it, tapping sign-out during a
  /// handshake clears the credential and the session, and then the submit
  /// resumes and adopts the credential back. The sign-out silently undoes
  /// itself, and the controller refuses the call for the same reason.
  Widget _signOutButton() {
    return WAnchor(
      onTap: () => _run(widget.provider.signOut),
      isDisabled: widget.provider.busy,
      semanticLabel: 'Çıkış yap',
      child: const WDiv(
        className: '''
          flex flex-row w-full h-11 items-center justify-center rounded-full
          bg-surface-container text-fg
          hover:bg-surface-container-high
          focus:ring-2 focus:ring-focus-ring
        ''',
        child: WText('Çıkış yap', className: 'text-sm font-bold'),
      ),
    );
  }

  Widget _backButton() => WAnchor(
    onTap: () => (widget.onBack ?? MagicRoute.back)(),
    semanticLabel: 'Geri',
    child: const WDiv(
      className: '''
        size-10 rounded-full items-center justify-center
        bg-surface-container text-fg
        hover:bg-surface-container-high
        focus:ring-2 focus:ring-focus-ring
      ''',
      child: WIcon(Icons.arrow_back, className: 'text-base'),
    ),
  );

  /// Runs a control's command and reports what it throws.
  ///
  /// `WAnchor.onTap` is a `VoidCallback`, so a future it returns belongs to
  /// nobody: a `PlatformException` (from [ProviderSetupController.signOut]
  /// stopping playback) would otherwise become an unhandled async error.
  /// Follows `PlaybackLayout._run`.
  Future<void> _run(Future<void> Function() command) async {
    try {
      await command();
    } on PlatformException catch (failure) {
      Log.error('provider settings control failed: ${failure.code} ${failure.message ?? ''}');
    }
  }

  /// Validates, saves, and hands the four values to the facade.
  ///
  /// 1. Refuse a form the shallow validators reject; nothing leaves this
  ///    widget.
  /// 2. Save, which is what fills [_baseUrl], [_username], [_password] and,
  ///    when the disclosure was opened, [_userAgent].
  /// 3. Fall back to [_defaultUserAgent] when the disclosure was never opened
  ///    or was opened and left blank.
  /// 4. Ask the facade, then navigate only once it reports nothing wrong: a
  ///    submit that failed leaves the user on the form that explains why.
  Future<void> _submit() async {
    // The screen's own copy of the controller's busy guard, and it earns its
    // place rather than duplicating one. `isDisabled` on the button can only
    // refuse a second tap from the frame after `refreshUI` repaints, and in
    // that one frame the controller's `submit` returns immediately having
    // cleared both verdicts, so the navigation below would fire while the
    // first handshake is still out and take the user off the form.
    if (widget.provider.busy) return;

    final FormState? form = _formKey.currentState;

    if (form == null || !form.validate()) return;

    form.save();

    final String typedUserAgent = _userAgent.trim();
    final String userAgent = typedUserAgent.isEmpty ? _defaultUserAgent : typedUserAgent;

    await widget.provider.submit(baseUrl: _baseUrl, username: _username, password: _password, userAgent: userAgent);

    if (!mounted) return;

    if (widget.provider.fault == null && widget.provider.fieldError == null) {
      (widget.onSaved ?? () => MagicRoute.to('/'))();
    }
  }

  /// Non-empty, and a scheme this app recognises. The real base URL
  /// validation (rejecting `user:password@host`, for one) belongs to
  /// `XtreamCredentials`'s constructor; [ProviderSetupController.fieldError]
  /// is what reports what it throws, and duplicating that check here would be
  /// two validators disagreeing.
  String? _validateBaseUrl(String? value) {
    final String trimmed = value?.trim() ?? '';

    if (trimmed.isEmpty) return 'Panel adresi gerekli.';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'Panel adresi http:// veya https:// ile başlamalı.';
    }

    return null;
  }

  /// The one shallow check shared by user name and password: present, or not.
  FormFieldValidator<String> _validateRequired(String message) {
    return (String? value) => (value == null || value.trim().isEmpty) ? message : null;
  }
}
