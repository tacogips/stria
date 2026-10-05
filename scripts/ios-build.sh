#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Mobile/build/packages Mobile/build/tool-home Mobile/build/package-cache
# Reuse resolved packages without mutating SwiftPM's .build directory.
if [ ! -d Mobile/build/packages/checkouts ]; then
  cp -R .build/checkouts Mobile/build/packages/checkouts
  cp -R .build/repositories Mobile/build/packages/repositories
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# CoreSimulator may be unavailable in a restricted environment. A generic
# simulator build still compiles both device families in that case.
if env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="$DEVELOPER_DIR" xcrun simctl list devices available -j > Mobile/build/devices.json 2> Mobile/build/simulator-error.log; then
  ipad_name=$(python3 - <<'PY'
import json
with open('Mobile/build/devices.json') as stream:
    devices = json.load(stream)['devices']
names = [d['name'] for group in devices.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPad')]
if not names:
    raise SystemExit('No available iPad simulator')
print(names[0])
PY
)
  destinations=("platform=iOS Simulator,name=iPhone 17" "platform=iOS Simulator,name=$ipad_name")
else
  echo "CoreSimulator unavailable; compiling both iPhone/iPad families for generic iOS Simulator." >&2
  destinations=("generic/platform=iOS Simulator")
fi
cd Mobile
for destination in "${destinations[@]}"; do
  # A minimal environment prevents build logs from containing inherited keys.
  env -i HOME="$PWD/build/tool-home" CFFIXED_USER_HOME="$PWD/build/tool-home" PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="$DEVELOPER_DIR" \
    xcodebuild build -project StriaMobile.xcodeproj -scheme StriaMobile \
    -configuration Debug -destination "$destination" -derivedDataPath build/DerivedData \
    -clonedSourcePackagesDirPath build/packages -disableAutomaticPackageResolution \
    -packageCachePath "$PWD/build/package-cache" -skipPackageUpdates \
    CODE_SIGNING_ALLOWED=NO
done
