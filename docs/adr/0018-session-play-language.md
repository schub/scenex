# 0018. Each session has a play language; console and editor stay English

- **Status:** Accepted, rationale open
- **Date:** 2026-07-12

## Decision

A session gets a play language at creation (default: the scenario's source
locale). It drives the content locale on group boards, the display and the GM
console, and the Gettext chrome of the two audience views. The GM console's
own chrome and the editor stay English "by design".

## Consequences

- One show, one language on every audience screen.
- Translating the platform UI is limited to about 28 audience-facing strings.

## Open

- Why English-only for the console and editor? Partners all work in English,
  or effort?

## Sources

- `f72747d` Audience screens speak the session's play language.
