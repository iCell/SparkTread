#!/bin/zsh
set -euo pipefail
PIXEL_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PIXEL_BUILD=$(mktemp -d /private/tmp/sparktread-pixel-verify.XXXXXX)
swiftc -swift-version 6 -module-cache-path "$PIXEL_BUILD/cache" \
  "$PIXEL_ROOT/Runtime/PixelArt.swift" "$PIXEL_ROOT/Runtime/PixelPresentation.swift" \
  "$PIXEL_ROOT/Tools/VerifyPixel.swift" -o "$PIXEL_BUILD/verify"
swiftc -swift-version 6 -module-cache-path "$PIXEL_BUILD/cache" \
  "$PIXEL_ROOT/Runtime/PixelArt.swift" "$PIXEL_ROOT/Runtime/PixelPresentation.swift" \
  "$PIXEL_ROOT/Tools/RenderPixel.swift" -o "$PIXEL_BUILD/render"
"$PIXEL_BUILD/verify" "$PIXEL_ROOT"
for device in compact phone tablet; do
  for phase in 0 1 2 3; do "$PIXEL_BUILD/render" "$PIXEL_ROOT" arena "$device" "$phase"; done
done
for phase in 0 1 2 3; do "$PIXEL_BUILD/render" "$PIXEL_ROOT" roster phone "$phase"; done
for mode in directions pause victory defeat settings selection tutorial tutorial_move tutorial_normal tutorial_special tutorial_equipment tutorial_base; do
  "$PIXEL_BUILD/render" "$PIXEL_ROOT" "$mode" phone 0
done
for phase in {0..23}; do "$PIXEL_BUILD/render" "$PIXEL_ROOT" battle phone "$phase"; done
print "Current exports verified. Temporary compiler output: $PIXEL_BUILD"
