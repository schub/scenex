#!/usr/bin/env bash
# Writes video/build/contact-sheet.png: one still from the middle of every
# scene of the last recording, for a quick visual check.
set -euo pipefail

build="$(cd "$(dirname "$0")" && pwd)/build"
frames="$build/frames"
rm -rf "$frames"
mkdir -p "$frames"

node -e '
  const t = require(process.argv[1]);
  t.scenes.forEach((s, i) => console.log(i, ((s.start + s.end) / 2).toFixed(2)));
' "$build/timeline.json" | while read -r i ts; do
  ffmpeg -v error -y -ss "$ts" -i "$build/scenex-tutorial.mp4" -frames:v 1 -vf scale=480:-1 "$frames/$(printf %02d "$i").png"
done

ffmpeg -v error -y -pattern_type glob -i "$frames/*.png" -vf "tile=5x10:padding=4" -frames:v 1 "$build/contact-sheet.png"
echo "$build/contact-sheet.png"
