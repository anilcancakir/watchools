import 'package:magic/magic.dart';

/// A [MagicVaultService] double whose [get] always throws
/// [MagicVaultException], the one shape [FakeVaultService] can never
/// produce: every one of its overrides is a no-throw body over an in-memory
/// map (`magic/lib/src/testing/fake_vault_service.dart:37-59`).
///
/// Stands in for a keychain read that fails natively: the darwin plugin
/// turns every non-success `OSStatus` into a `PlatformException`, and
/// [MagicVaultService.get] wraps that as [MagicVaultException]
/// (`magic/lib/src/security/magic_vault_service.dart:48-54`). Uses
/// [MagicVaultService.forTesting] as its super constructor for the same
/// reason [FakeVaultService] does: it skips the `late final _storage`
/// assignment, so nothing here ever touches real secure storage.
class ThrowingVaultService extends MagicVaultService {
  ThrowingVaultService() : super.forTesting();

  @override
  Future<String?> get(String key) async {
    throw MagicVaultException('Keychain read failed', 'simulated OSStatus failure');
  }

  /// Registers this double under the `vault` binding, the way [Vault.fake]
  /// registers [FakeVaultService]. Callers restore normal resolution with
  /// [Vault.unfake].
  static ThrowingVaultService install() {
    final ThrowingVaultService service = ThrowingVaultService();
    Magic.app.setInstance('vault', service);

    return service;
  }
}
