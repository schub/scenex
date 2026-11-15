# 0014. Registration is invitation-only

- **Status:** Accepted
- **Date:** 2026-07-05

## Decision

Public sign-up is closed: entry points to `/users/register` were removed (the
route and backend remain). Accounts come from scenario invitations: an owner
invites by email as author or viewer, and accepting the invitation creates the
account and the membership in one transaction.

## Consequences

- Every account is tied to a scenario someone vouched for.
- A new partner can't get started without an owner.

## Rationale

For now the platform is open to partners only: it runs on limited resources,
and its purpose is to serve the project. It may open up in the future — that
is decided later; before it is open to the public, someone has to finance the
hosting costs (Markus, 2026-11-15).

## Sources

- `0b354c2` Close public registration; add invite-by-email for scenario members.
