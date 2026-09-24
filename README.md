# Scenex

A web platform for **authoring and running** large, role-based simulation
games — "megagames" — staged as live, facilitator-led performances.

## What it does

A room full of participants is split into fixed groups, each seated together
with their own screen. A game master (GM) runs the session in real time,
manually triggering authored story beats in whatever order and at whatever
pace fits the room. Each beat presents narrative and lets one or more groups
make a decision. Every decision nudges a small set of tracked numeric values,
per group and in aggregate — so the score on the wall is the visible, moving
consequence of what the room chose.

There are three screens:

- a shared **projected display** for the whole room — global values, the
  current beat, and the finale;
- each group's own **group board** — that group's values and its own
  decisions, opened by scanning a QR code, no login;
- the GM's **console** — full visibility and every control.

Everything a game is made of — its values, its groups, its beats and options
and endings, in as many languages as you need — is authored in the browser.
The platform itself is generic: any particular game is just content inside it.
One authored scenario can run as many separate live sessions at once, in
different cities, without them touching each other.

## How it's built

Three layers, which is the one architectural idea everything else serves:

| Layer | What it is | Storage |
|---|---|---|
| **Engine** | The rules of physics — values, aggregation, conditions, effects. The same for every game. | Code, pure functions |
| **Definition** | One authored scenario. Reusable. | CRUD in Postgres |
| **Session** | One live run of a definition, at one venue, on one day. | Append-only event log + in-memory projection |

Elixir, Phoenix 1.8, LiveView, PostgreSQL. Live sessions are event-sourced,
with one supervised process per running session — so a session survives an app
restart by replaying its log, and the GM can correct any mistake by simply
re-entering the decision.

See [`docs/architecture.md`](docs/architecture.md) for the full picture.

## Running it locally

Requires Elixir 1.19 / OTP 28 and a PostgreSQL reachable on `localhost` with
user `dev`, password `dev` (see `config/dev.exs`).

```bash
mix setup        # deps, create + migrate DB, seed, build assets
mix phx.server   # http://localhost:4000
```

Use `iex -S mix phx.server` if you want a REPL attached.

To get something to look at, register an account, then create the CIVITAS demo
scenario — a three-group mini-megagame:

```elixir
iex> Scenex.DemoScenario.create(Scenex.Accounts.get_user_by_email("you@example.com"))
```

In development, sent mail (including magic-link logins) is captured at
`/dev/mailbox` rather than delivered.

## Commands

| Command | What it does |
|---|---|
| `mix setup` | Install deps, create + migrate + seed the DB, build assets |
| `mix phx.server` | Run the server on port 4000 |
| `mix precommit` | Compile with warnings as errors, unlock unused deps, format, test — **run before finishing any change** |
| `mix test` | Full suite (creates and migrates the test DB itself) |
| `mix test path/to_test.exs:42` | A single test by line |
| `mix test --failed` | Re-run the last failures |
| `mix ecto.reset` | Drop, recreate, migrate, re-seed |
| `mix ecto.gen.migration name` | Generate a migration — always use this, never hand-write timestamps |
| `./release.sh [patch\|minor\|major]` | Cut a release (see [`docs/releasing.md`](docs/releasing.md)) |
| `./deploy.sh [branch-or-tag]` | Deploy to the VM |

## Where things are

```
lib/scenex/
  engine/       Layer 1 — pure: Sim, Formula, Condition, Index, Scale
  authoring/    Layer 2 — the definition graph (scenarios, values, groups,
                timeline elements, options, effects, endings, pages)
  play/         Layer 3 — sessions, append-only log, capability tokens,
                the per-session GenServer and its projection
  media/        Per-scenario media library
  accounts/     phx.gen.auth — magic-link auth and scopes
lib/scenex_web/
  live/scenario_live/   The authoring editor + simulate (dry-run) mode
  live/session_live/    Session list and the GM console
  live/play_live/       Token-access group board and projected display
docs/           Architecture, deployment, releasing
server/         Files that live on the production VM
```

The module docs are the reference for anything specific — they are kept
current and are more detailed than these documents.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — the three layers, the
  invariants, how a live session runs
- [`docs/deployment.md`](docs/deployment.md) — production VM, environment,
  edge proxy
- [`docs/releasing.md`](docs/releasing.md) — branch model, versioning, cutting
  a release
- [`AGENTS.md`](AGENTS.md) — conventions for writing code in this repo

The game design material this app models — concepts, playtest feedback, the
scenario briefs — lives one level up in `studio/docs/`, not here. Authors
writing content for a specific production should start from
`studio/docs/ai-context.md`.
