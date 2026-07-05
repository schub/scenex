---
name: release
description: Cut a Scenex release by running ./release.sh (strips the -dev suffix, merges dev into main as a tagged merge commit, reopens dev on the next -dev version). Use when Markus asks to create/cut/make a release. Optional argument sets the next dev version (patch/minor/major or explicit X.Y.Z; default minor).
---

# Release Scenex

The release is fully scripted — do not reimplement the steps.

Run from `dev/scenex/`:

```bash
./release.sh [patch|minor|major|X.Y.Z]
```

The argument sets the **next** dev version (default: minor bump). The script
handles all checks (on dev, clean tree, in sync with origin, tag free,
`mix precommit` green) and dies with a clear message if one fails — relay
that message and stop; do not work around a failed check.

On success, report the released version and the new dev version.
Do **not** deploy — Markus deploys manually (`./deploy.sh vX.Y.Z`).
