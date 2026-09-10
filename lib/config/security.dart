import 'package:flutter/foundation.dart' show kReleaseMode;

/// Security Configuration.
///
/// - `vault.macos_data_protection_keychain`: which of macOS's two keychains
///   `Vault` reads and writes. Consulted on macOS alone.
///
/// ### Why this file exists at all
///
/// The data protection keychain requires the restricted
/// `keychain-access-groups` entitlement, and a restricted entitlement forces
/// the build to be signed with an App ID rather than ad hoc, so every
/// `Vault.put` from a checkout with no certificate installed fails with
/// `PlatformException(-34018, errSecMissingEntitlement)`; measured through
/// this app's own build with the sandbox both on and off. That made the one
/// platform with a working player the one platform where a credential could
/// not be stored. The legacy login keychain needs no entitlement, and
/// `magic 0.0.10` is what made it reachable
/// (`fluttersdk/magic#153`).
///
/// ### Why the value is [kReleaseMode] rather than `false`
///
/// A release build is signed and should have the stronger keychain: the data
/// protection one is where `kSecAttrAccessible` means anything at all, and
/// where Apple is putting its effort (TN3137 puts the file-based keychain "on
/// the road to deprecation"). Debug and profile builds are what a contributor
/// runs with no certificate, and those are the ones that need the way out.
/// Profile is included deliberately: `tool/dusk/perf.sh` starts a profile
/// build and would otherwise be unable to store anything.
///
/// ### The cost, stated because it is silent
///
/// **There is no migration between the two keychains in either direction**,
/// and a miss reads as "never stored" rather than as an error. So a credential
/// entered in a debug build is invisible to a release build of the same app,
/// and the release build offers the onboarding form as though nothing had ever
/// been entered. That is acceptable here and only here: this is a provider
/// credential the user can retype, the two builds are not the same install in
/// practice, and the alternative is a debug build that cannot store one at
/// all. It would not be acceptable for anything the user cannot reproduce.
Map<String, dynamic> get securityConfig => <String, dynamic>{
  'security': <String, dynamic>{
    'vault': <String, dynamic>{'macos_data_protection_keychain': kReleaseMode},
  },
};
