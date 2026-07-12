#!/usr/bin/env bash
# Runs on the VM as root. Called by deploy.sh on your laptop.
set -euo pipefail

APP_DIR="/opt/containers/scenex"
BRANCH="${1:-main}"
REPO_URL="${2:-}"

echo "==> Updating source ($BRANCH)..."
if [ ! -d "$APP_DIR/src/.git" ]; then
  [ -z "$REPO_URL" ] && { echo "ERROR: src not cloned yet and no REPO_URL given."; exit 1; }
  git clone "$REPO_URL" "$APP_DIR/src"
fi
cd "$APP_DIR/src"
git fetch origin --tags
git checkout "$BRANCH"
# Tags check out detached — nothing to pull. Only branches track a remote.
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git pull origin "$BRANCH"
fi

echo "==> Building image..."
docker build -t scenex:latest .

echo "==> Running migrations..."
docker run --rm \
  --env-file "$APP_DIR/.env" \
  --network postgres_default \
  scenex:latest /app/bin/migrate

echo "==> Restarting container..."
cd "$APP_DIR"
docker compose up -d --remove-orphans

echo "==> Done. scenex is running on port 4000."
