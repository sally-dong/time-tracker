#!/bin/zsh
# Builds a universal (Apple silicon + Intel) app and packages it as a
# drag-to-Applications disk image in build/release/.
#
# Without signing credentials the app is ad-hoc signed: it runs, but other
# Macs will block it until the user approves it in System Settings.
# For a download that opens normally, set both variables (see README):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<keychain profile created with `xcrun notarytool store-credentials`>
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$NOTARY_PROFILE" && -z "$DEVELOPER_ID" ]]; then
    print -u2 "NOTARY_PROFILE requires DEVELOPER_ID."; exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
OUT="$PWD/build/release"
APP="$OUT/Time Tracker.app"
DMG="$OUT/TimeTracker-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security \
    -c release --arch arm64 --arch x86_64 --product TimeTracker
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TimeTracker" "$APP/Contents/MacOS/TimeTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/MakeIcon.swift "$OUT/AppIcon.iconset"
cp "$OUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
[[ -f "$OUT/AppIcon.assets/Assets.car" ]] && cp "$OUT/AppIcon.assets/Assets.car" "$APP/Contents/Resources/Assets.car"
rm -rf "$OUT/AppIcon.iconset" "$OUT/AppIcon.icns" "$OUT/AppIcon.assets"

if [[ -n "$DEVELOPER_ID" ]]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Time Tracker.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Time Tracker" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ -n "$DEVELOPER_ID" ]]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

printf 'Built %s\n' "$DMG"
[[ -n "$NOTARY_PROFILE" ]] || print "Not notarized: other Macs will ask users to approve it in System Settings > Privacy & Security."
