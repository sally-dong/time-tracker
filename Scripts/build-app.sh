#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --product TimeTracker
APP="$PWD/build/Time Tracker.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TimeTracker "$APP/Contents/MacOS/TimeTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/MakeIcon.swift "$PWD/build/AppIcon.iconset"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
