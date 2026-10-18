#!/usr/bin/env bash
# Regenerates everything the tutorial shows, from scratch:
#
#   1. rebuilds a throwaway database (scenex_tutorial) and seeds Mars Colony,
#   2. starts Scenex on port 4100 against it,
#   3. captures the screenshots into docs/tutorial/images/,
#   4. with --video, also records the narrated screencast (see video/).
#
#     tutorial/run.sh [--video]
#
# Your normal dev database is never touched.
set -euo pipefail

cd "$(dirname "$0")/.."
export SCENEX_DEV_DATABASE=scenex_tutorial
export PORT=4100
export MIX_ENV=dev

if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is busy — stop whatever runs there first." >&2
  exit 1
fi

(cd tutorial && [ -d node_modules ] || (npm install --no-audit --no-fund && npx playwright install chromium))

echo "▸ Resetting the tutorial database"
mix ecto.drop --quiet --force-drop >/dev/null
mix ecto.create --quiet
mix ecto.migrate --quiet >/dev/null
mix run tutorial/setup.exs 2>&1 | grep -A8 "Seeded Mars Colony"

echo "▸ Starting Scenex on :$PORT"
mix phx.server >/tmp/scenex-tutorial-server.log 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do
  curl -sf "http://localhost:$PORT/" >/dev/null && break
  sleep 1
done

echo "▸ Capturing screenshots"
(cd tutorial && node capture.mjs)

if [[ "${1:-}" == "--video" ]]; then
  echo "▸ Recording the video"
  (cd tutorial && node video/record.mjs && ./video/assemble.sh)
fi

echo "▸ Done"
