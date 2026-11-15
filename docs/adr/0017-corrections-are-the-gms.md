# 0017. Groups confirm once; corrections are the GM's alone

- **Status:** Accepted
- **Date:** 2026-07-06

## Decision

A group confirms its decision explicitly, once. After a decision is recorded —
by the group, the GM or a default the GM applied — the element is locked for the
group. Only the GM can correct it (a new event, per
[0009](0009-event-sourced-sessions.md)). Enforced on the server; stale clients
are refused.

## Consequences

- No ambiguous re-tappable buttons on the group boards.
- Every change after the fact goes through the GM.

## Rationale

The group makes a decision, and that's it. There is a confirm dialog, but no
reason to change a decision afterwards — basically, to keep it simple
(Markus, 2026-11-15).

## Sources

- `3f14eff` Groups confirm their decision once; corrections are the GM's alone.
