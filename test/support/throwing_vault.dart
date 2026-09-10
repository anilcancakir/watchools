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
