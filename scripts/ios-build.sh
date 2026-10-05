#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Mobile/build/packages Mobile/build/tool-home Mobile/build/package-cache
# XcodeGen can retain a stale workspace pin. Always use the root package pin.
resolved_dir=Mobile/StriaMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved_dir"
cp Package.resolved "$resolved_dir/Package.resolved"
agent_revision=$(python3 - <<'PYTHON'
import json
with open('Package.resolved') as stream:
    pins = json.load(stream)['pins']
print(next(pin['state']['revision'] for pin in pins if pin['identity'] == 'agent-gateway'))
PYTHON
)
# Reuse resolved packages without mutating SwiftPM's .build directory. Refresh
# both caches when the checkout is stale or the bare repository lacks the pin.
cached_revision=$(git -C Mobile/build/packages/checkouts/agent-gateway rev-parse HEAD 2>/dev/null || true)
repository_has_pin=false
for repository in Mobile/build/packages/repositories/agent-gateway-*; do
  if git -C "$repository" cat-file -e "$agent_revision^{commit}" 2>/dev/null; then
    repository_has_pin=true
    break
  fi
done
if [ "$cached_revision" != "$agent_revision" ] || [ "$repository_has_pin" != true ]; then
  source_revision=$(git -C .build/checkouts/agent-gateway rev-parse HEAD)
  if [ "$source_revision" != "$agent_revision" ]; then
    echo "The .build agent-gateway checkout must match the root Package.resolved before building iOS." >&2
    exit 1
  fi
  rm -rf Mobile/build/packages/checkouts Mobile/build/packages/repositories
  cp -R .build/checkouts Mobile/build/packages/checkouts
  cp -R .build/repositories Mobile/build/packages/repositories
  # Keep SwiftPM checkout metadata aligned with the refreshed source trees.
  if [ -f .build/workspace-state.json ]; then
    cp .build/workspace-state.json Mobile/build/packages/workspace-state.json
  fi
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
