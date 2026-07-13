#!/bin/bash
# Generate the Xcode project from project.yml
set -e
cd "$(dirname "$0")"
/opt/homebrew/bin/xcodegen generate
echo "Generated LaReplique.xcodeproj"
