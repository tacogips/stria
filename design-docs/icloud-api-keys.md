# iCloud API keys

Implemented on 2026-10-06 for the iPhone/iPad and Mac applications.

## Storage and behavior

- API keys use synchronizable Keychain generic-password items, scoped to the
  existing `me.tacogips.stria.apikey` service and vendor account name.
- Synchronization defaults to enabled on iPhone/iPad and disabled on Mac. On
  Mac, enable it in Settings in the signed app. It requires the same Apple Account and
  iCloud Passwords & Keychain enabled on both devices. Arrival is asynchronous;
  saving locally does not establish that another device has received the key.
- Existing device-only keys migrate on first read. The cloud copy is written
  before the old local item is removed.
- Turning synchronization off copies available keys into device-only storage;
  existing cloud copies remain. Turning it back on copies local keys into the
  synchronized scope, replacing that vendor's cloud value.
- Explicit deletion removes both local and synchronized scopes. A different
  device that opted out can retain its independent local copy.
- Keys are never written into the document synchronization folder or config.
- The signed Mac app uses the iOS app's explicit shared Keychain access group.
  The Mac Developer ID provisioning profile and signing entitlements authorize
  that group. An unsigned `swift run stria-app` can use local key storage, but
  cannot access the shared synchronized group.
- Vendor controls save immediately, show saved status, accept replacements,
  and confirm deletion. Saved secrets are not displayed in the form.

Synchronization uses `kSecAttrSynchronizable` and
`kSecAttrAccessibleAfterFirstUnlock`; device-only items use
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. See
[Apple's synchronizable Keychain documentation](https://developer.apple.com/documentation/security/ksecattrsynchronizable).

## Verification

19 targeted tests passed across credential, platform, and settings suites.
The Keychain tests use an injected executor and cover migration, replacement,
scope switching, failure recovery, deletion, and avoiding cloud reads while
sync is disabled. They do not use real vendor keys or the user's Keychain.
SwiftLint passed. iPhone and iPad simulator builds passed.
The Developer ID signed Mac probe passed code-signature validation and
synchronizable add/read/delete operations in the shared group. This checks
local access rights, not cloud propagation.

Physical verification remains required: save a key on iPhone, reopen Settings
on iPad and signed Mac, confirm saved status, and perform an authorized provider
request. Repeat replacement and deletion, then check local-only behavior with
sync off.
Do not include key values in evidence or screenshots.
