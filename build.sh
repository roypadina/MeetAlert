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
# Sparkle (in-app updates): the framework SwiftPM puts next to the binary; ditto keeps its symlinks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Stable identity (when in the keychain) keeps Calendar/notification grants across updates; ad-hoc otherwise.
# No hardened runtime: it was never enabled, and it would need the calendar entitlement.
ID="${MEETALERT_SIGN_IDENTITY:-}"
if [ -z "$ID" ] && security find-identity -v -p codesigning | grep -q "KeyLayoutSwitcher Dev"; then
  ID="KeyLayoutSwitcher Dev"
fi
SIGN="${ID:--}"
# Inside-out: Sparkle's helpers and framework, then the app.
find "$APP/Contents" -depth \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' -o -name '*.dylib' \
  -o \( -name Autoupdate -type f \) \) | while read -r f; do
  codesign --force --preserve-metadata=identifier,entitlements,flags --sign "$SIGN" "$f"
done
codesign --force --sign "$SIGN" --identifier com.roy.meetalert "$APP"
codesign --verify --deep --strict "$APP"
if [ -n "$ID" ]; then echo "signed with: $ID"; else echo "stable signing identity not found: ad-hoc signed"; fi
echo "built $APP"

# RELEASE=1: zip for GitHub Releases + the cask, and the Sparkle feed (uploaded next to the zip) when the
# maintainer's key matching SUPublicEDKey is in the keychain; any other key makes a feed every copy refuses.
if [ -n "${RELEASE:-}" ]; then
  rm -f build/MeetAlert.zip
  ditto -c -k --keepParent "$APP" build/MeetAlert.zip
  echo "SHA-256: $(shasum -a 256 build/MeetAlert.zip | cut -d' ' -f1)"
  SPARKLE=.build/artifacts/sparkle/Sparkle/bin
  if [ "$("$SPARKLE/generate_keys" -p 2>/dev/null || true)" = "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)" ]; then
    VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
    D=$(mktemp -d)
    cp build/MeetAlert.zip "$D/"
    # This version's CHANGELOG section becomes the update prompt's release notes.
    awk -v v="## [$VER]" 'index($0, v) == 1 {f=1; next} /^## \[/ {f=0} f' CHANGELOG.md > "$D/MeetAlert.md"
    rm -f build/appcast.xml  # generate_appcast merges into an existing file
    "$SPARKLE/generate_appcast" --embed-release-notes \
      --download-url-prefix "https://github.com/roypadina/MeetAlert/releases/download/v$VER/" \
      -o build/appcast.xml "$D"
    rm -rf "$D"
    echo build/appcast.xml
  else
    echo "Sparkle signing key (matching SUPublicEDKey) not in the keychain: no appcast.xml"
  fi
fi
