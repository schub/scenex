# 0005. Global values are derived, never stored

- **Status:** Accepted, rationale open
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

## Open

- The game-design reason: that the world's state is literally the sum of the
  groups' choices? Is this from the paper prototype?
- Was storing/overriding globals ever considered (e.g. a GM override)?

## Sources

- `fea558e` Engine.Sim — "derive globals via Formula".
- Former implementation plan §2 "Global values are derived, never entered
  directly".
