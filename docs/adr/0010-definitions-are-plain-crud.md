# 0010. Only sessions are event-sourced; definitions are plain CRUD

- **Status:** Accepted, rationale open
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

## Open

- Why not version definitions? Presumably deadline and simplicity. Is it still
  the right call now that several teams edit the same Common Ground?

## Sources

- Former implementation plan §2 "Layer 2 is plain CRUD; only Layer 3 is
  event-sourced."
