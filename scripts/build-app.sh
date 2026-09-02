#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
configuration="${1:-debug}"

case "$configuration" in
  debug)
    xcode_configuration="Debug"
    ;;
  release)
    xcode_configuration="Release"
    ;;
  *)
    echo "Usage: scripts/build-app.sh [debug|release]" >&2
    exit 2
    ;;
esac

app_dir="$repo_root/Build/PersonalPi.app"
derived_data_dir="$repo_root/.build/xcode-derived"
built_app="$derived_data_dir/Build/Products/$xcode_configuration/PersonalPi.app"
host_arch="$(uname -m)"

cd "$repo_root"
xcodebuild \
  -project "$repo_root/PersonalPi.xcodeproj" \
  -scheme PersonalPi \
  -configuration "$xcode_configuration" \
  -destination "platform=macOS,arch=$host_arch" \
  -derivedDataPath "$derived_data_dir" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$built_app" ]]; then
  echo "Xcode build did not produce $built_app" >&2
  exit 1
fi

mkdir -p "$repo_root/Build"
rm -rf "$app_dir"
ditto "$built_app" "$app_dir"

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
