# 0017. Groups confirm once; corrections are the GM's alone

- **Status:** Accepted, rationale open
- **Date:** 2026-07-06

## Decision

A group confirms its decision explicitly, once. After a decision is recorded —
by the group, the GM or a lapsed deadline — the element is locked for the
group. Only the GM can correct it (a new event, per
[0009](0009-event-sourced-sessions.md)). Enforced on the server; stale clients
are refused.

## Consequences

- No ambiguous re-tappable buttons on the group boards.
- Every change after the fact goes through the GM.

## Open

- What prompted it — a playtest where groups changed their minds after seeing
  the board, or accidental taps?

## Sources

- `3f14eff` Groups confirm their decision once; corrections are the GM's alone.
