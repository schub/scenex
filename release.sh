#!/usr/bin/env bash
# Usage: ./release.sh [patch|minor|major|X.Y.Z]
# Run from the repo root on your local machine.
#
# dev always carries X.Y.Z-dev in mix.exs (the Elixir pre-release
# convention). This script strips the suffix, merges dev into main as a
# merge commit (the style of every release since v0.4.0), tags it vX.Y.Z,
# and reopens dev on the next -dev version. The argument sets the NEXT dev
# version (default: minor).
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "release: $*" >&2; exit 1; }

BUMP="${1:-minor}"

# ── Preflight ──────────────────────────────────────────────────────────
[ "$(git rev-parse --abbrev-ref HEAD)" = "dev" ] || die "not on dev"
[ -z "$(git status --porcelain)" ] || die "working tree not clean — commit or stash first"

git fetch origin
[ -z "$(git rev-list HEAD..origin/dev)" ] || die "dev is behind origin/dev — pull first"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] || die "local main differs from origin/main"

DEV_VERSION="$(sed -nE 's/^ *version: "([^"]+)",$/\1/p' mix.exs)"
[ -n "$DEV_VERSION" ] || die "no version found in mix.exs"

case "$DEV_VERSION" in
  *-dev) RELEASE="${DEV_VERSION%-dev}" ;;
  *) die "mix.exs version is '$DEV_VERSION' — expected X.Y.Z-dev" ;;
esac

echo "$RELEASE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "release version '$RELEASE' is not X.Y.Z"

if git rev-parse -q --verify "refs/tags/v$RELEASE" >/dev/null; then
  die "tag v$RELEASE already exists"
fi

IFS=. read -r MAJOR MINOR PATCH <<< "$RELEASE"
case "$BUMP" in
  patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  *)
    echo "$BUMP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
      die "argument must be patch, minor, major, or X.Y.Z (got '$BUMP')"
    NEXT="$BUMP"
    ;;
esac

echo "==> Releasing v$RELEASE; dev continues as $NEXT-dev."

echo "==> Running mix precommit..."
mix precommit
[ -z "$(git status --porcelain)" ] || die "precommit changed files (formatting?) — commit them first"

set_version() {
  sed -E "s/^( *version: )\"$1\",$/\1\"$2\",/" mix.exs > mix.exs.tmp && mv mix.exs.tmp mix.exs
  grep -q "version: \"$2\"," mix.exs || die "failed to set version $2 in mix.exs"
}

# ── Release commit on dev ──────────────────────────────────────────────
set_version "$DEV_VERSION" "$RELEASE"
git commit -am "Release v$RELEASE"
git push origin dev

# ── Promote to main and tag ────────────────────────────────────────────
git checkout main
git merge --no-ff dev -m "Release v$RELEASE" ||
  { git merge --abort; git checkout dev; die "merge of dev into main failed"; }
git tag -a "v$RELEASE" -m "Release v$RELEASE"
git push origin main
git push origin "v$RELEASE"

# ── Reopen dev on the next -dev version ────────────────────────────────
git checkout dev
set_version "$RELEASE" "$NEXT-dev"
git commit -am "Start v$NEXT-dev"
git push origin dev

echo
echo "==> Released v$RELEASE (tagged on main). dev is now at $NEXT-dev."
echo "==> Deploy when ready: ./deploy.sh   (deploys main = v$RELEASE)"
