# 0007. Manual before automatic

- **Status:** Accepted
- **Date:** 2026-07-03

## Decision

Every input can be entered by the GM by hand. Election votes can always be
entered as a hand-count tally; device-based individual voting is an
enhancement, never a dependency. Per-participant values (well-being) are
collected in the room, analog — smiley coins — and entered by the GM.

## Consequences (documented)

- A show works with one GM laptop and no player devices.
- Device features must degrade to manual entry.

## Rationale

- **The system knows groups, not players.** There are no individual players
  in the data model, so individual decisions can't be tracked electronically.
- **Simple to run.** From the start, the goal was a simple tech setup and
  simple requirements for running a show — so votes are counted by hand.

Device-based individual voting is not planned: it would need a UI per player
and trackable individuals, which the group-only model rules out (Markus,
2026-11-15).

## Sources

- Former implementation plan §2 "Manual before automatic".
- `266b3bb` Add well-being tally for per-participant values.
