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
  -derivedDataPath .build -allowProvisioningUpdates build
APP=".build/Build/Products/Debug/LaReplique.app"
LOG="$(mktemp -t lr-prime)"
echo "→ priming (throwaway store, Development CloudKit)…"
# Through LaunchServices, NOT the bare binary: launched from a shell the app gets
# no window (so nothing runs) and CloudKit's background scheduler refuses its tasks.
open -n --env LR_SCHEMA_PRIME=1 --env LR_PRIME_TAG="$(date +%s)" --stderr "$LOG" --stdout "$LOG" "$APP"
for _ in $(seq 1 30); do grep -q "cleaned up" "$LOG" 2>/dev/null && break; sleep 3; done
sleep 20   # let the private-database export finish too
pkill -f "Debug/LaReplique.app/Contents/MacOS/LaReplique" 2>/dev/null || true
echo "→ done. What the run reported:"
grep -E "SCHEMA PRIME" "$LOG" | sed 's/^.*\[LaReplique\]/  [LaReplique]/'
echo "→ Now, in the CloudKit Console (Development): confirm the record types CD_Version AND PlayComment,"
echo "  follow docs/NOTES.md for the PlayComment security roles, then Deploy Schema Changes to Production."
