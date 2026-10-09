#!/bin/sh
# Point fastlane at the captured media without copying 240 MB into the repo.
# AppStoreMedia/<app locale>/ is gitignored and regenerable (capture.py +
# compose.py); fastlane wants <path>/<App Store locale>/, so these are
# symlinks and the two trees can never drift.
set -e
cd "$(dirname "$0")/../.."
rm -rf fastlane/screenshots fastlane/previews
# app locale -> App Store Connect locale
for pair in en:en-US es:es-ES ja:ja ko:ko zh-Hans:zh-Hans zh-Hant:zh-Hant; do
  app=${pair%%:*}
  asc=${pair##*:}
  [ -d "AppStoreMedia/$app/iphone" ] || { echo "missing AppStoreMedia/$app/iphone"; exit 1; }
  mkdir -p fastlane/screenshots fastlane/previews/"$asc"
  ln -s ../../AppStoreMedia/"$app"/iphone fastlane/screenshots/"$asc"
  # deliver reads the device from the FILE NAME: it must contain a PreviewType
  # token. IPHONE_67 is the 6.9" slot, whose accepted resolution is 886x1920 --
  # what compose.py renders. A name without the token is silently skipped.
  ln -s ../../../AppStoreMedia/"$app"/preview_iphone.mp4 \
        fastlane/previews/"$asc"/preview_IPHONE_67.mp4
done
echo "linked:"
ls -l fastlane/screenshots fastlane/previews/* | grep -E '^l|:$'
