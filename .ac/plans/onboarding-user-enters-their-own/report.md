# Onboarding: a user enters their own credentials

Seven of nine steps shipped. Two need a human at a machine and are described at the end with a
better route out than the one the plan wrote.

Delivered in two commits on `onboarding`, pull request #29.

| Step | What | State |
|---|---|---|
| 1 | Sign the macOS target so the Keychain accepts a write | deferred, and probably no longer the right fix |
| 2 | Stop a keychain read failure from booting the app to nothing | done |
| 3 | Let the session adopt a credential and forget one | done |
| 4 | Confirm a typed credential with a handshake before storing it | done |
| 5 | Replace the placeholder with the real form | done |
| 6 | Send a credential-less user to the form | done |
| 7 | Correct the fault comment this plan made false | done |
| 8 | Walk the whole flow on the running app | deferred with step 1 |
| 9 | Open the magic PR that unblocks an unsigned checkout | done, and revised through a review round |

## What the app does now that it did not

A user can type a panel address, a user name and a password, optionally a user agent, and have them
confirmed against the panel before anything is stored. `ProviderSetupController.submit` validates,
handshakes, classifies, adopts on a null fault only, and then fires the catalogue fetch. A wrong
password arrives as HTTP 200 carrying `{"auth": 0}`, which is valid JSON, so it is a credential
rejection rather than a parse failure and the user reads the real reason at the moment they caused
it.

A user with no credential is sent to that form instead of to 23 fixture channels they cannot play.
A user who has one can sign out, which stops playback first, because the core holds one of the
account's connection slots from a URL carrying the credential in its path.

## The four things this found that the plan had not

Each of these was a live path, and each is now covered by a test proved to fail without its fix.

**A keychain read failure aborted the boot.** Every `Vault` operation wraps a `PlatformException` as
`MagicVaultException`, reads included, and `_loadCredentials` caught only `FormatException`. The
failure propagated out of `start()`, which is awaited before `runApp()`: no UI at all, and no way
for the user to clear it. It is `ProviderFault.unreachable` now, not `expired`, because `expired` is
the one fault that withholds the retry.

**A sign-out during the boot-time refresh crashed, twice over.** `boot()` fires `refresh()`
unawaited and `signOut` nulls the clock and the schedule midnight, which the channel half read
through `!`. The first fix extended the EPG loop's own break, which guards the next iteration while
the crash was in the current one. The second captured before the loop, which still sat immediately
after `get_live_streams`, the single longest response in a refresh. Both are the same mistake:
narrowing a window reads exactly like closing one, and the test double had no seam that could
express the widest case. Both values are arguments now, so no nullable field is read across an await
at all.

**`PlaybackController.stop` was the one of four without the resolved-engine guard**, and wiring the
sign-out seam to it made that reachable: signing out with nothing playing constructed an
`MpvPlaybackEngine`, whose constructor subscribes to a platform channel, to stop a core that never
existed.

**`ProviderSetupFacade` shipped without a member for "is a provider configured"**, which the screen
needs to decide whether to offer a sign-out at all.

## The one the review round found, and it was the happy path

`submit` adopted the credential and deliberately did not refresh, on a stated contract that the
first fetch was "`boot()`'s job or the user's". Neither exists at that moment. `boot()`'s refresh
already ran and returned at the door because there was no credential then; `adopt` restores the
cache for an account key that has never existed; and the only other caller of `refresh()` is a
fault panel's retry that `adopt` has just cleared.

So a user who typed a working credential landed on `/` reading "Sonuç yok. Arama terimini
değiştirin", having searched for nothing, with no control anywhere that fetches a catalogue and no
recovery short of relaunching the app. On every first run.

It was invisible to the suite for a reason worth keeping: the layout test asserted the facade
received the four typed values, the controller test asserted the vault held them, and nobody owned
the frame after. `review-log.md` carries the full triage, eighteen findings fixed and six recorded.

## Gates

| Gate | Result |
|---|---|
| `flutter analyze --fatal-infos --fatal-warnings` | clean |
| `flutter test` | 534 pass, 1 deliberate skip |
| Coverage, computed with CI's own script | 2608/2709 = 96.3% against a 90% floor |
| `dart format lib test` | clean, 151 files |
| CI on #29 | both jobs green |

Four of the tests written during triage could have passed without their fix, and reading them did
not reveal it. Breaking the source revealed all four. That is the discipline this plan keeps
relearning and `wisdom.md` entry 12 is the record.

## Sibling work

`fluttersdk/magic#153` went through a review round and came out a different change. The first
version flipped macOS to the legacy keychain unconditionally, which unblocked this app and would
have silently orphaned every vault item every existing signed macOS consumer had already stored:
there is no migration between the two keychains in either direction, a miss reads as "never stored"
rather than as an error, and `Crypt._getDeviceEncrypter` generates a fresh device key on that null
read. The shape that shipped is a constructor argument plus a config key, defaulting to today's
behaviour, so nothing moves for anyone who is already storing secrets. It also gained
`FakeVaultService.throwOnRemove` and `.throwOnFlush`, and its documentation and skill pages.

Four more findings went to `.ac/research/ecosystem-defects.md`: magic drops an unregistered
middleware alias silently, which is the one kind of middleware whose absence looks like success;
wind's `InputType` has no `url` member, so the first field on this screen gets a keyboard with no
`/` or `:`; magic's vault hardcodes `iOptions` to plain `first_unlock`, which is the same
hardcoding as the macOS one with the opposite error; and `Vault` has no capability probe, which is
why a form can be offered on a platform that cannot keep what it collects.

## The two steps that need you, and the better route

**Step 1 was going to be signing.** The account side is done through `asc`: App ID `SW57679G5G`,
device `8Q46CPBVM9`, profile `6SRPP332YR`, ACTIVE to 2027 and installed. Three headless builds
still failed, because Xcode indexes an installed profile when it opens and not when `xcodebuild`
runs, and the repository was reverted to HEAD rather than left with a half-applied signing change.

The oracle checked that premise and it no longer holds as the only route. Once magic#153 is
released, one config key in a debug build (`security.vault.macos_data_protection_keychain: false`)
lets an unsigned macOS checkout write to the legacy login keychain, which needs no entitlement, and
signing becomes optional rather than a build requirement. Setting that key before the release would
be reshaping this app around an unreleased API, which `.claude/rules/workflow.md` prohibits, so it
lands with the version bump.

**Step 8 is the walk**: type a credential into the form on the running app against the local mock
panel and watch it survive a restart. It needs a real Keychain write, so it follows whichever of
the two routes above lands first. One of its own criteria wants fixing first: "a channel count of
8" can be satisfied by `catalogue_channels` rows a previous walk left behind, because `signOut`
leaves them on purpose.
