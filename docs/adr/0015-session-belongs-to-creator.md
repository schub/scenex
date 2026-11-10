# 0015. A session belongs to its creator; the owner keeps an override

- **Status:** Accepted
- **Date:** 2026-07-05

## Context

Several authors share one scenario. Until this change, any author of a
scenario could open the console of any of its sessions and send commands.

## Decision

The person who creates a session is its GM. Other authors of the same scenario
can't open its console or send commands. The scenario owner keeps an override
as the recovery path for live events (e.g. the GM's laptop dies).

## Consequences

- One person in control per show; the sessions list shows who runs each one.
- Handing a show over to someone else needs the owner.
- Session roles are separate from scenario roles (`owner`/`author`/`viewer`) —
  see [`architecture.md`](../architecture.md) §7.

## Open

- The commit records the override's purpose but not why other authors were
  locked out. Accidental double control during a show? Accountability?

## Sources

- `14a8af6` Sessions belong to their creator; scenario owner keeps an override.
