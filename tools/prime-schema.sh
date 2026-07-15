#!/bin/bash
# Materialise the FULL CloudKit record-type set in the DEVELOPMENT environment.
#
# Why: Production CloudKit can't create record types or fields at runtime, so the
# schema must be built in Development and deployed. But a record type only exists
# once a record of that type is saved — which is how CD_Version came to exist in
# NEITHER environment, leaving the first named version silently unsyncable.
#
# Safety: runs a Debug (Development-CloudKit) build against a THROWAWAY store, so
# the real library and its mirroring metadata are never touched. Pointing a dev
# build at the production store would reset that metadata and risk re-uploading
# everything as duplicates.
#
# After this: CloudKit Console → Development → Deploy Schema Changes to Production.
set -e
cd "$(dirname "$0")/.."
./gen.sh
xcodebuild -project LaReplique.xcodeproj -scheme LaReplique \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath .build build
APP=".build/Build/Products/Debug/LaReplique.app/Contents/MacOS/LaReplique"
echo "→ priming (throwaway store, Development CloudKit)…"
LR_SCHEMA_PRIME=1 LR_PRIME_TAG="$(date +%s)" "$APP" &
PID=$!
sleep 45   # let CloudKit export the new types
kill $PID 2>/dev/null || true
echo "→ done. Now: CloudKit Console → Development → Record Types → confirm CD_Version,"
echo "  then Deploy Schema Changes to Production."
