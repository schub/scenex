# Scenex — Releasing

## Branch model

Two long-lived branches:

- **`dev`** — where work happens. Always carries an `X.Y.Z-dev` version in
  `mix.exs` (the Elixir pre-release convention).
- **`main`** — released code only. Every release is a `--no-ff` merge commit
  from `dev`, tagged `vX.Y.Z`. This has been the shape of every release since
  v0.4.0.

`main` is what gets deployed. Nothing is committed to it directly.

## Cutting a release

Fully scripted — don't do the steps by hand:

```bash
./release.sh [patch|minor|major|X.Y.Z]
```

The argument sets the **next dev version**, not the one being released. The
version being released is whatever `dev` currently carries, minus the `-dev`
suffix. Default bump is `minor`.

So from `1.5.2-dev`, `./release.sh` releases **v1.5.2** and reopens `dev` at
`1.6.0-dev`; `./release.sh patch` would reopen at `1.5.3-dev` instead.

The script:

1. **Checks** — on `dev`, clean tree, not behind `origin/dev`, local `main`
   matches `origin/main`, the target tag doesn't exist, and `mix precommit`
   passes.
2. Strips `-dev` from `mix.exs`, commits `Release vX.Y.Z`, pushes `dev`.
3. Checks out `main`, merges `dev` with `--no-ff`, tags `vX.Y.Z`, pushes both.
4. Returns to `dev`, sets the next `-dev` version, commits `Start vX.Y.Z-dev`,
   pushes.

If a check fails the script stops with a clear message and changes nothing.
Fix the cause rather than working around it — in particular, if `mix precommit`
reformats files, commit those first and re-run.

## Deploying

Releasing does **not** deploy. That is a separate, manual step:

```bash
./deploy.sh            # deploys main
./deploy.sh v1.5.1     # deploys a specific tag
```

See [`deployment.md`](deployment.md).

## Automation

`.claude/skills/release/SKILL.md` lets an AI assistant run this on request. It
delegates to `release.sh` and does not reimplement any of it — which is the
point: there is one implementation of the release process, and it's the
script.
