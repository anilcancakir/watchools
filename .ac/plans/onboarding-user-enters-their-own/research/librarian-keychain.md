# macOS Keychain: why -34018 fires and what actually clears it

`ac:librarian`, thorough, five searches. Written after the fact: Stage 1e should have
archived every agent's output here and this one was missed, which the plan reviewer caught
as a dangling reference. The content is the agent's, condensed to the claims the plan rests
on, with its own confidence separation preserved.

## The mechanism

`-34018` is `errSecMissingEntitlement`, and it is an **access-group** check rather than a
sandbox one.

> Error -34018 translates to errSecMissingEntitlement. This error means that your app is
> trying to use a keychain access group for which it does not have entitlements.

Apple Developer Forums thread 114456, an Apple engineer reply. Documented.

The reason adding the entitlement broke the build is that `keychain-access-groups` is a
**restricted** entitlement:

> In contrast, restricted entitlements must be authorized by a provisioning profile... the
> fact that the `keychain-access-groups` entitlement must be authorized by a profile means
> that other developers can't impersonate your app.

TN3125, Inside Code Signing: Provisioning Profiles. Documented.

And the entitlement is not itself the grant. What grants a default access group is being
signed with an App ID:

> The data protection keychain is only available to code that can carry an entitlement... To
> use the data protection keychain your app must be signed with an App ID. Without that, you
> get the errSecMissingEntitlement error (which is -34018)... The easiest way to force Xcode
> to sign your app with an App ID is to add a restricted entitlement to your project.

TN3137, On Mac keychain APIs and implementations. **Indexed snippet only**: the page itself
was unreachable through all three fetch layers (WebFetch returned an unrendered application
shell, the MCP fetch returned only the account header, the browser escalation timed out at
60 s). This is the weakest link in the chain and the reason step 1 verifies its own outcome
with `codesign` rather than trusting the source.

## What the plugin documents

flutter_secure_storage's README:

> You also need to add Keychain Sharing as capability to your macOS runner... add the
> following in *both* your `macos/Runner/DebugProfile.entitlements` *and*
> `macos/Runner/Release.entitlements`

followed by `<key>keychain-access-groups</key><array/>`. First-party, and it says nothing
about the signing consequence. Its own example app ships exactly that empty array, and
**also** sets `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development"` and
`CODE_SIGN_STYLE = Automatic` at target level, which watchools does not. That difference is
the whole of step 1.

Corroborating the other direction: flutter_secure_storage issue #804 shows the entitlement
present with an explicit named group and the write still returning `-34018`, which is why
the plan uses an empty array rather than naming one.

## What signing actually requires

flutter_secure_storage issue #1176, user-reported, 2026-07-01:

> When using a free Apple Developer account, once `keychain-access-groups` is present, Xcode
> automatically switches from `Provisioning Profile: None Required` to
> `Provisioning Profile: Xcode Managed Profile`... the resulting application can only run on
> the Mac used for signing.

So a free Apple ID plus a `DEVELOPMENT_TEAM` and a development certificate is enough for a
local, machine-scoped build. A paid membership matters only for running that signed build on
a different Mac.

## The no-signing route, and its cost

flutter_secure_storage PR #1047, the accepted workaround:

> use following workaround that allows the application to work without
> keychain-access-groups, avoiding the provisioning requirement:
> `MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device, usesDataProtectionKeychain: false)`

The cost, read out of the plugin's Swift rather than its docs:
`FlutterSecureStorage.swift:227-231` is
`if #available(macOS 10.15, *), params.usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain] = true }`.
So `false` **omits** the key rather than setting it false, the item lands in the legacy login
keychain, and an item written there is invisible to any later read that sets the flag true.
The plugin ships no migration for that. Separately, `kSecAttrAccessible` is set
unconditionally at `:219-222`, outside the data-protection branch, so
`first_unlock_this_device` is applied to a legacy-keychain item where Apple documents the
attribute as data-protection-only; whether that is ignored or returns `errSecParam` was not
settled.

## Sandbox

Toggling `com.apple.security.app-sandbox` changes nothing, which matches what was measured
here directly. The two entitlements are independent axes: the sandbox controls filesystem
and network access, `keychain-access-groups` controls which access group a `SecItemAdd` may
claim. **Inferred** by combining the errSecMissingEntitlement mechanics with TN3125's
restricted-entitlement model; no single Apple sentence says it.

## CI

Real projects that build macOS in CI without an identity strip `DEVELOPMENT_TEAM` and
`CODE_SIGN_IDENTITY` and set `CODE_SIGNING_ALLOWED=NO`, then codesign afterwards for release
artifacts. None of that applies here: a Flutter-only job running `flutter analyze` and
`flutter test` never invokes `xcodebuild`, and this project's CI compiles no Swift at all
(`ci.yml:23` and `:150` are both `ubuntu-latest`).

## Sources

- https://developer.apple.com/documentation/security/errsecmissingentitlement
- https://developer.apple.com/forums/thread/114456
- https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
- https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains (indexed snippet only, page unreachable)
- https://github.com/juliansteenbakker/flutter_secure_storage (README, example entitlements, issues #804, #1176, PR #1047)
