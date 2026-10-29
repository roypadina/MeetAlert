#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64  # universal
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
APP=build/MeetAlert.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # macOS 14/15 icon (CFBundleIconFile)
# macOS 26+ icon with Dark/Clear/Tinted looks, once an Icon Composer AppIcon.icon exists (needs Xcode 26+ actool).
if [ -d AppIcon.icon ]; then
  xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$APP/icon-partial.plist" >/dev/null
  rm -f "$APP/icon-partial.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
fi
cp "$BIN/MeetAlert" "$APP/Contents/MacOS/MeetAlert"
# Stable identity (when in the keychain) keeps Calendar/notification grants across updates; ad-hoc otherwise.
# No hardened runtime: it was never enabled, and it would need the calendar entitlement.
ID="${MEETALERT_SIGN_IDENTITY:-}"
if [ -z "$ID" ] && security find-identity -v -p codesigning | grep -q "KeyLayoutSwitcher Dev"; then
  ID="KeyLayoutSwitcher Dev"
fi
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" --identifier com.roy.meetalert "$APP"
  codesign --verify --deep --strict "$APP"
  echo "signed with: $ID"
else
  codesign --force --sign - --identifier com.roy.meetalert "$APP"
  echo "stable signing identity not found: ad-hoc signed"
fi
echo "built $APP"
