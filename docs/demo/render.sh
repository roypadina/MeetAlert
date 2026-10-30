#!/bin/bash
# Regenerates the MeetAlert demo from scratch: compile the real AlertContent view + kit + scene, render frames offscreen
# (no window is ever shown, nothing is clicked or captured), encode. One command: ./render.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="${KIT:-$HERE}"; [ -f "$KIT/DemoKit.swift" ] || KIT="$HERE/../kit"          # repo: kit is vendored next to this file
APP="${APP_SRC:-$HERE/../../Sources/MeetAlert}"                                 # repo: docs/demo -> Sources/MeetAlert
GIF="${GIF:-$HERE/../demo.gif}"                                                 # repo: docs/demo.gif
BUILD="${BUILD:-${TMPDIR:-/tmp}/meetalert-demo}"                                    # never inside the repo (421 MB of frames)
mkdir -p "$BUILD"
swiftc -swift-version 5 -parse-as-library -O -o "$BUILD/demo" \
  "$KIT/DemoKit.swift" "$HERE/stubs.swift" "$HERE/scene.swift" "$APP/AlertPanel.swift" "$APP/Theme.swift"
rm -rf "$BUILD/frames"
"$BUILD/demo" "$BUILD/frames" 30 -AppleLocale en_US -AppleLanguages "(en)"      # en_US: "9:46 AM", like the menu text
"$KIT/encode.sh" "$BUILD/frames" "$GIF" ${MP4:+"$MP4"} ${WEBP:+"$WEBP"} ${POSTER:+"$POSTER"}
rm -rf "$BUILD/frames"                                                            # ~400 MB of PNGs; only after a successful encode (set -e)
