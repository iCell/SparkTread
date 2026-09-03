#!/bin/sh
# M0 architecture check (§14.1, D-017): detects forbidden dependencies.
# - GameCore imports nothing (not even Foundation).
# - GameApplication imports only GameCore (plus Foundation/Testing helpers later
#   would require an ADR; today it is GameCore only).
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
bad_app=$(echo "$app_imports" | grep -vE '^(GameCore)?$' || true)
if [ -n "$bad_app" ]; then
    echo "FORBIDDEN: Sources/GameApplication may only import GameCore; found:"
    echo "$bad_app"
    fail=1
fi

adapter_bad=$(grep -rl 'import AppleAdapters' Sources/GameCore Sources/GameApplication --include='*.swift' || true)
if [ -n "$adapter_bad" ]; then
    echo "FORBIDDEN: inner layers import AppleAdapters:"
    echo "$adapter_bad"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "Architecture check passed."
fi
exit "$fail"
