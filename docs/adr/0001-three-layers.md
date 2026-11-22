# 0001. Three layers: engine, definition, session

- **Status:** Accepted
- **Date:** 2026-07-01

## Decision

Separate the generic engine from game-specific content, and authored content
from a live play-through:

1. **Engine** (`Scenex.Engine`) — the rules, identical for every game; pure code.
2. **Definition** (`Scenex.Authoring`) — one authored scenario; CRUD in Postgres.
3. **Session** (`Scenex.Play`) — one live run of a definition; event log plus
   in-memory projection.

One definition runs as many concurrent, isolated sessions.

## Consequences (documented)

- The same engine drives the dry-run and live play ([0002](0002-pure-engine.md)).
- The same scenario can run in several cities at once without sessions
  touching each other.
- Listed first under "Never cut" in the former implementation plan.

## Background

Anything before Scenex was just playing around, not an earlier attempt to
learn from. The three-layer split was the plan from the start; no
alternatives (one app per game, a spreadsheet-like tool) were considered
(Markus, 2026-11-15).

## Sources

- `99e8a60`, `fea558e`, `555de41` (Phases 0–1).
- Former implementation plan §1–2, §9.
- [`architecture.md`](../architecture.md) §1.
