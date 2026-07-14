#!/bin/bash
# Build both platforms + run tests. Catches macOS-only issues an iOS-only build
# misses (e.g. .bottomBar / .keyboard toolbar placements), plus — via the GA
# Xcode preflight — Swift 6 strict-concurrency errors that the BETA Xcode's
# looser region analysis lets through but Xcode Cloud (GA toolchain) fails on.
set -e
cd "$(dirname "$0")"
./gen.sh >/dev/null
SIM_ID=$(xcrun simctl list devices available | grep -oE '[0-9A-F-]{36}' | head -1)

# GA-Xcode preflight — compile both platforms with the same toolchain Xcode Cloud
# uses, so data-race / concurrency errors surface here, not in the cloud.
GA=/Applications/Xcode.app/Contents/Developer
if [ -d "$GA" ]; then
  echo "▸ GA-Xcode preflight (iOS)";   DEVELOPER_DIR=$GA xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'generic/platform=iOS'   -derivedDataPath .build-ga CODE_SIGNING_ALLOWED=NO -quiet
  echo "▸ GA-Xcode preflight (macOS)"; DEVELOPER_DIR=$GA xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'platform=macOS'          -derivedDataPath .build-ga CODE_SIGNING_ALLOWED=NO -quiet
else
  echo "⚠︎ GA Xcode not found at $GA — skipping the cloud-toolchain preflight."
fi

echo "▸ iOS build";   xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'generic/platform=iOS Simulator' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "▸ macOS build"; xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique -destination 'platform=macOS' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "▸ tests";       xcodebuild test  -project LaReplique.xcodeproj -scheme LaReplique -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath .build CODE_SIGNING_ALLOWED=NO -quiet
echo "✓ all green (GA preflight + iOS + macOS + tests)"
