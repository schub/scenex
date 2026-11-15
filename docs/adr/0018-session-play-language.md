# 0018. Each session has a play language; console and editor stay English

- **Status:** Accepted
- **Date:** 2026-07-12

## Decision

A session gets a play language at creation (default: the scenario's source
locale). It drives the content locale on group boards, the display and the GM
console, and the Gettext chrome of the two audience views. The GM console's
own chrome and the editor stay English "by design".

## Consequences

- One show, one language on every audience screen.
- Translating the platform UI is limited to about 28 audience-facing strings.

## Rationale

- **The audience gets its language, no compromises:** everything players and
  the room see is translated.
- **The people who work with the editor and the GM console don't need it.**
  Workshops and tutorials are in English anyway, and translating the controls
  brings no big advantage — with more people involved, every new language
  would have to be added to all the controls. Keep it simple: English
  (Markus, 2026-11-15).

## Sources

- `f72747d` Audience screens speak the session's play language.
