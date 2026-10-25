#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
./scripts/swift-local.sh build -c "$configuration"
binary_dir="$(./scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
bundle="$PWD/build/ActionsWatcher.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/ActionsWatcher" "$bundle/Contents/MacOS/ActionsWatcher"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/build"
cp build/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"

# Local builds use ad-hoc signing. Set SIGN_IDENTITY to a Developer ID for distribution.
codesign --force --sign "${SIGN_IDENTITY:--}" "$bundle"
printf '\nApp lista: %s\n' "$bundle"
