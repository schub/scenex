# 0027. An MCP server lets agents author scenarios and observe live shows

- **Status:** Proposed
- **Date:** —

## Context

Building a scenario is a lot of clicking: values, groups, timeline elements,
options, effects, endings, each in several languages. An AI agent could draft
and rebalance a scenario, but today the only way in is the browser UI. The
[Model Context Protocol](https://modelcontextprotocol.io) is the common way to
give an agent (Claude, Cursor, ChatGPT) tools against a system.

Two things make this an architecture decision rather than a feature: it is a
new way into the system with its own authentication, and agents acting in a
live session collide with [0006](0006-system-proposes-gm-disposes.md) and
[0007](0007-manual-before-automatic.md) — the GM triggers every beat and makes
every final call.

## Decision

Add an MCP server to Scenex, in two phases.

- **Inside the Phoenix app**, as a Streamable HTTP endpoint (e.g. `/mcp`), not
  a separate service. Tools are thin wrappers over `Scenex.Authoring` and
  `Scenex.Play`, so authorization (`can_edit?/2`, `get_user_role/2`) and the
  invariants hold unchanged. A separate process writing to Postgres would
  bypass both, and could not reach running sessions, which live in the app's
  session processes.
- **Authentication by personal access tokens**: created and revoked by a user
  in their settings, scoped (authoring; observe), stored hashed. A request with
  a token runs as that user's `current_scope`.
- **Phase 1 — authoring.**
  - read a whole scenario as one document, every entity identified by its
    `key` ([0023](0023-key-name-title-vocabulary.md));
  - create/update/delete single entities by key, writing join tables through
    the existing upsert helpers;
  - simulate: run the scenario through `Scenex.Engine.Sim` and report where the
    values and the recommended ending land, so an agent can build, simulate
    and rebalance in a loop without a live session
    ([0002](0002-pure-engine.md));
  - reference material as MCP resources: data model, formula syntax, localized
    fields as `locale => string` maps.
- **Phase 2 — observe live shows, never act.** An agent may read a running
  session's snapshot and give recommendations (which beat next, which ending
  matches). It issues no `Scenex.Play` commands; the human GM acts.

## Alternatives considered

- **Separate MCP server against the database or a REST API** — duplicates or
  bypasses authorization; a REST API would have to be built first anyway.
- **OAuth 2.1 (MCP's spec for remote servers)** — needed to appear as a
  Claude.ai/ChatGPT connector, but far more machinery than tokens. Can be added
  later on top of the same tools.
- **Agents control live sessions** — in rehearsals only, or in live shows when
  the GM delegates. Rejected for now: it is the GM's call by
  [0006](0006-system-proposes-gm-disposes.md), and the event log records no
  actor, so agent-issued events couldn't be told apart from the GM's.

## Consequences

- Scenarios can be drafted, translated and balanced by an agent; the simulate
  tool makes the engine's purity pay off a second time.
- A second way in that must stay in step with the UI: every new authoring
  function needs a tool, or agents fall behind.
- Tokens are a new secret to protect; a leaked token can edit every scenario
  its user can.
- No new dependency is decided here. Elixir MCP libraries (Hermes MCP, Anubis
  MCP) are young; the protocol is small JSON-RPC, so a hand-written endpoint is
  a real option. Choose when implementing.
- Revisit live control if a real need appears; it would need an actor on
  `SessionEvent` first.

## Open

- Phase 1 tool granularity: one tool per entity type, or a generic
  `upsert_entity(type, key, attrs)`? Should a whole scenario document also be
  importable in one call (which overlaps with copying, [0024](0024-shared-scenario-vs-copies.md))?
- Media upload through MCP, or links to existing media only?
- Can agents create scenarios, or only edit ones a human created?
- Token scopes: is "authoring / observe" enough, or per scenario?

## Sources

- Conversation with Markus, 2026-11-10.
- `lib/scenex/authoring.ex`, `lib/scenex/play.ex`, `lib/scenex/engine/sim.ex`,
  `priv/repo/balance_mars_colony.exs` (balance loop an agent would replace).
