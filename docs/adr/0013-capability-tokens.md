# 0013. Players get capability tokens, not accounts

- **Status:** Accepted, rationale open
- **Date:** 2026-07-04

## Decision

Two-tier identity:

- **Accounts** (email, magic link) for admins, authors and GMs — few,
  persistent.
- **Capability tokens** handed out as QR codes for players and the display.
  A token grants access to exactly one group (or the read-only display) in
  exactly one session and dies with the session. The group id comes from the
  token, never from the client.

## Consequences (documented)

- Players scan and play; no sign-up.
- A leaked QR code grants access to one group in one session, nothing more.

## Open

- The reason: friction in a theatre audience? Privacy / no personal data from
  the audience? Both?

## Sources

- `061c49e` Add QR capability tokens, group input view, projected display.
- Former implementation plan §2 "Two-tier identity".
