#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
product="stria"
app_product="stria-app"
app_name="Stria"
bundle_id="me.tacogips.stria"
artifact_name="stria"

usage() {
  cat <<EOF
Usage:
  scripts/build-homebrew-cask-release.sh [--dry-run] [target ...]

Targets:
  darwin-arm64  darwin-x64

Required environment for real builds:
  APPLE_SIGNING_IDENTITY  Developer ID Application identity for the executable.
  APPLE_ID                Apple ID email for notarization.
  APPLE_PASSWORD          Apple app-specific password for notarization.
  APPLE_TEAM_ID           Apple Developer Team ID for notarization.

Optional environment:
  RELEASE_VERSION       Override archive version used in archive names.
  CASK_RELEASE_DIR      Output directory. Defaults to dist/homebrew-cask.
  SWIFT_BIN             Swift executable. Defaults to Xcode's Swift toolchain on macOS, then PATH.
  SWIFT_DEVELOPER_DIR   Defaults to /Applications/Xcode.app/Contents/Developer.
  SWIFT_SDKROOT         Defaults to Xcode's macOS SDK path.
  NOTARYTOOL            Defaults to Xcode's notarytool.
  STAPLER               Defaults to Xcode's stapler.

Examples:
  scripts/build-homebrew-cask-release.sh --dry-run darwin-arm64 darwin-x64
  kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
    scripts/build-homebrew-cask-release.sh darwin-arm64 darwin-x64

This builder stages signed, notarized, and stapled macOS .dmg artifacts for a
Homebrew Cask. Each DMG holds Stria.app (the SwiftUI reader, executable
stria-app) with the stria CLI inside it at Contents/MacOS/stria, plus an
Applications link. The app is notarized and stapled before it goes into the
DMG, and the DMG is notarized and stapled as well. It does not publish
release assets, mutate a tap, or push commits.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    return 1
  fi
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    printf 'missing required environment variable: %s\n' "$1" >&2
    return 1
  fi
}

detect_target() {
  local kernel arch
  kernel="$(uname -s)"
  arch="$(uname -m)"

  case "$kernel:$arch" in
    Darwin:arm64) printf '%s\n' "darwin-arm64" ;;
    Darwin:x86_64) printf '%s\n' "darwin-x64" ;;
    *)
      printf 'unsupported Swift cask host platform: %s/%s\n' "$kernel" "$arch" >&2
      return 1
      ;;
  esac
}

validate_target() {
  case "$1" in
    darwin-arm64 | darwin-x64) ;;
    *)
      printf 'unsupported Swift cask target: %s\n' "$1" >&2
      printf 'Homebrew Cask DMGs are macOS-only.\n' >&2
      usage >&2
      return 1
      ;;
  esac
}

validate_version() {
  local version
  version="$1"

  if [[ "$version" == *..* || ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z][0-9A-Za-z.+-]*)?$ ]]; then
    printf 'unsafe cask version: %s\n' "$version" >&2
    printf 'expected archive-safe semver-like value without path separators or parent traversal\n' >&2
    return 1
  fi
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$repo_root" "$1" ;;
  esac
}

validate_release_dir() {
  local path part
  local -a parts
  path="$1"

  if [[ -z "$path" ]]; then
    printf 'unsafe cask release directory: empty path\n' >&2
    return 1
  fi

  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    if [[ "$part" == "." || "$part" == ".." ]]; then
      printf 'unsafe cask release directory: %s\n' "$path" >&2
      printf 'release directory must not contain . or .. path components\n' >&2
      return 1
    fi
  done
}

assert_child_path() {
  local root child
  root="${1%/}"
  child="$2"

  if [[ -z "$root" || "$root" == "/" || "$child" != "$root"/* ]]; then
    printf 'unsafe cask path outside release directory: %s\n' "$child" >&2
    return 1
  fi
}

swift_triple_for_target() {
  case "$1" in
    darwin-arm64) printf '%s\n' "arm64-apple-macosx" ;;
    darwin-x64) printf '%s\n' "x86_64-apple-macosx" ;;
  esac
}

install_prefix_for_target() {
  case "$1" in
    darwin-arm64) printf '%s\n' "/opt/homebrew" ;;
    darwin-x64) printf '%s\n' "/usr/local" ;;
  esac
}

write_sha256() {
  local file dir base
  file="$1"
  dir="$(dirname "$file")"
  base="$(basename "$file")"

  if command -v shasum >/dev/null 2>&1; then
    ( cd "$dir" && shasum -a 256 "$base" )
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$dir" && sha256sum "$base" )
    return
  fi

  printf 'missing checksum tool: expected shasum or sha256sum\n' >&2
  return 1
}

package_version() {
  if [[ -n "${RELEASE_VERSION:-}" ]]; then
    printf '%s\n' "$RELEASE_VERSION"
    return
  fi

  tr -d '[:space:]' < "$repo_root/VERSION"
}

swift_bin() {
  if [[ -n "${SWIFT_BIN:-}" ]]; then
    printf '%s\n' "$SWIFT_BIN"
    return
  fi
  if [[ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift ]]; then
    printf '%s\n' "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    return
  fi
  command -v swift
}

swift_release_bin_path() {
  local target swift_exe developer_dir sdkroot triple
  target="$1"
  swift_exe="$(swift_bin)"
  developer_dir="${SWIFT_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  sdkroot="${SWIFT_SDKROOT:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
  triple="$(swift_triple_for_target "$target")"

  (
    cd "$repo_root"
    DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" \
      "$swift_exe" build -c release --product "$product" --triple "$triple" >/dev/null
    DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" \
      "$swift_exe" build -c release --product "$app_product" --triple "$triple" >/dev/null
    DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" \
      "$swift_exe" build -c release --product "$product" --triple "$triple" --show-bin-path
  )
}

assert_codesigning_identity() {
  local identity
  identity="$1"
  security find-identity -v -p codesigning | grep -F -- "$identity" >/dev/null
}

print_plan() {
  local version target release_dir work_dir dmg_path app_dir triple install_prefix
  version="$1"
  target="$2"
  release_dir="$3"
  work_dir="$release_dir/work/$artifact_name-$version-$target"
  dmg_path="$release_dir/$artifact_name-$version-$target.dmg"
  app_dir="$work_dir/$app_name.app"
  triple="$(swift_triple_for_target "$target")"
  install_prefix="$(install_prefix_for_target "$target")"

  assert_child_path "$release_dir" "$work_dir"
  assert_child_path "$release_dir" "$dmg_path"

  printf 'Swift Homebrew Cask DMG plan\n'
  printf '  products: %s (CLI), %s (app)\n' "$product" "$app_product"
  printf '  target: %s\n' "$target"
  printf '  swift triple: %s\n' "$triple"
  printf '  cask install prefix: %s\n' "$install_prefix"
  printf '  app bundle: %s (%s %s)\n' "$app_dir" "$bundle_id" "$version"
  printf '  CLI inside app: %s/Contents/MacOS/%s\n' "$app_dir" "$product"
  printf '  notarized DMG: %s\n' "$dmg_path"
  printf '  checksum: %s.sha256\n' "$dmg_path"
  printf '  required Apple env: APPLE_SIGNING_IDENTITY, APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID\n'
  printf '  publish side effects: false\n'
}

write_info_plist() {
  local plist version
  plist="$1"
  version="$2"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$app_name</string>
  <key>CFBundleExecutable</key><string>$app_product</string>
  <key>CFBundleIconFile</key><string>$app_name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$app_name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright tacogips. MIT License.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>PDF Document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
  plutil -lint "$plist" >/dev/null
}

# Submits a file for notarization and fails unless Apple accepts it.
notarize() {
  local file notarytool output status
  file="$1"
  notarytool="$2"
  output="$("$notarytool" submit "$file" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait --output-format json)"
  status="$(printf '%s' "$output" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  if [[ "$status" != "Accepted" ]]; then
    printf 'notarization of %s ended with status %s\n' "$file" "${status:-unknown}" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf 'notarized %s\n' "$(basename "$file")"
}

build_target() {
  local version target release_dir work_dir dmg_path app_dir bin_path notarytool stapler app_zip
  version="$1"
  target="$2"
  release_dir="$3"
  work_dir="$release_dir/work/$artifact_name-$version-$target"
  dmg_path="$release_dir/$artifact_name-$version-$target.dmg"
  app_dir="$work_dir/$app_name.app"
  app_zip="$release_dir/work/$artifact_name-$version-$target-app.zip"
  notarytool="${NOTARYTOOL:-/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool}"
  stapler="${STAPLER:-/Applications/Xcode.app/Contents/Developer/usr/bin/stapler}"

  assert_child_path "$release_dir" "$work_dir"
  assert_child_path "$release_dir" "$dmg_path"
  assert_child_path "$release_dir" "$app_zip"

  require_env APPLE_SIGNING_IDENTITY
  require_env APPLE_ID
  require_env APPLE_PASSWORD
  require_env APPLE_TEAM_ID
  require_command codesign
  require_command ditto
  require_command hdiutil
  require_command plutil
  require_command security
  require_command spctl
  test -x "$notarytool"
  test -x "$stapler"
  test -f "$repo_root/Resources/$app_name.icns"
  assert_codesigning_identity "$APPLE_SIGNING_IDENTITY"

  rm -rf "$work_dir" "$dmg_path" "$dmg_path.sha256" "$app_zip"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

  bin_path="$(swift_release_bin_path "$target" | tail -n 1)"
  cp "$bin_path/$app_product" "$app_dir/Contents/MacOS/$app_product"
  cp "$bin_path/$product" "$app_dir/Contents/MacOS/$product"
  chmod 0755 "$app_dir/Contents/MacOS/$app_product" "$app_dir/Contents/MacOS/$product"
  cp "$repo_root/Resources/$app_name.icns" "$app_dir/Contents/Resources/$app_name.icns"
  printf 'APPL????' > "$app_dir/Contents/PkgInfo"
  write_info_plist "$app_dir/Contents/Info.plist" "$version"

  # Nested code first, then the bundle (no --deep).
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$app_dir/Contents/MacOS/$product"
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$app_dir"
  codesign --verify --strict --deep --verbose=2 "$app_dir"

  ditto -c -k --keepParent "$app_dir" "$app_zip"
  notarize "$app_zip" "$notarytool"
  "$stapler" staple "$app_dir"
  "$stapler" validate "$app_dir"
  spctl --assess --type execute --verbose=4 "$app_dir"
  rm -f "$app_zip"

  ln -s /Applications "$work_dir/Applications"
  hdiutil create -quiet -fs HFS+ -format UDZO -volname "$app_name" -srcfolder "$work_dir" "$dmg_path"
  codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$dmg_path"
  codesign --verify --strict --verbose=2 "$dmg_path"
  notarize "$dmg_path" "$notarytool"
  "$stapler" staple "$dmg_path"
  "$stapler" validate "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
  write_sha256 "$dmg_path" > "$dmg_path.sha256"

  printf 'built %s\n' "$dmg_path"
  cat "$dmg_path.sha256"
}

main() {
  local dry_run
  dry_run=false

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi

  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
    shift
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Homebrew Cask DMG builds must run on macOS.\n' >&2
    return 1
  fi

  local version release_dir
  version="$(package_version)"
  validate_version "$version"
  release_dir="$(absolute_path "${CASK_RELEASE_DIR:-dist/homebrew-cask}")"
  validate_release_dir "$release_dir"

  local -a targets
  if [[ "$#" -eq 0 ]]; then
    targets=("$(detect_target)")
  else
    targets=("$@")
  fi

  local target
  for target in "${targets[@]}"; do
    validate_target "$target"
    if [[ "$dry_run" == true ]]; then
      print_plan "$version" "$target" "$release_dir"
    else
      mkdir -p "$release_dir"
      build_target "$version" "$target" "$release_dir"
    fi
  done

  printf '\nRender a cask after all platform DMGs exist:\n'
  printf '  scripts/render-homebrew-cask.sh %s\n' "$version"
}

main "$@"
