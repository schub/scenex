---
name: release
description: Cut a Scenex release — strip -snapshot from the version, fast-forward main, tag vX.Y.Z, then reopen dev on the next -snapshot version. Use when Markus asks to create/cut/make a release. Optional argument sets the next dev version (explicit version or patch/minor/major; default minor).
---

# Release Scenex

Versioning scheme: `dev` always carries `X.Y.Z-snapshot` in `mix.exs`. A release
strips the suffix, promotes that commit to `main` (fast-forward only), tags it
`vX.Y.Z`, and moves dev on to the next snapshot. `main` only ever receives
releases.

All commands run from `dev/scenex/`. Never force-push. If any check fails,
stop and report — do not improvise around it.

## 1. Preflight

- Current branch must be `dev` (`git rev-parse --abbrev-ref HEAD`).
- Working tree must be clean (`git status --porcelain` prints nothing).
- `git fetch origin`. `dev` must not be behind `origin/dev`, and local `main`
  must be equal to `origin/main`.
- Read `version:` from `mix.exs`. It must match `X.Y.Z-snapshot`; the release
  version is `X.Y.Z`. If the suffix is missing, the scheme is broken — stop
  and ask which version to release.
- Confirm the tag `vX.Y.Z` does not already exist.
- Run `mix precommit`. Abort on any failure.

## 2. Release commit on dev

- Set `version: "X.Y.Z"` in `mix.exs`.
- `git commit -am "Release vX.Y.Z"`
- `git push origin dev`

## 3. Promote to main and tag

- `git checkout main`
- `git merge --ff-only dev` — if this refuses, main has diverged from dev;
  stop and report instead of forcing a merge commit.
- `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- `git push origin main`
- `git push origin vX.Y.Z`

## 4. Reopen dev on the next snapshot

- `git checkout dev`
- Next version: bump **minor** by default → `X.(Y+1).0-snapshot`. A skill
  argument overrides this: an explicit version (`0.8.0`) or a bump size
  (`patch` / `minor` / `major`).
- Set `version: "<next>-snapshot"` in `mix.exs`.
- `git commit -am "Start v<next>-snapshot"`
- `git push origin dev`

## 5. Report

Summarize: released `vX.Y.Z` (tagged on main), dev now at `<next>-snapshot`.
Do **not** deploy — Markus deploys manually (`./deploy.sh`); just note that
the release is ready to deploy.
