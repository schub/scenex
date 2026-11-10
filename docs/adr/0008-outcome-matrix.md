# 0008. Effects target the deciding group or an explicit group (outcome matrix)

- **Status:** Accepted, rationale open
- **Date:** 2026-07-03

## Decision

An `OptionEffect` with `group_id: nil` applies to the deciding group (events:
each group decides for itself). A set `group_id` targets that group explicitly,
which is how elections ("Votes") and sidequests ("Wildcards") express a
per-group outcome matrix. Three kinds at three social scales: a group, the
whole room, one player.

## Consequences (documented)

- One effect model covers all three kinds.
- `nil` carries meaning, so it must never be "fixed" into a concrete group id.

## Open

- The three-scales symmetry comes from the game design document — worth one
  sentence on why these three scales.

## Sources

- `5a0d0e4` Add design-alignment schema: notes, gates, matrices, endings.
- Former implementation plan §2 (table "Three timeline element kinds, three
  social scales").
