# 0012. Timers run on a pausable game clock, not wall-clock

- **Status:** Accepted, rationale open
- **Date:** 2026-07-04

## Decision

Each session has a game clock the GM can pause. `game_time_ms` accumulates
only while the session is live; every event is stamped with it. Deadlines are
measured in game time; the session process schedules timers, cancels them on
pause and reschedules them with the remaining game time on resume or restart.

## Consequences (documented)

- Pausing the show freezes every deadline.
- Restarting a session process resumes timers correctly from the log.

## Open

- The reason: interruptions in the room (discussion, technical problems, an
  intermission)? Anything else?

## Sources

- `37df786` Session "pausable game clock"; `6fb5aa2` timers against the game
  clock.
- Former implementation plan §2.
