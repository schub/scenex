# 0020. Sessions select their groups; played groups are archived, not deleted

- **Status:** Accepted
- **Date:** 2026-07-18

## Context

Venues seat 25–70 people, and some groups are specific to one theatre, so not
every show plays with every group of a scenario. At the same time, an
event-sourced session ([0009](0009-event-sourced-sessions.md)) must replay
identically forever, which needs every group it played with to stay loadable.

## Decision

- Each session picks its groups (minimum two) from the scenario's pool at
  creation (`session_groups`). The selection is fixed: the log replays against
  it.
- Effects aimed at a group that isn't playing are no-ops.
- Deleting a group that no session has used is a hard delete. Deleting one that
  a session used **archives** it (`archived_at`): gone from the editor, the
  dry-run and new sessions, but still loaded by the play definition.
- Key uniqueness covers active groups only, so an archived group's key is free
  again immediately.

## Consequences

- Old sessions keep rendering and replaying after the pool changes.
- Code that lists groups must decide whether archived ones count
  (`include_archived: true` in the play layer only).
- Archived groups are invisible but not gone — relevant whenever a scenario is
  exported or copied.

## Sources

- `4065413` Sessions select their groups from the scenario's pool.
- `ea02ce8` Groups archive instead of blocking deletion once a session uses them.
