# 0013. Players get capability tokens, not accounts

- **Status:** Accepted
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

## Rationale

- **No sign-up hassle for the audience**, and **no personal data** from them.
- **As simple as possible for the people who run the show:** scan a QR code,
  place the tables, and that's it (Markus, 2026-11-15).

## Sources

- `061c49e` Add QR capability tokens, group input view, projected display.
- Former implementation plan §2 "Two-tier identity".
