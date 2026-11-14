# Default iCloud Drive folder

Stria now uses the app-owned `iCloud.me.tacogips.stria` container's `Documents`
directory when no explicit folder is selected. Folder selection is optional.
The existing sync enable switch continues to control document synchronization;
local reading and imports remain available when iCloud is unavailable.

The iOS application declares CloudDocuments and the explicit container in its
entitlements. Its App ID has the container assigned, and the distribution
profile must authorize the same container. The IPA check verifies both signed
entitlements and the embedded profile before upload. Container lookup runs on
a utility task so it cannot hold up the UI thread.

A saved iPhone/iPad folder bookmark retains priority. Settings provides
“Use Default iCloud Folder” to remove that device's folder override; it does
not delete documents from the previous folder. On Mac, a configured folder
retains priority, and the entitled container is preferred when available.
Mac builds without available container access retain the previous
iCloud Drive/Stria fallback. Upgrade each device to this release to use the new
automatic container consistently; existing files in older custom folders are
not moved or deleted automatically.

Konjac uses an app-owned CloudKit container. Stria retains its existing file
synchronization format in an app-owned iCloud document container.

Verification covers default resolution without a bookmark, explicit folder
priority, unavailable iCloud, and existing sync engine/controller behavior.
Real cloud propagation requires devices using the same Apple Account with
iCloud Drive enabled.
