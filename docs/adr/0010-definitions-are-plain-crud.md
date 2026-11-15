# 0010. Only sessions are event-sourced; definitions are plain CRUD

- **Status:** Accepted
- **Date:** 2026-07-04

## Decision

Layer 2 (scenarios and everything in them) is ordinary create/update/delete in
Postgres, with no history and no versions. Only layer 3 is event-sourced
([0009](0009-event-sourced-sessions.md)). Sessions are protected from edits by
a snapshot ([0011](0011-definition-snapshot.md)).

## Consequences

- Simple editing code.
- No history of a scenario: an edit by one team overwrites the shared state
  for everyone, with no undo — see [0024](0024-shared-scenario-vs-copies.md).

## Rationale

Keep it simple. Version history for definitions would be nice, but it is too
much for now — still the call with several teams editing the same scenario.
Something to think about in the future, not now (Markus, 2026-11-15). Related:
[0024](0024-shared-scenario-vs-copies.md).

## Sources

- Former implementation plan §2 "Layer 2 is plain CRUD; only Layer 3 is
  event-sourced."
