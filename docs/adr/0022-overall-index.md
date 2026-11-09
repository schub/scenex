# 0022. A scenario-agnostic Overall Index replaces the Democracy Score

- **Status:** Accepted
- **Date:** 2026-08-28

## Context

The single headline metric was built for the Portugal game as the "Democracy
Score", hardwired into schema, engine, projection and UI. Scenex is a generic
platform: a sci-fi or fantasy megagame has no democracy. Its formula also
aggregated an anonymous list of all globals, so it could neither weight values
nor cope with values on different scales.

## Decision

- Rename to **Overall Index**, labelled by the author per scenario (localized
  `overall_index_name`/`description`, falling back to "Overall Index").
- New `Scenex.Engine.Index`: the formula references value globals **by key**
  (e.g. `2*stability + 3*resources`). References are raw; authors normalise
  explicitly.
- Rename in place (columns, table, board section, functions); ranges, bands and
  the gauge window carry over.

## Consequences

- The engine no longer contains a game-specific concept — the standing example
  for the rule "mechanics never depend on a specific game".
- The formula language changed, so the migration blanked every existing
  formula; each scenario had to re-enter it once.
- Formulas reference value keys, which is one reason value keys must stay
  slugs ([0023](0023-key-name-title-vocabulary.md)).

## Sources

- `0a7cea7`, `d5c03be` (the original Democracy Score), `4cbacae` (the
  replacement).
