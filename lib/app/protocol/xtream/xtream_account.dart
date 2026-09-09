import 'package:flutter/foundation.dart';

import '../../models/provider_fault.dart';
import 'xtream_json.dart';

/// What a handshake said about the user's subscription, parsed once and read
/// many times.
///
/// Built from the two objects the no-action `player_api.php` call answers
/// with, `user_info` and `server_info`, through the readers in
/// `xtream_json.dart` that already absorb the wire's type drift: `auth` bare
/// beside `max_connections` quoted, in the same object.
///
/// Deliberately does not carry `username` or `password`, even though the
/// panel echoes both back inside `user_info`
/// (`tool/xtream-mock/server.mjs:151-152`): `magic_devtools`'s telescope
/// interceptor records the first 8 KiB of every response body, so a value
/// type that kept them would be one `Log` line or one inspector away from a
/// provider password. Neither field is read here, on receipt, rather than
/// stripped by a wrapper downstream that runs after the interceptor already
/// has.
///
/// A value type rather than a Magic ORM model, matching `XtreamCredentials`:
/// this is a fact about one handshake, not a row to persist.
@immutable
class XtreamAccount {
  /// `user_info.auth`. `true` only when the wire sent the bare integer `1`;
  /// a missing or unparsable field reads as `false` rather than as unknown,
  /// because [active] cannot afford a third state here.
  final bool auth;

  /// `user_info.status`, verbatim and un-lowercased. `null` on panels that
  /// omit it, which [active] treats as passing rather than as failing: a
  /// truthy [auth] with no status text is what a real client calls active.
  final String? status;

  /// `user_info.exp_date`, already folded by [readExpiryEpoch]: `null` means
  /// no expiry (lifetime, trial, reseller), never "epoch zero". A caller
  /// comparing this against a raw `exp_date` string without that fold is the
  /// bug `lifetime:lifetime`'s mock account exists to catch.
  final int? expiresAt;

  /// `user_info.max_connections`, read through [readInt] because the wire
  /// sends it quoted. Defaults to `0` on a malformed or absent field, which
  /// [atConnectionLimit] reads as "no limit stated" rather than as a limit of
  /// zero.
  final int maxConnections;

  /// `user_info.active_cons`, the same quoted-string shape as
  /// [maxConnections].
  final int activeConnections;

  /// `user_info.allowed_output_formats`, filtered to the string entries: a
  /// wire that sent something else in the array has nothing a client reading
  /// container extensions can use.
  final List<String> allowedOutputFormats;

  /// `server_info.timestamp_now`, the panel's own clock as a Unix epoch.
  final int? panelTimestamp;

  /// `server_info.time_now`, the same instant panel-local and pre-formatted.
  /// Kept as sent rather than parsed into a [DateTime]: nothing here needs it
  /// as one, and a caller that renders the provider's own clock verbatim is
  /// the one that will.
  final String? panelTime;

  /// Creates an account from its already-read fields. Prefer
  /// [XtreamAccount.fromHandshake] at a call site; this is what it builds.
  const XtreamAccount({
    required this.auth,
    required this.status,
    required this.expiresAt,
    required this.maxConnections,
    required this.activeConnections,
    required this.allowedOutputFormats,
    required this.panelTimestamp,
    required this.panelTime,
  });

  /// Parses a decoded handshake body: `{ "user_info": {...}, "server_info":
  /// {...} }`, as `decodeBody` hands one back.
  ///
  /// Never throws on a shape short of that: a missing `user_info` or
  /// `server_info` object reads as empty rather than as a cast failure,
  /// because the rejected-credentials handshake sends exactly one key
  /// (`{"auth": 0}`) and nothing else, and that shape has to parse rather
  /// than crash the caller that classifies it.
  factory XtreamAccount.fromHandshake(Map<String, dynamic> handshake) {
    final Map<String, dynamic> userInfo = _asObject(handshake['user_info']);
    final Map<String, dynamic> serverInfo = _asObject(handshake['server_info']);

    return XtreamAccount(
      auth: readBool(userInfo, 'auth') ?? false,
      status: readNullableString(userInfo, 'status'),
      expiresAt: readExpiryEpoch(userInfo, 'exp_date'),
      maxConnections: readInt(userInfo, 'max_connections') ?? 0,
      activeConnections: readInt(userInfo, 'active_cons') ?? 0,
      allowedOutputFormats: _asStringList(userInfo['allowed_output_formats']),
      panelTimestamp: readInt(serverInfo, 'timestamp_now'),
      panelTime: readNullableString(serverInfo, 'time_now'),
    );
  }

  /// Whether the subscription is usable at all, as the disjunction three
  /// independent clients (`iptvnator`, `tvarr`) agree on:
  /// `.ac/plans/xtream-codes-protocol-layer-watchools/research/librarian-xtream-reality.md`
  /// section 4. Not active when [auth] is not `true`, OR [status] is present
  /// and is not `Active` case-insensitively, OR [expiresAt] is set and
  /// already in the past. A missing [status] beside a truthy [auth] is
  /// active: real panels omit the field on a healthy account.
  bool get active {
    if (!auth) return false;
    if (status != null && status!.toLowerCase() != 'active') return false;
    if (expiresAt != null && expiresAt! < _nowEpochSeconds()) return false;

    return true;
  }

  /// Whether every connection the subscription is allowed is already in use.
  ///
  /// Orthogonal to [active]: a subscription can be alive and fully booked at
  /// once, which is a different problem (`ProviderFault.evicted`) from a dead
  /// credential (`ProviderFault.expired`).
  ///
  /// `false` when [maxConnections] is not a positive number, because a panel
  /// that stated no limit has not stated a limit that is reached. Reading the
  /// `0` default as a limit would make `0 >= 0` true and route a healthy
  /// account with a drifted `max_connections` field to
  /// `ProviderFault.evicted`, whose message tells the user another device is
  /// streaming and whose retry is withheld. Under ignorance the honest answer
  /// is the one whose retry is safe.
  bool get atConnectionLimit => maxConnections > 0 && activeConnections >= maxConnections;

  @override
  bool operator ==(Object other) =>
      other is XtreamAccount &&
      other.auth == auth &&
      other.status == status &&
      other.expiresAt == expiresAt &&
      other.maxConnections == maxConnections &&
      other.activeConnections == activeConnections &&
      listEquals(other.allowedOutputFormats, allowedOutputFormats) &&
      other.panelTimestamp == panelTimestamp &&
      other.panelTime == panelTime;

  @override
  int get hashCode => Object.hash(
    auth,
    status,
    expiresAt,
    maxConnections,
    activeConnections,
    Object.hashAll(allowedOutputFormats),
    panelTimestamp,
    panelTime,
  );

  @override
  String toString() =>
      'XtreamAccount(auth: $auth, status: $status, expiresAt: $expiresAt, '
      'maxConnections: $maxConnections, activeConnections: $activeConnections)';

  /// Now, in the same unit as [expiresAt]: Unix epoch seconds. The device's
  /// own clock, not the panel's: [expiresAt] is a real-world instant, and
  /// [panelTimestamp] exists to compare against it rather than to replace it.
  static int _nowEpochSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Reads [value] as a JSON object, or empty when it is anything else.
  static Map<String, dynamic> _asObject(Object? value) => value is Map<String, dynamic> ? value : <String, dynamic>{};

  /// Reads [value] as a list of strings, skipping any element that is not
  /// one, the same tolerance [decodeEntries] applies to a list of objects.
  static List<String> _asStringList(Object? value) => value is List ? value.whereType<String>().toList() : <String>[];
}

/// Classifies why [account] is not delivering a working catalogue, from
/// [statusCode] and [body] alone.
///
/// [account] is the last handshake the session parsed, not necessarily built
/// from THIS response: a denial can land on a later call (a listing action,
/// not the handshake itself), and comparing it against the account already
/// known is what lets [ProviderFault.throttled] and [ProviderFault.evicted]
/// exist as separate members rather than one. Precedence, decided once here
/// so a caller never has to reconstruct it:
///
/// 1. [ProviderFault.unreachable] when [statusCode] is `0`: no response
///    reached the app, so there is nothing else to reason about.
/// 2. [ProviderFault.expired] when [account] is `null` or
///    `XtreamAccount.active` is `false`. A denial landing on a subscription
///    already known dead is still the dead subscription, not a fresh
///    throttle.
/// 3. [ProviderFault.evicted] when [account] is active, at its connection
///    limit, and [body] is the generic non-JSON denial: retrying costs the
///    other device its slot.
/// 4. [ProviderFault.throttled] for that same denial on an account that is
///    active but not at its limit.
/// 5. `null` when [account] is active and [body] decoded as JSON, which is
///    what a healthy call looks like whether the action answers an object or
///    an array.
///
/// Never call this with the result of parsing a list body as evidence of
/// health: a dead subscription still returns its whole catalogue and fails
/// only at the stream, so [_isGenericDenial] treats a decodable JSON array
/// as healthy, the same as a decodable object.
ProviderFault? classifyProviderFault({
  required XtreamAccount? account,
  required int statusCode,
  required Object? body,
}) {
  // 1. Nothing answered at all.
  if (statusCode == 0) return ProviderFault.unreachable;

  // 2. A body that decoded is a body that spoke. Whatever the account says is
  //    then the answer: a null or inactive one here is a real credential
  //    rejection, because the panel returned JSON and that JSON is what the
  //    account was parsed from. A JSON array counts, so a healthy catalogue
  //    call is never mistaken for a denial.
  if (!_isGenericDenial(body)) {
    return (account == null || !account.active) ? ProviderFault.expired : null;
  }

  // 3. The generic denial with no account behind it, which is the first-launch
  //    case: the handshake itself came back as unparseable text. That says
  //    nothing whatsoever about the credential, so it must not be read as
  //    `expired`, the one fault that withholds the retry
  //    (`provider_notice.dart`'s button routes to settings for it and nowhere
  //    useful, since no onboarding screen exists). A blocked address, a
  //    blocked user agent and a reverse proxy's HTML error page all land here,
  //    and all three are recoverable.
  if (account == null) return ProviderFault.throttled;

  // 4. A subscription already known dead stays dead, whatever this call
  //    answered.
  if (!account.active) return ProviderFault.expired;

  // 5. The denial against a live account, narrowed by whether answering it
  //    would cost the other device its slot.
  return account.atConnectionLimit ? ProviderFault.evicted : ProviderFault.throttled;
}

/// Whether [body] is the provider's generic denial shape: text that decodes
/// as neither a JSON object nor a JSON array. Real panels answer a blocked
/// address, a blocked user agent, an HTML error page and a rate limit all
/// this same way (`tool/xtream-mock/server.mjs:736-746`, `README.md:126-129`),
/// so this reader cannot itself say which; [classifyProviderFault] narrows it
/// with the account's own state.
///
/// Checking [decodeBody] alone is wrong: it returns `null` for a JSON array
/// too, and a list body is exactly what most catalogue actions answer with,
/// so that check alone would misclassify a healthy `get_live_streams` call as
/// a denial.
bool _isGenericDenial(Object? body) => decodeBody(body) == null && decodeEntries(body) == null;
