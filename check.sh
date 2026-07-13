#!/bin/bash
# Build both platforms + run tests. Catches macOS-only issues that an
# iOS-only build misses (e.g. .bottomBar / .keyboard toolbar placements).
set -e
cd "$(dirname "$0")"
./gen.sh >/dev/null
SIM_ID=$(xcrun simctl list devices available | grep -oE '[0-9A-F-]{36}' | head -1)
echo "▸ iOS build";   xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'generic/platform=iOS Simulator' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "▸ macOS build"; xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'platform=macOS' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "▸ tests";       xcodebuild test  -project LaReplique.xcodeproj -scheme LaReplique -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "✓ all green (iOS + macOS + tests)"
