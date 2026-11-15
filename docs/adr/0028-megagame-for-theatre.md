# 0028. The megagame, adapted for theatre: three kinds of beats on a GM-driven timeline

- **Status:** Accepted
- **Date:** 2026-07-03 (recorded 2026-11-15)

## Context

Scenex starts from the generic megagame paradigm: teams decide, control
adjudicates, the game advances in rounds. A theatre production needs more:
a director has to shape the arc of an evening, read the audience and react
to it. This is the core game-design decision behind Scenex — what Markus
changed in the megagame to make it work as a theatre production, giving the
director more ways to shape an evening (Markus, 2026-11-15).

## Decision

**Three kinds of timeline elements**, each a different way of deciding:

| Kind (code / UI) | Who decides | Role |
|---|---|---|
| **Event** (`:event`) | Each group, on its own | The main element; drives the story |
| **Vote** (`:election`) | Every player individually, together for the whole room | A collective decision of the room |
| **Wildcard** (`:sidequest`) | One player gets their own task; the GM judges it | Individual tasks; a way for the director or GM to move the story in a direction without the whole room being involved |

Votes and Wildcards complement Events, so that decision processes other than
the group's can take place. Only the three together cover the range a
director needs. A Wildcard can be carried out in secret or in front of the
whole room — whichever suits the scenario and the moment; showing it on the
scoreboard is the GM's choice.

**A time-based timeline instead of rounds.** The classic megagame is
round-based. In Scenex the GM triggers every beat when they choose: they
know the room, read the audience and react. Deadlines run on a game clock
([0012](0012-game-clock.md)), not on rounds.

## Consequences

- One effect model covers all three kinds: an effect targets the deciding
  group or an explicit group ([0008](0008-outcome-matrix.md)).
- The GM triggers everything; the system proposes and the GM disposes
  ([0006](0006-system-proposes-gm-disposes.md)).
- No group-to-group mechanics (e.g. two groups negotiating a deal) — not
  needed for now. A fourth kind would be a new decision.
- Each Wildcard starts hidden on the scoreboard; the GM shows it with its own
  "On screen" switch ([#20](https://github.com/schub/scenex/issues/20)).

## Sources

- Markus, 2026-11-15 (conversation while filling in the open rationale,
  [#4](https://github.com/schub/scenex/issues/4)).
- `5a0d0e4` Add design-alignment schema: notes, gates, matrices, endings.
- Former implementation plan §2, table "Three timeline element kinds, three
  social scales".
