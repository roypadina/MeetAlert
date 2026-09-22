#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release
APP=build/MeetAlert.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/MeetAlert "$APP/Contents/MacOS/MeetAlert"
codesign --force --sign - --identifier com.roy.meetalert "$APP"
echo "built $APP"
