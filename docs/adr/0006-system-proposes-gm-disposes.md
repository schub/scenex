# 0006. The system proposes, the GM disposes

- **Status:** Accepted
- **Date:** 2026-07-03

## Decision

Nothing fires automatically in a live show. The GM triggers every timeline
element, adjudicates sidequests, breaks ties and declares the end. Conditions,
deadline defaults and ending matches are recommendations. No dice, no hidden
randomness. Gated options are shown greyed out with the reason, never hidden.

## Consequences (documented)

- Server-side commands enforce structural integrity, not gates: "the GM
  disposes" (`37df786`).
- Endings are recommended by condition and priority; the GM picks and may
  override.
- A lapsed deadline only proposes its default options; the GM applies them
  with one click in the console (`defaults_applied`). Until v1.11 the server
  applied them by itself (`deadline_lapsed`); old logs still replay
  ([#12](https://github.com/schub/scenex/issues/12)).

## Rationale

It's theatre: the facilitator has to steer the show (Markus, 2026-11-15).

## Sources

- `aa38082` Align the implementation plan with the hardened game design.
- Former implementation plan §2 "The system proposes, the GM disposes".
- Game design document (`docs/game-design.md` in `77db073`, now in
  `studio/docs/`).
