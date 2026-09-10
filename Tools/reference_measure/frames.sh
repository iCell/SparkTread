#!/bin/sh
# Accurate-seek frame strip. usage: frames.sh VIDEO T [DURATION FPS]
# One frame (DURATION omitted) or a tiled strip of DURATION seconds at FPS.
set -eu
video=$1; t=$2; dur=${3:-}; fps=${4:-10}
if [ -z "$dur" ]; then
    ffmpeg -y -loglevel error -i "$video" -ss "$t" -frames:v 1 "frame_$t.png"
else
    n=$(python3 -c "import math; print(math.ceil($dur*$fps))")
    cols=$(( n < 10 ? n : 10 )); rows=$(( (n + cols - 1) / cols ))
    ffmpeg -y -loglevel error -ss "$t" -t "$dur" -i "$video" \
        -vf "fps=$fps,scale=240:-1,tile=${cols}x${rows}" "strip_${t}_${dur}s_%d.png"
fi
