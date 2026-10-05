#!/bin/bash
# Run outside a restricted sandbox: CoreSimulator must be available.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p Mobile/build/screenshots
mise run ios:build > Mobile/build/screenshot-build.log 2>&1
# Keep inherited credentials out of simulator subprocesses.
simctl() {
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="$DEVELOPER_DIR" xcrun simctl "$@"
}
simctl list devices available -j > Mobile/build/screenshot-devices.json
python3 - <<'PY' > Mobile/build/screenshot-devices.tsv
import json
with open('Mobile/build/screenshot-devices.json') as stream:
    groups = json.load(stream)['devices']
# Prefer the newest available iOS runtime and use an iPad from the same runtime.
for runtime, devices in sorted(groups.items(), reverse=True):
    phones = [d for d in devices if d.get('isAvailable') and d['name'] == 'iPhone 17']
    tablets = [d for d in devices if d.get('isAvailable') and d['name'].startswith('iPad')]
    if phones and tablets:
        for label, device in [('iphone', phones[0]), ('ipad', tablets[0])]:
            print(label, device['udid'], device['state'], sep='\t')
        break
else:
    raise SystemExit('Install an iOS runtime with iPhone 17 and an iPad in Xcode first.')
PY
app="$PWD/Mobile/build/DerivedData/Build/Products/Debug-iphonesimulator/StriaMobile.app"
bundle=me.tacogips.stria.mobile
capture() {
  local device="$1" label="$2" screen="$3"
  shift 3
  simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true
  simctl launch "$device" "$bundle" -StriaSampleImport "$@" >/dev/null
  # Small sample import and navigation need time to settle before capture.
  sleep 8
  simctl io "$device" screenshot "$PWD/Mobile/build/screenshots/$label-$screen.png"
}
while IFS=$'\t' read -r label device state; do
  if [ "$state" != Booted ]; then simctl boot "$device"; fi
  simctl bootstatus "$device" -b
  simctl ui "$device" appearance light
  simctl install "$device" "$app"
  capture "$device" "$label" library
  if [ "$label" = iphone ]; then
    capture "$device" "$label" reader -StriaReader
    capture "$device" "$label" agent-chat -StriaAgent
    capture "$device" "$label" settings -StriaSettings
    capture "$device" "$label" settings-ocr-vendors -StriaOCRVendors
  else
    capture "$device" "$label" reader-agent -StriaAgent
  fi
done < Mobile/build/screenshot-devices.tsv
printf '%s\n' Mobile/build/screenshots/*.png
