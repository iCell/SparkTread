#!/bin/sh
# Single non-interactive gate (§18.3). Runs everything M0 provides today;
# content validation, replay goldens, and the boot-to-training smoke test are
# appended here as their milestones land.
set -eu
cd "$(dirname "$0")/.."

sh Scripts/check-architecture.sh
swift test
xcodegen generate
xcodebuild test \
    -project ProjectGoldenEagle.xcodeproj \
    -scheme ProjectGoldenEagle \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath .build/DerivedData
