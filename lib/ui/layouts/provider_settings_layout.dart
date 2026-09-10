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
        _backButton(),
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
                  if (fault != null) _faultPanel(fault),
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
  /// `WFormInput` to mint its own; see the class doc block. `autocorrect` and
  /// `enableSuggestions` are left at their defaults here: unlike the three
  /// visible fields, nothing this field carries is sensitive or something an
  /// IME dictionary would leak.
  Widget _userAgentField() {
    return WFormInput(
      focusNode: _userAgentFocusNode,
      label: 'Kullanıcı aracı (User-Agent)',
      labelClassName: _labelClassName,
      placeholder: _defaultUserAgent,
      onSaved: (String? value) => _userAgent = value ?? '',
      textInputAction: TextInputAction.done,
      className: _fieldClassName,
    );
  }

  /// Wind ships no disclosure or accordion widget, so this is one built
  /// inline: a `WAnchor` toggling a bool held in this state, with the field
  /// rendered only while it is true. Not extracted into a reusable component,
  /// because there is exactly one caller.
  Widget _disclosure() {
    final String label = _advancedOpen ? 'Gelişmiş ayarları gizle' : 'Gelişmiş ayarlar';

    return WAnchor(
      onTap: () => setState(() => _advancedOpen = !_advancedOpen),
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
  /// Both callbacks retry the same submit: unlike the browse screens, this
  /// panel appears from the user's OWN just-typed credentials rather than
  /// from a stored one, so `onOpenSettings` (`expired`'s own action) has
  /// nowhere else to send them; editing the fields and trying again is the
  /// only recovery this screen can offer either way.
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
  Widget _signOutButton() {
    return WAnchor(
      onTap: () => _run(widget.provider.signOut),
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
