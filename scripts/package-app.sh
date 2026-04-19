#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
output_root="${2:-}"

case "$configuration" in
  debug|release)
    ;;
  *)
    echo "Usage: scripts/package-app.sh [debug|release] [output-directory]" >&2
    exit 64
    ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [[ -z "$output_root" ]]; then
  output_root="$repo_root/.build/app/$configuration"
fi

app_name="MacProxyUI"
helper_name="AskpassHelper"
bundle_path="$output_root/$app_name.app"
contents_path="$bundle_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
info_plist_template="$repo_root/Packaging/MacProxyUI-Info.plist"
icon_generator="$repo_root/scripts/generate-app-icon.swift"

bundle_identifier="${MACPROXYUI_BUNDLE_ID:-com.macproxyui.app}"
bundle_version="${MACPROXYUI_VERSION:-0.1.0}"
bundle_build="${MACPROXYUI_BUILD:-1}"
bundle_category="${MACPROXYUI_CATEGORY:-public.app-category.developer-tools}"
copyright_notice="${MACPROXYUI_COPYRIGHT:-Copyright 2026 MacProxyUI}"

create_iconset() {
  local base_png="$1"
  local iconset_path="$2"

  mkdir -p "$iconset_path"

  sips -s format png -z 16 16 "$base_png" --out "$iconset_path/icon_16x16.png" >/dev/null
  sips -s format png -z 32 32 "$base_png" --out "$iconset_path/icon_16x16@2x.png" >/dev/null
  sips -s format png -z 32 32 "$base_png" --out "$iconset_path/icon_32x32.png" >/dev/null
  sips -s format png -z 64 64 "$base_png" --out "$iconset_path/icon_32x32@2x.png" >/dev/null
  sips -s format png -z 128 128 "$base_png" --out "$iconset_path/icon_128x128.png" >/dev/null
  sips -s format png -z 256 256 "$base_png" --out "$iconset_path/icon_128x128@2x.png" >/dev/null
  sips -s format png -z 256 256 "$base_png" --out "$iconset_path/icon_256x256.png" >/dev/null
  sips -s format png -z 512 512 "$base_png" --out "$iconset_path/icon_256x256@2x.png" >/dev/null
  sips -s format png -z 512 512 "$base_png" --out "$iconset_path/icon_512x512.png" >/dev/null
  ditto "$base_png" "$iconset_path/icon_512x512@2x.png"
}

echo "Building $app_name ($configuration)..."
cd "$repo_root"
swift build -c "$configuration" --product "$helper_name"
swift build -c "$configuration" --product "$app_name"

bin_path="$(swift build -c "$configuration" --show-bin-path)"
main_binary="$bin_path/$app_name"
helper_binary="$bin_path/$helper_name"

if [[ ! -x "$main_binary" ]]; then
  echo "Missing built binary: $main_binary" >&2
  exit 1
fi

if [[ ! -x "$helper_binary" ]]; then
  echo "Missing built helper: $helper_binary" >&2
  exit 1
fi

rm -rf "$bundle_path"
mkdir -p "$macos_path" "$resources_path"

cp "$info_plist_template" "$contents_path/Info.plist"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

base_icon_png="$tmp_dir/AppIcon.png"
iconset_path="$tmp_dir/AppIcon.iconset"
icon_icns="$resources_path/AppIcon.icns"

swift "$icon_generator" "$base_icon_png"
create_iconset "$base_icon_png" "$iconset_path"
iconutil -c icns "$iconset_path" -o "$icon_icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $bundle_version" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundle_build" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleGetInfoString $app_name $bundle_version" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType $bundle_category" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright $copyright_notice" "$contents_path/Info.plist"

ditto "$main_binary" "$macos_path/$app_name"
ditto "$helper_binary" "$macos_path/$helper_name"
chmod 755 "$macos_path/$app_name" "$macos_path/$helper_name"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$macos_path/$helper_name"
  codesign --force --sign - --deep "$bundle_path"
fi

echo
echo "Created app bundle:"
echo "  $bundle_path"
echo
echo "Bundle identifier: $bundle_identifier"
echo "Version: $bundle_version ($bundle_build)"
echo
echo "Run it with:"
echo "  open \"$bundle_path\""
