#!/bin/sh
# Build, sign (free provisioning, team HFA66PX9R5), install, and launch on
# Xiaoyu's iPhone. Requires the device paired with Developer Mode on and the
# keychain partition list authorized for CLI codesign.
set -eu
cd "$(dirname "$0")/.."

DEVICE_ID="1C09422B-F9E4-5640-AF18-FE85688F6740"

xcodegen generate
xcodebuild build \
    -project SparkTread.xcodeproj -scheme SparkTread \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -derivedDataPath .build/DerivedData \
    -allowProvisioningUpdates -quiet
xcrun devicectl device install app --device "$DEVICE_ID" \
    .build/DerivedData/Build/Products/Debug-iphoneos/SparkTread.app
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" io.icell.sparktread
