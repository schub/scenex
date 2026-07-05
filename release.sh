#!/usr/bin/env bash
# Usage: ./release.sh [patch|minor|major|X.Y.Z]
# Run from the repo root on your local machine.
#
# dev always carries X.Y.Z-snapshot in mix.exs. This script strips the
# suffix, fast-forwards main, tags vX.Y.Z, and reopens dev on the next
# snapshot version. The argument sets the NEXT dev version (default: minor).
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

SNAPSHOT="$(sed -nE 's/^ *version: "([^"]+)",$/\1/p' mix.exs)"
[ -n "$SNAPSHOT" ] || die "no version found in mix.exs"

case "$SNAPSHOT" in
  *-snapshot) RELEASE="${SNAPSHOT%-snapshot}" ;;
  *) die "mix.exs version is '$SNAPSHOT' — expected X.Y.Z-snapshot" ;;
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

echo "==> Releasing v$RELEASE; dev continues as $NEXT-snapshot."

echo "==> Running mix precommit..."
mix precommit
[ -z "$(git status --porcelain)" ] || die "precommit changed files (formatting?) — commit them first"

set_version() {
  sed -E "s/^( *version: )\"$1\",$/\1\"$2\",/" mix.exs > mix.exs.tmp && mv mix.exs.tmp mix.exs
  grep -q "version: \"$2\"," mix.exs || die "failed to set version $2 in mix.exs"
}

# ── Release commit on dev ──────────────────────────────────────────────
set_version "$SNAPSHOT" "$RELEASE"
git commit -am "Release v$RELEASE"
git push origin dev

# ── Promote to main and tag ────────────────────────────────────────────
git checkout main
git merge --ff-only dev
git tag -a "v$RELEASE" -m "Release v$RELEASE"
git push origin main
git push origin "v$RELEASE"

# ── Reopen dev on the next snapshot ────────────────────────────────────
git checkout dev
set_version "$RELEASE" "$NEXT-snapshot"
git commit -am "Start v$NEXT-snapshot"
git push origin dev

echo
echo "==> Released v$RELEASE (tagged on main). dev is now at $NEXT-snapshot."
echo "==> Deploy when ready: ./deploy.sh v$RELEASE"
