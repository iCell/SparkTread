#!/bin/sh
# Presentation smoke test (PI, rounds 20–21): the SKView must actually
# present the PLAYFIELD — a bug class no unit test sees (on 2026-09-10 the
# HUD kept updating over a blank SKView). Cold-launches the app on the
# iPhone 17 simulator, waits past startup and the intro with a bounded
# retry, and requires evidence of the gameplay surface — terrain-colour
# occupancy in a region that excludes the HUD, the touch controls and the
# system overlays — for the stage and for the intro-free lab. Contrast
# alone is not evidence: the intro card and the results overlay have
# plenty (R21-01). Every required step propagates failure (R21-02).
#
#   sh Scripts/smoke-render.sh            # the real check (simulator)
#   sh Scripts/smoke-render.sh selftest   # classifier + failure-path tests, no simulator
#
# Needs ffmpeg for the pixel statistics: missing locally → skipped with a
# notice; missing under CI (CI=true) → failure, so the guard cannot be
# silently absent from a green gate.
set -eu
cd "$(dirname "$0")/.."
if ! command -v ffmpeg > /dev/null 2>&1; then
    if [ "${CI:-}" != "" ]; then echo "smoke-render: ffmpeg is required in CI"; exit 1; fi
    echo "smoke-render: ffmpeg not installed — skipped"; exit 0
fi
SIMCTL="${SMOKE_SIMCTL:-xcrun simctl}"
FFMPEG="${SMOKE_FFMPEG:-ffmpeg}"
device="${SMOKE_DEVICE:-iPhone 17}"
derived="${DERIVED_DATA:-.build/DerivedData}"
out="${SMOKE_OUT:-.build/smoke}"
mkdir -p "$out"

# Gameplay-surface predicate on the central 60 % × 50 % of the surface:
# ≥ 20 % frontier ground pixels (≈ 200,182,146 ± 24) and ≥ 2 % brick
# pixels (≈ 192,120,72 ± 28). Prints "playfield ground=.. brick=.." or
# "not-playfield ground=.. brick=..". A missing/unreadable image is an error.
classify() {
    [ -s "$1" ] || { echo "error: no image"; return 1; }
    # Decode to a file with a CHECKED decoder status (R22-01): a pipeline
    # would report only the classifier's status, and a decoder that fails
    # after emitting plausible pixels must not be accepted.
    raw="${TMPDIR:-/tmp}/smoke-crop-$$.rgb"
    if ! "$FFMPEG" -loglevel error -y -i "$1" -vf "crop=iw*0.6:ih*0.5:iw*0.2:ih*0.25" -f rawvideo -pix_fmt rgb24 "$raw"; then
        rm -f "$raw"; echo "error: decoder failed"; return 1
    fi
    verdict=$(python3 -c '
import sys
d = open(sys.argv[1], "rb").read(); n = len(d) // 3
if n < 1000: print("error: empty crop"); sys.exit(1)
ground = brick = 0
for i in range(n):
    r, g, b = d[3*i], d[3*i+1], d[3*i+2]
    if abs(r-200) <= 24 and abs(g-182) <= 24 and abs(b-146) <= 24: ground += 1
    elif abs(r-192) <= 28 and abs(g-120) <= 28 and abs(b-72) <= 28: brick += 1
gp, bp = 100.0 * ground / n, 100.0 * brick / n
ok = gp >= 20 and bp >= 2
print(("playfield" if ok else "not-playfield") + " ground=%.1f%% brick=%.1f%%" % (gp, bp))
' "$raw") || { rm -f "$raw"; echo "error: classifier failed"; return 1; }
    rm -f "$raw"
    echo "$verdict"
}

# Average luma of an image (ffmpeg signalstats), for fixture assertions.
luma() {
    "$FFMPEG" -loglevel info -i "$1" -vf "signalstats,metadata=print" -f null - 2>&1 \
        | awk -F= '/lavfi.signalstats.YAVG=/ {v=$2} END { print (v == "" ? -1 : int(v)) }'
}

check() { # name, env-var-or-empty, settle-seconds
    name=$1; env=$2; settle=$3
    $SIMCTL terminate "$device" io.icell.sparktread > /dev/null 2>&1 || true   # best effort
    if [ -n "$env" ]; then env "SIMCTL_CHILD_$env=1" $SIMCTL launch "$device" io.icell.sparktread > /dev/null \
        || { echo "smoke-render: FAILED — $name did not launch"; return 1; }
    else $SIMCTL launch "$device" io.icell.sparktread > /dev/null \
        || { echo "smoke-render: FAILED — $name did not launch"; return 1; }
    fi
    sleep "$settle"
    attempt=0; verdict=""
    while [ $attempt -lt 6 ]; do
        shot="$out/$name-$attempt.png"
        rm -f "$shot"
        $SIMCTL io "$device" screenshot "$shot" > /dev/null 2>&1 \
            || { echo "smoke-render: FAILED — $name screenshot $attempt could not be captured"; return 1; }
        [ -s "$shot" ] || { echo "smoke-render: FAILED — $name screenshot $attempt is empty"; return 1; }
        verdict=$(classify "$shot") || { echo "smoke-render: FAILED — $name classifier error: $verdict"; return 1; }
        case "$verdict" in
            playfield*) echo "smoke-render: $name renders ($verdict)"; rm -f "$shot"; return 0 ;;
        esac
        attempt=$((attempt + 1)); sleep 1.5
    done
    echo "smoke-render: FAILED — $name never showed the playfield ($verdict); see $shot"
    return 1
}

selftest() {
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    status=0
    # Synthetic positive: ground canvas with brick blocks and a steel border.
    ffmpeg -loglevel error -y -f lavfi -i "color=c=0xC8B692:s=1206x2622:d=1" -frames:v 1 \
        -vf "drawbox=x=100:y=400:w=300:h=120:c=0xC07848:t=fill,drawbox=x=700:y=900:w=300:h=120:c=0xC07848:t=fill,drawbox=x=300:y=1400:w=400:h=200:c=0xC07848:t=fill,drawbox=x=0:y=0:w=1206:h=40:c=0x6E8291:t=fill" "$tmp/positive.png"
    # Negatives: the intro card (black with a yellow title block), a flat
    # field, and the results overlay (the positive darkened by 82 %).
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1206x2622:d=1" -frames:v 1 \
        -vf "drawbox=x=450:y=1100:w=300:h=500:c=0xFFCC00:t=fill" "$tmp/card.png"
    ffmpeg -loglevel error -y -f lavfi -i "color=c=0xBBBBBB:s=1206x2622:d=1" -frames:v 1 "$tmp/flat.png"
    # Results overlay: the field darkened to 18 % (OUTPUT maxima, R22-02)
    # with a light title block and a bordered table block over it.
    ffmpeg -loglevel error -y -i "$tmp/positive.png" \
        -vf "colorlevels=romax=0.18:gomax=0.18:bomax=0.18,drawbox=x=400:y=300:w=400:h=90:c=0xFFCC00:t=fill,drawbox=x=350:y=900:w=500:h=700:c=0xFFCC00:t=6" "$tmp/results.png"
    src=$(luma "$tmp/positive.png"); dark=$(luma "$tmp/results.png")
    if [ "$dark" -lt "$src" ] && [ "$dark" -lt 90 ]; then echo "selftest: results fixture is darker than its source (YAVG $src → $dark)"
    else echo "selftest: FAILED — results fixture is not darker (YAVG $src → $dark)"; status=1; fi
    for img in positive; do v=$(classify "$tmp/$img.png"); case "$v" in playfield*) echo "selftest: $img → $v";; *) echo "selftest: FAILED — $img classified as $v"; status=1;; esac; done
    for img in card flat results; do v=$(classify "$tmp/$img.png"); case "$v" in not-playfield*) echo "selftest: $img → $v";; *) echo "selftest: FAILED — $img classified as $v"; status=1;; esac; done
    # Decoder failure AFTER plausible output must not be accepted (R22-01).
    cat > "$tmp/ffmpeg-fails-late.sh" <<MOCK
#!/bin/sh
ffmpeg "\$@"; exit 47
MOCK
    chmod +x "$tmp/ffmpeg-fails-late.sh"
    if v=$(SMOKE_FFMPEG="$tmp/ffmpeg-fails-late.sh" sh -c '. "$0" _mock; classify "$1"' "$0" "$tmp/positive.png" 2>/dev/null); then
        echo "selftest: FAILED — late decoder failure accepted ($v)"; status=1
    else echo "selftest: late decoder failure is rejected ($v)"; fi
    # Failure paths through a mock simctl: launch failure and capture
    # failure must fail the gate even though a valid playfield image exists.
    cat > "$tmp/mock-launch-fails.sh" <<MOCK
#!/bin/sh
case "\$1" in launch) exit 1 ;; io) cp "$tmp/positive.png" "\$4"; exit 0 ;; *) exit 0 ;; esac
MOCK
    cat > "$tmp/mock-capture-fails.sh" <<MOCK
#!/bin/sh
case "\$1" in io) exit 1 ;; *) exit 0 ;; esac
MOCK
    cat > "$tmp/mock-ok.sh" <<MOCK
#!/bin/sh
case "\$1" in io) cp "$tmp/positive.png" "\$4"; exit 0 ;; *) exit 0 ;; esac
MOCK
    chmod +x "$tmp"/mock-*.sh
    if SMOKE_SIMCTL="$tmp/mock-launch-fails.sh" SMOKE_OUT="$tmp/out1" sh -c '. "$0" _mock; check stage "" 0' "$0" > "$tmp/l.log" 2>&1; then echo "selftest: FAILED — launch failure passed"; status=1; else echo "selftest: launch failure fails the gate"; fi
    if SMOKE_SIMCTL="$tmp/mock-capture-fails.sh" SMOKE_OUT="$tmp/out2" sh -c '. "$0" _mock; check stage "" 0' "$0" > "$tmp/c.log" 2>&1; then echo "selftest: FAILED — capture failure passed"; status=1; else echo "selftest: capture failure fails the gate"; fi
    if SMOKE_SIMCTL="$tmp/mock-ok.sh" SMOKE_OUT="$tmp/out3" sh -c '. "$0" _mock; check stage "" 0' "$0" > "$tmp/o.log" 2>&1; then echo "selftest: healthy mock passes"; else echo "selftest: FAILED — healthy mock failed: $(cat "$tmp/o.log")"; status=1; fi
    [ $status -eq 0 ] && echo "selftest: passed"
    return $status
}

case "${1:-}" in
    _mock) return 0 2>/dev/null || true ;;   # sourced by the selftest for `check`
    selftest) selftest; exit $? ;;
esac

xcodebuild build -project SparkTread.xcodeproj -scheme SparkTread \
    -destination "platform=iOS Simulator,name=$device" -derivedDataPath "$derived" -quiet
app=$(find "$derived/Build/Products" -name "SparkTread.app" -path "*iphonesimulator*" | head -1)
[ -n "$app" ] || { echo "smoke-render: app not built"; exit 1; }
$SIMCTL boot "$device" > /dev/null 2>&1 || true
$SIMCTL bootstatus "$device" -b > /dev/null 2>&1 || { echo "smoke-render: simulator did not boot"; exit 1; }
$SIMCTL install "$device" "$app" || { echo "smoke-render: install failed"; exit 1; }
status=0
check stage SPARKTREAD_AUTOSTART 5 || status=1  # past the title, startup + 3.1 s intro, then retries up to 9 s more
check lab MOVEMENT_LAB 2 || status=1  # no intro
$SIMCTL terminate "$device" io.icell.sparktread > /dev/null 2>&1 || true
exit $status
