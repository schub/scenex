#!/usr/bin/env bash
# Writes video/build/frames-at.png: a strip of stills around one moment of
# the last video (every 0.5 s, from 2 s before to 2 s after), to inspect
# glitches.
#
#     tutorial/video/frames-at.sh 3:29
set -euo pipefail

build="$(cd "$(dirname "$0")" && pwd)/build"
at="$1"
seconds=$(( 10#${at%%:*} * 60 + 10#${at##*:} ))
start=$(( seconds - 2 ))

ffmpeg -v error -y -ss "$start" -t 4 -i "$build/scenex-tutorial.mp4" \
  -vf "fps=2,scale=400:-1,tile=4x2:padding=4" -frames:v 1 "$build/frames-at.png"
echo "$build/frames-at.png ($((start / 60)):$(printf %02d $((start % 60))) … +4 s)"
