# 0009. Live sessions are event-sourced

- **Status:** Accepted
- **Date:** 2026-07-04

## Context

A live show can't be paused to fix the database. The GM enters decisions under
time pressure and makes mistakes; servers restart; the team wants live charts
during the show and comparisons across venues afterwards. All of this needs the
history of a session, not only its current state.

## Decision

A session is an append-only log of facts — element triggered, option chosen,
tally entered, sidequest adjudicated, ending selected — stored as
`Scenex.Play.SessionEvent` rows that are **never updated or deleted**. Every
number on the board is derived by folding the log (`Play.Projection`, pure).

- Decisions live in per-element slots; a newer entry overwrites the slot
  (last wins). A correction is a new event, not an edit.
- Events store ids, never rendered text, so the log is language-neutral.
- Each event is stamped with game time (see [0012](0012-game-clock.md)).
- Unknown event types are skipped in the fold, so old logs stay replayable.
- One `SessionServer` process per running session holds the projection;
  on start it replays the log.

## Consequences

- Undo/correction, crash recovery, live charts and cross-venue analytics come
  without extra machinery.
- It is expensive to retrofit, which is why it was decided first and marked
  "never cut".
- The log must stay readable forever: event payloads can only grow
  compatibly, and everything a log references must keep existing — see
  [0011](0011-definition-snapshot.md) and
  [0020](0020-session-groups-and-archiving.md).

## Sources

- `37df786` Add the event-sourced live-session core.
- Former implementation plan §2 "Sessions are event-sourced … This buys undo,
  live charts, crash-recovery, and cross-venue analytics for free", §9 "the
  event-sourced core is never cut (expensive to retrofit)".
- [`architecture.md`](../architecture.md) §3, §6.
