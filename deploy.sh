#!/usr/bin/env bash
# Usage: ./deploy.sh [branch-or-tag]   (defaults to main)
# Run from the repo root on your local machine.
# Requires SSH access to nf-ts-deb and the root password of the VM.
set -euo pipefail

VM="nf-ts-deb"
APP_DIR="/opt/containers/scenex"
BRANCH="${1:-main}"
# The VM clones over HTTPS (public repo, no credentials needed). Local dev
# uses SSH for pushing — deliberately decoupled.
REPO_URL="https://github.com/schub/scenex.git"

echo "==> Syncing server scripts to $VM..."
# Copy as your regular SSH user into /tmp, then su copies them to APP_DIR.
scp server/update.sh server/compose.yml "$VM:/tmp/"

echo "==> Installing scripts and triggering deploy (you will be prompted for the root password)..."
ssh -t "$VM" "su - -c '
  set -e
  cp /tmp/update.sh $APP_DIR/update.sh
  chmod +x $APP_DIR/update.sh
  cp /tmp/compose.yml $APP_DIR/compose.yml
  bash $APP_DIR/update.sh $BRANCH $REPO_URL
'"
