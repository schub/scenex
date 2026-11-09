# 0002. The engine is pure and shared by simulate mode and live play

- **Status:** Accepted
- **Date:** 2026-07-02

## Context

A scenario is balanced by its author in the editor, then performed live in a
room. If the numbers on the night differ from the numbers in the dry-run, the
author's balancing is worthless — and nobody finds out until the audience does.

## Decision

All game rules live in `Scenex.Engine` as pure functions: no Ecto, no
processes, no I/O. Values, clamping, effects, aggregation formulas, conditions,
the Overall Index and band scales. Simulate mode (the editor's dry-run) and
live play (`Scenex.Play`) call the same code. `Scenex.Play` is the only place
that wraps the engine in processes.

## Consequences

- A scenario balanced in the editor behaves identically on the night.
- The engine is exhaustively unit-testable without a database.
- The live projection (`Play.Projection`) can be a pure fold over the event log
  (see [0009](0009-event-sourced-sessions.md)), so replay-on-restart gives an
  identical board.
- Anything that needs a database or a clock must be passed in as data. This is
  a constraint on every new mechanic, by design.
- Listed under "Never cut" in the former implementation plan.

## Sources

- `fea558e` Phase 1a: pure Engine (Formula, ValueSpec, Sim) — "Reusable by
  simulate (Phase 2) and live sessions (Phase 3)."
- Former implementation plan §9 "Never cut: … the pure `Engine` (incl.
  `Condition`)".
- [`architecture.md`](../architecture.md) §3–4.
