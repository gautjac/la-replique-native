#!/bin/bash
# Build + run the macOS app (dev-signed).
set -e
cd "$(dirname "$0")"
./gen.sh
xcodebuild -project LaReplique.xcodeproj -scheme LaReplique \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath .build build
open ".build/Build/Products/Debug/LaReplique.app"
