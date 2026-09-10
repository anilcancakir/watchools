import 'package:magic/magic.dart';

import '../models/provider_fault.dart';
import '../protocol/xtream/xtream_account.dart';
import '../protocol/xtream/xtream_client.dart';
import '../protocol/xtream/xtream_credentials.dart';
import '../provider/provider_session.dart';

/// What the onboarding form reads of the submit flow, and nothing more.
///
/// A narrow interface beside the controller rather than the controller itself,
/// so a widget test drives the form with no container, no provider session and
/// no panel behind it. [ProviderSetupController] implements it and is what the
/// app binds; a test passes a hand-written double.
///
/// Note what is absent, because the absence is the design: nothing here hands
/// back an [XtreamCredentials], and nothing here reports a password. The four
/// typed fields go in through [submit] and the only things that come back are
/// a verdict, a form message and a flag.
abstract interface class ProviderSetupFacade {
  /// Why the panel refused the credential just typed, or null when it did not.
  ProviderFault? get fault;

  /// Whether a submit is in flight, which is what refuses a double tap.
  bool get busy;

  /// What is wrong with the form itself, in the user's language, or null.
  String? get fieldError;

  /// Whether a provider is configured right now.
  ///
  /// The screen needs this to decide whether to offer a sign-out at all, and
  /// reading `ProviderSession` from the widget instead would hand a layout the
  /// whole session when one boolean is the question. Added here rather than in
  /// the screen's own step because a facade is the only thing the screen may
  /// read, and a facade is defined beside its controller.
  bool get hasCredential;

  /// Confirms the four typed values with the panel and stores them only if it
  /// accepts them.
  Future<void> submit({
    required String baseUrl,
    required String username,
    required String password,
    required String userAgent,
  });

  /// Ends playback and forgets the current provider, in that order.
  Future<void> signOut();
}

/// What turns four typed strings into a stored credential, and the one place
/// that decides whether they earn it.
///
/// ### The order is the whole deliverable
///
/// [submit] validates, then asks the panel, then stores, and never in another
/// order. Storing first and classifying afterwards would be the same code with
/// the same tests passing and a different product: a wrong password arrives as
/// HTTP 200 carrying `{"auth": 0}`, which is valid JSON, so
/// [classifyProviderFault] takes `xtream_account.dart:219` and reports
/// [ProviderFault.expired]. Stored before that verdict, the user gets no
/// explanation now and the same fault on every later launch, from a screen that
/// has no idea a credential was ever rejected.
///
/// ### It does not know playback exists
///
/// A sign-out has to stop the core first: it holds one of the account's
/// connection slots (the measured limit on a real subscription is 1) with a
/// stream URL carrying a credential this method is about to forget. Reaching
/// the engine from here would make the provider half of the app depend on the
/// playback half, which is exactly what `ProviderSession`'s connection gate
/// exists to avoid, so the stop arrives as [_endPlayback] and
/// `AppServiceProvider` closes the loop beside the gate it already closes.
///
/// ### The user agent is not optional here
///
/// [submit] takes it as a required parameter and never invents one. Resellers
/// key access control to the header, so a silently defaulted one makes their
/// rejection unexplainable, and [XtreamCredentials] requires the field with no
/// default of its own (`xtream_credentials.dart:88`). Supplying
/// `Watchools/1.0` when the advanced disclosure was never opened is the form's
/// job, not this controller's.
class ProviderSetupController extends SimpleMagicController implements ProviderSetupFacade {
  // No `static get instance`, for the same structural reason
  // `PlaybackController` has none: `Magic.findOrPut` needs a zero-argument
  // constructor and this one requires its playback seam.
  // `AppServiceProvider.register()` binds the single instance, and a view
  // resolves it with `Magic.find<ProviderSetupController>()`.

  /// What the form says when [XtreamCredentials] refuses the panel URL.
  ///
  /// Written here rather than forwarded from the [ArgumentError], for two
  /// reasons that pull the same way. The exception's own message is English
  /// (`CLAUDE.md`: code is English, user-facing strings are Turkish), and it
  /// has two spellings, one per rejected shape, which collapse to one true
  /// statement for someone looking at a text field. The rejected value is
  /// never interpolated: it is exactly the string that may carry
  /// `user:password@host`, which is the second shape being rejected.
  static const String _panelUrlRejected =
      'Panel adresi geçersiz. http:// veya https:// ile başlayan, kullanıcı '
      'bilgisi içermeyen bir adres girin.';

  /// What the form says when the panel accepted the credential and the device
  /// refused to remember it.
  ///
  /// Not a [ProviderFault]: all four members are statements about the
  /// provider, and this one is about the keychain, so reporting `unreachable`
  /// would send the user to retry a panel that already said yes. A live path
  /// rather than a hypothetical, and it is why this arm exists at all: on
  /// macOS `Vault` is the Keychain and every `Vault.put` from a build without
  /// the `keychain-access-groups` entitlement fails with OSStatus -34018
  /// (`xtream_credentials.dart:96-105`). Letting it propagate out of a button
  /// handler was the alternative and is worse: the form would unlock with the
  /// panel confirmed, nothing stored and nothing said.
  static const String _storeRefused =
      'Panel bilgileri doğrulandı, ancak kimlik bilgisi cihazın güvenli '
      'deposuna yazılamadı.';

  /// Ends playback, without this file knowing what plays it.
  ///
  /// A closure rather than an engine or a controller, and the seam is the same
  /// shape and for the same reason as `PlaybackController`'s engine factory: it
  /// is resolved at call time, so `AppServiceProvider` can bind this controller
  /// in `register()` without touching a platform. `MpvPlaybackEngine`'s
  /// constructor subscribes to the plugin's `EventChannel`, and building one
  /// during `register()` throws `Binding has not yet been initialized` in every
  /// test that boots the providers.
  ///
  /// Named apart from its `stopPlayback` parameter because an initializing
  /// formal is not available: a private named parameter cannot be passed from
  /// another library, and `AppServiceProvider` is one.
  final Future<void> Function() _endPlayback;

  /// The provider handle passed in, or null to resolve one from the container.
  /// Follows `PlaybackController`'s shape: pass one in a test, leave it null in
  /// the app.
  final ProviderSession? _sessionOverride;

  ProviderFault? _fault;

  String? _fieldError;

  bool _busy = false;

  /// Creates the controller. [stopPlayback] is what [signOut] calls before the
  /// session clears; [session] is what a confirmed credential is adopted into.
  ProviderSetupController({required Future<void> Function() stopPlayback, ProviderSession? session})
    : _endPlayback = stopPlayback,
      _sessionOverride = session;

  ProviderSession get _session => _sessionOverride ?? Magic.findOrPut(ProviderSession.new);

  /// Why the panel refused the credential just typed, or null when it did not.
  ///
  /// This submit's own verdict rather than the session's: a rejected credential
  /// is never adopted, so [ProviderSession.fault] would have nothing to say
  /// about it, and [ProviderSession.adopt] clears its fault on the way in.
  @override
  ProviderFault? get fault => _fault;

  /// Whether a submit is in flight.
  @override
  bool get busy => _busy;

  /// What is wrong with the form itself, or null.
  ///
  /// The escape hatch for the two failures that are not statements about the
  /// provider: a panel URL [XtreamCredentials] will not accept, and a vault
  /// that would not store what the panel accepted. Both are Turkish, because
  /// this is the one member a text field renders verbatim.
  @override
  String? get fieldError => _fieldError;

  /// Read through to the session rather than cached, for the same reason
  /// `PlaybackController.health` is: `adopt` and `signOut` both move it, and a
  /// copy held here would be stale for exactly as long as it takes a listener
  /// to run.
  @override
  bool get hasCredential => _session.hasCredentials;

  /// Confirms the four typed values with the panel, and stores them only if it
  /// accepts them.
  ///
  /// 1. Construct [XtreamCredentials], which validates and normalises
  ///    [baseUrl]. A scheme-less one is the user's typo rather than anything
  ///    the provider said, so it becomes [fieldError] and **no request leaves
  ///    at all**.
  /// 2. Ask a throwaway [XtreamClient] for a handshake. Throwaway because a
  ///    client is bound to one panel by construction and this credential is not
  ///    the session's yet; [ProviderSession.adopt] builds the one that stays.
  /// 3. Classify with the one reader that owns the question, handing it this
  ///    call's own account. There is no previous account to carry forward here:
  ///    a first credential has no history, so a denial with no parsable body
  ///    reports [ProviderFault.throttled] rather than `expired`, which is the
  ///    fault whose panel offers the retry.
  /// 4. Store on a null fault, and only then.
  ///
  /// Returns rather than throwing on a refusal: every outcome a user can cause
  /// is a value here, and the screen reads it off [fault] or [fieldError].
  ///
  /// The guard at the top is the second half of what [busy] is for. The screen
  /// refuses the second tap, but it can only do that from the frame after
  /// [refreshUI], and the measured connection limit on a real account is one:
  /// two handshakes for one form is a request this app has no reason to be able
  /// to send. [ProviderSession.refresh] guards its own re-entry for the same
  /// reason.
  ///
  /// [_busy] is cleared in a `finally` so an exception this method does not
  /// claim (anything below [XtreamClient] that is not a transport failure, and
  /// a transport failure is already a value) leaves the form usable rather than
  /// wedged on its way past.
  @override
  Future<void> submit({
    required String baseUrl,
    required String username,
    required String password,
    required String userAgent,
  }) async {
    if (_busy) return;

    _busy = true;
    _fault = null;
    _fieldError = null;
    refreshUI();

    try {
      final XtreamCredentials credentials = XtreamCredentials(
        baseUrl: baseUrl,
        username: username,
        password: password,
        userAgent: userAgent,
      );

      final XtreamResponse<Map<String, dynamic>> handshake = await XtreamClient(credentials).handshake();
      final XtreamAccount? account = handshake.data == null ? null : XtreamAccount.fromHandshake(handshake.data!);

      _fault = classifyProviderFault(account: account, statusCode: handshake.statusCode, body: handshake.body);

      if (_fault != null) return;

      // `adopt` and not `refresh`: adoption is local, it restores the cached
      // catalogue for the new account key, and the first network refresh is
      // `boot()`'s job or the user's. A refresh fired from here would race the
      // connection gate against whatever brought the user to this form.
      await _session.adopt(credentials);
    } on ArgumentError {
      // Only step 1 can raise one: a transport failure arrives as
      // `statusCode: 0` rather than as a throw (`xtream_client.dart:13-16`),
      // which is why the classifier has a member for it.
      _fieldError = _panelUrlRejected;
    } on MagicVaultException {
      // The `Vault.put` inside `adopt` (`provider_session.dart:333`). Handled
      // rather than swallowed: see [_storeRefused]. Nothing was adopted, so
      // `hasCredentials` is still false and the session is untouched.
      _fieldError = _storeRefused;
    } finally {
      _busy = false;
      refreshUI();
    }
  }

  /// Ends playback and then forgets the current provider.
  ///
  /// The order is the point. The core holds one of the account's connection
  /// slots, from a URL carrying the credential in its path, and the measured
  /// limit on a real subscription is 1: clearing the session first would leave
  /// a stream running against a provider the app can no longer name, redact a
  /// log line for or stop through anything but the engine itself.
  ///
  /// The verdicts are cleared with it, because both are statements about a
  /// credential that no longer exists.
  @override
  Future<void> signOut() async {
    await _endPlayback();
    await _session.signOut();

    _fault = null;
    _fieldError = null;
    refreshUI();
  }
}
