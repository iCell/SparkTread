#!/bin/sh
# M0 architecture check (§14.1, D-017): detects forbidden dependencies.
# - GameCore imports nothing (not even Foundation).
# - GameApplication may import GameCore and Foundation (content-loading use
#   cases live here, §14 — JSON decoding needs Foundation), but never a
#   presentation/platform framework (SpriteKit/SwiftUI/UIKit/GameController…).
# It also bans one presentation call that is silently wrong with the
# delivery's compiled atlases (see below).
# Run from the repository root: sh Scripts/check-architecture.sh
set -eu

fail=0

core_imports=$(grep -rhE '^[[:space:]]*(@[A-Za-z_() ]+[[:space:]]+)?import[[:space:]]' Sources/GameCore --include='*.swift' || true)
if [ -n "$core_imports" ]; then
    echo "FORBIDDEN: Sources/GameCore must import nothing (D-017):"
    echo "$core_imports"
    fail=1
fi

app_imports=$(grep -rhE '^[[:space:]]*(@[A-Za-z_() ]+[[:space:]]+)?import[[:space:]]' Sources/GameApplication --include='*.swift' \
    | sed -E 's/^[[:space:]]*(@[A-Za-z_() ]+[[:space:]]+)?import[[:space:]]+//' | sort -u || true)
# Allowed: GameCore, Foundation. Forbidden: any presentation/platform module.
bad_app=$(echo "$app_imports" | grep -vE '^(GameCore|Foundation)?$' || true)
if [ -n "$bad_app" ]; then
    echo "FORBIDDEN: Sources/GameApplication may only import GameCore or Foundation; found:"
    echo "$bad_app"
    fail=1
fi

adapter_bad=$(grep -rl 'import AppleAdapters' Sources/GameCore Sources/GameApplication --include='*.swift' || true)
if [ -n "$adapter_bad" ]; then
    echo "FORBIDDEN: inner layers import AppleAdapters:"
    echo "$adapter_bad"
    fail=1
fi

# A sub-rect of an atlas-backed texture resolves against the PACKED PAGE,
# not the sprite: in the app this drew a strip of the frozen/floodplain/
# citadel ground sprites down the arena's right edge, while the tests — which
# load the delivery's loose files, where each texture is its own image —
# stayed green. Clip the CGImage instead (MovementLabScene.clippedGroundTexture).
# (Comment lines are skipped so the explanation above may name the call.)
subrect=$(grep -rn 'SKTexture(rect' Sources --include='*.swift' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)
if [ -n "$subrect" ]; then
    echo "FORBIDDEN: SKTexture(rect:in:) samples the packed atlas page — crop the CGImage instead:"
    echo "$subrect"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "Architecture check passed."
fi
exit "$fail"
