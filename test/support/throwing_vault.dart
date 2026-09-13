import 'dart:async';

import 'package:magic/magic.dart';

/// Which vault operation a [ThrowingVaultService] fails.
enum VaultFailure {
  /// A keychain read that fails natively, which is what aborts a boot.
  get,

  /// A keychain write that fails, which is what OSStatus -34018 is on an
  /// unsigned macOS build.
  put,

  /// A keychain delete that fails, which is what leaves a sign-out with the
  /// credential still on the device.
  remove,
}

/// A vault double that fails exactly one operation and performs the rest.
///
/// Extends [FakeVaultService] rather than [MagicVaultService] because two of
/// the three cases have to get a credential IN first: a double that cannot
/// store is a session with nothing to read or sign out of, and the test then
/// passes for the wrong reason. The in-memory store handles everything except
/// the named operation.
///
/// The shape [FakeVaultService] itself can never produce: every one of its
/// overrides is a no-throw body over a map. Stands in for the darwin plugin
/// turning a non-success `OSStatus` into a `PlatformException`, which
/// [MagicVaultService] then wraps as [MagicVaultException] on all four
/// operations (`magic/lib/src/security/magic_vault_service.dart:48-104`).
///
/// One operation at a time, which mirrors the hooks `magic` itself is gaining
/// in `fluttersdk/magic#153`: a throw armed on `get` does not touch `put`. That
/// PR supersedes this file, and it is unreleased while this repository resolves
/// magic from pub.dev in CI.
class ThrowingVaultService extends FakeVaultService {
  ThrowingVaultService(this.failing);

  /// The operation that throws.
  final VaultFailure failing;

  @override
  Future<String?> get(String key) async {
    if (failing == VaultFailure.get) {
      throw MagicVaultException('Keychain read failed', 'simulated OSStatus failure');
    }

    return super.get(key);
  }

  @override
  Future<void> put(String key, String value) async {
    if (failing == VaultFailure.put) {
      throw MagicVaultException('Keychain write failed', 'simulated OSStatus -34018');
    }

    return super.put(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (failing == VaultFailure.remove) {
      throw MagicVaultException('Keychain delete failed', 'simulated OSStatus failure');
    }

    return super.remove(key);
  }

  /// Registers this double under the `vault` binding, the way [Vault.fake]
  /// registers [FakeVaultService]. Callers restore normal resolution with
  /// [Vault.unfake].
  static ThrowingVaultService install(VaultFailure failing) {
    final ThrowingVaultService service = ThrowingVaultService(failing);
    Magic.app.setInstance('vault', service);

    return service;
  }
}

/// A vault double that holds one `put` open until the test lets it finish.
///
/// [FakeVaultService] completes every operation in the microtask the caller
/// queued it in, so two writers suspended on it always resume in call order.
/// That is the SAFE ordering, and it is the reason a race between
/// `ProviderSession.setBackgroundPlayback` and `signOut` cannot be reproduced
/// on the plain fake: the preference write resumes and finishes before the
/// sign-out ever gets to null the record.
///
/// A real Keychain gives no such guarantee, and the orderings differ in cost: a
/// write is the slower of the two operations, so the sign-out landing FIRST is
/// the ordering to expect on a device, and it is the one where an unguarded
/// writer resurrects a credential the user has just deleted and puts their
/// password back on disk behind the delete.
///
/// One `put` at a time, armed explicitly, so seeding a credential through the
/// same double is unaffected.
class StallingVaultService extends FakeVaultService {
  Completer<void>? _gate;

  /// Whether a [put] has already taken [_gate], so the next one runs through.
  ///
  /// Separate from nulling [_gate] on the way in, which is the shape this was
  /// written as first and which deadlocks: [release] then has no reference to
  /// the completer the stalled [put] is waiting on, so nothing ever completes
  /// it and the test hangs to its timeout rather than failing on an assertion.
  bool _claimed = false;

  /// Makes the NEXT [put] wait for [release] before it stores anything.
  void stallNextPut() {
    _gate = Completer<void>();
    _claimed = false;
  }

  /// Lets a stalled [put] finish. Safe to call when nothing is stalled.
  void release() {
    final Completer<void>? gate = _gate;
    _gate = null;
    _claimed = false;

    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> put(String key, String value) async {
    final Completer<void>? gate = _gate;

    // Exactly one write is held. A second `put` arriving while the first waits
    // is a different operation, usually the very one the test is racing in, so
    // it has no reason to inherit the stall.
    if (gate != null && !_claimed) {
      _claimed = true;
      await gate.future;
    }

    return super.put(key, value);
  }

  /// Registers this double under the `vault` binding, the way
  /// [ThrowingVaultService.install] does.
  static StallingVaultService install() {
    final StallingVaultService service = StallingVaultService();
    Magic.app.setInstance('vault', service);

    return service;
  }
}
