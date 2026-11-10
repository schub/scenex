# 0016. Releases: `-dev` versions, `--no-ff` merge to `main`, one script

- **Status:** Accepted
- **Date:** 2026-07-06

## Context

The release steps first lived only inside a Claude skill (`03b9617`), with a
`-snapshot` version suffix, and the first scripted version did not produce
the merge-commit shape `main` had used since v0.4.0.

## Decision

- `dev` always carries an `X.Y.Z-dev` version (the Elixir pre-release
  convention, replacing `-snapshot`).
- A release is a `--no-ff` merge commit of `dev` into `main`, tagged `vX.Y.Z`,
  matching the shape of the history since v0.4.0.
- `release.sh` is the only implementation. The `/release` skill just runs it.
- Releasing does not deploy; `deploy.sh` is a separate manual step.

## Consequences

- One implementation of the process, with checks (clean tree, up to date,
  `mix precommit`) that stop before anything changes.
- `main` contains only released code.

## Sources

- `03b9617`, `af9b6b9` "Script the release flow; /release skill just runs
  release.sh", `cea02c8` "Use the Elixir -dev pre-release suffix",
  `31c15ae` "Release with a merge commit on main, matching the repo's history".
- [`releasing.md`](../releasing.md).
