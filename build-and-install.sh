#!/bin/bash
# Build HackerTube and install it on your Apple TV.
#
#   ./build-and-install.sh <TEAM_ID> <DEVICE_ID> [BUNDLE_ID]
#
# TEAM_ID    your Apple developer team (Xcode > Settings > Accounts; a free Apple ID works)
# DEVICE_ID  your paired Apple TV:  xcrun devicectl list devices
# BUNDLE_ID  optional, must be unique to you (default: com.<TEAM_ID>.hackertube)
set -euo pipefail
cd "$(dirname "$0")"
TEAM="${1:?usage: ./build-and-install.sh <TEAM_ID> <DEVICE_ID> [BUNDLE_ID]}"
DEVICE="${2:?usage: ./build-and-install.sh <TEAM_ID> <DEVICE_ID> [BUNDLE_ID]}"
BUNDLE="${3:-com.$(echo "$TEAM" | tr 'A-Z' 'a-z').hackertube}"
mkdir -p logs
command -v xcodegen >/dev/null && xcodegen generate --quiet
xcodebuild -project HackerTube.xcodeproj -scheme HackerTube -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" -allowProvisioningUpdates build > logs/build.log 2>&1 \
  || { grep -E "error:" logs/build.log | head -20; echo "Build failed. See logs/build.log"; exit 1; }
echo "Built $BUNDLE"
xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Release-appletvos/HackerTube.app
