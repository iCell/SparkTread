#!/bin/sh
# Single non-interactive gate (§18.3). Runs everything M0 provides today;
# replay goldens and the boot-to-training smoke test are appended here as
# their milestones land.
set -eu
cd "$(dirname "$0")/.."

sh Scripts/check-architecture.sh
swift run content-validator Content
swift test
xcodegen generate
xcodebuild test \
    -project SparkTread.xcodeproj \
    -scheme SparkTread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath .build/DerivedData
