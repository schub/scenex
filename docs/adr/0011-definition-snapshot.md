# 0011. A session runs on a snapshot of its definition

- **Status:** Accepted
- **Date:** 2026-07-04

## Context

Definitions are plain, editable CRUD ([0010](0010-definitions-are-plain-crud.md)).
Authors can keep editing a scenario while sessions of it are running.

## Decision

When a session process starts, it loads an immutable snapshot of the scenario
(`Scenex.Play.Definition`) and runs on that. Edits to the scenario do not reach
a running game.

## Consequences

- An author fixing a typo can't silently change the numbers of a show in
  progress.
- The snapshot is rebuilt from the database when the process (re)starts, so
  the underlying rows must stay loadable for as long as sessions reference
  them. That is why played groups are archived instead of deleted
  ([0020](0020-session-groups-and-archiving.md)).
- A session that is restarted after the scenario was edited picks up the
  edits. Accepted so far; revisit if it bites.

## Sources

- `37df786` — "Play.Definition: an immutable snapshot of the scenario loaded at
  process start, so mid-session edits never silently change a running game."
- [`architecture.md`](../architecture.md) §6.
