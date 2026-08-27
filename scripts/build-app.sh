#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
configuration="${1:-debug}"

case "$configuration" in
  debug|release) ;;
  *)
    echo "Usage: scripts/build-app.sh [debug|release]" >&2
    exit 2
    ;;
esac

app_dir="$repo_root/Build/PersonalPi.app"
contents_dir="$app_dir/Contents"
binary_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/private/tmp/personal-pi-modulecache}"

cd "$repo_root"
swift build --configuration "$configuration"
bin_dir="$(swift build --configuration "$configuration" --show-bin-path)"

mkdir -p "$binary_dir" "$resources_dir"
cp "$repo_root/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$bin_dir/PersonalPi" "$binary_dir/PersonalPi"
chmod 755 "$binary_dir/PersonalPi"

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
