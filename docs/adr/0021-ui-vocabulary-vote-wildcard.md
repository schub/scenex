# 0021. Code says election/sidequest, the UI says Vote/Wildcard

- **Status:** Accepted
- **Date:** 2026-07-28

## Context

The three timeline kinds were named `:event`, `:election`, `:sidequest` in the
original design. The team then changed the words they use in the room.

## Decision

Rename in the UI only, via `ScenexWeb.CoreComponents.kind_label/1`. The kind
atoms, the database, the engine and the contexts keep the design terms.

## Consequences

- No migration, no risk to stored data or event logs.
- Two vocabularies to keep in mind: code and docs for developers use
  election/sidequest; anything an author, GM or partner reads uses
  Vote/Wildcard.

## Sources

- `4ee1242` — "The team changed their wording; the underlying
  :election/:sidequest kind atoms are untouched."
- [`architecture.md`](../architecture.md) §9.
