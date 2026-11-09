# 0014. Registration is invitation-only

- **Status:** Accepted, rationale open
- **Date:** 2026-07-05

## Decision

Public sign-up is closed: entry points to `/users/register` were removed (the
route and backend remain). Accounts come from scenario invitations: an owner
invites by email as author or viewer, and accepting the invitation creates the
account and the membership in one transaction.

## Consequences

- Every account is tied to a scenario someone vouched for.
- A new partner can't get started without an owner.

## Open

- Why: spam, cost, keeping the platform among partners for now? Is opening it
  up planned (relevant to the license and to [0024](0024-shared-scenario-vs-copies.md))?

## Sources

- `0b354c2` Close public registration; add invite-by-email for scenario members.
