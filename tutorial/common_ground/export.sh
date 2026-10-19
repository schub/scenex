#!/usr/bin/env bash
# Extracts the Common Ground scenario from a restored copy of the production
# database into a folder the tutorial can load (tutorial/setup.exs):
# one CSV per table plus the scenario's media files. Nothing personal is
# exported — no accounts, memberships, sessions or logs.
#
#     tutorial/common_ground/export.sh <database-url> <media-dir> [out-dir]
#
#   database-url  a restored production copy, e.g.
#                 postgres://oracle:oracle@localhost:5433/scenex_prod
#   media-dir     the production media folder (from the media backup)
#   out-dir       default: ../data/common-ground next to the studio checkout
#
# The output is kept out of this repository on purpose.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
db="${1:?database url}"
media="${2:?production media dir}"
out="${3:-$here/../../../../data/common-ground}"
handle="${SCENARIO_HANDLE:-COMMON GROUND}"

rm -rf "$out"
mkdir -p "$out/media"
cd "$out"

psql "$db" -q -v handle="$handle" -f "$here/export.sql"

# Media: one folder per file id, as in the production media dir.
tail -n +2 media_files.csv | cut -d, -f1 | while read -r id; do
  cp -R "$media/$id" "media/$id"
done

echo "Exported \"$handle\" to $out"
wc -l ./*.csv | sed 's/^/  /'
