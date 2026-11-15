# 0005. Global values are derived, never stored

- **Status:** Accepted
- **Date:** 2026-07-02

## Decision

A global value is computed from the per-group values through that value's
aggregation formula (`Scenex.Engine.Formula`: `avg`, `min`, `max`, `median`,
`sum`, arithmetic, parentheses) every time. Nothing writes a global directly.
Values are clamped to their `min`/`max`.

## Consequences (documented)

- Globals can't drift from the group values they summarize.
- Effects can only move group values; a "global" effect has to be expressed as
  effects on groups.

## Rationale

A game-design decision: the state of the world is the result of the groups'
values — always. Having both derived and directly set globals doesn't work,
so there is deliberately **no GM override** for a global value (Markus,
2026-11-15).

## Sources

- `fea558e` Engine.Sim — "derive globals via Formula".
- Former implementation plan §2 "Global values are derived, never entered
  directly".
