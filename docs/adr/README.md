# Architecture decision records

Why Scenex is built the way it is. One file per decision, numbered in the order
the decisions were made. [`architecture.md`](../architecture.md) describes the
system as it is now; an ADR records *why* one part of it was chosen, what the
alternatives were, and what it costs.

## Rules

- **An ADR is never rewritten once accepted.** A changed decision gets a new
  ADR that supersedes the old one; the old one only gets its status updated.
- **Don't invent rationale.** Most of these were written in reverse on
  2026-10-28. Where the reason is documented (commit message, the former
  implementation plan), it is quoted or paraphrased and the source is linked.
  Where it isn't, the ADR says so under *Open* instead of guessing.
- Short is fine. Copy [`template.md`](template.md).

The former implementation plan, removed in `bcb7b57`, is the richest source for
the early decisions: `git show bcb7b57^:docs/implementation-plan.md`, §2
"Locked decisions" and §9 "Never cut".

## Index

Status: **Accepted** · **Accepted, rationale open** (decision is in force, the
*why* still needs Markus) · **Proposed** · **Superseded**.

| # | Decision | Date | Status |
|---|---|---|---|
| [0001](0001-three-layers.md) | Three layers: engine, definition, session | 2026-07-01 | Accepted, rationale open |
| [0002](0002-pure-engine.md) | The engine is pure and shared by simulate mode and live play | 2026-07-02 | Accepted |
| [0003](0003-localized-content-as-jsonb.md) | Authored content is localized as `jsonb` maps; chrome uses Gettext | 2026-07-02 | Accepted, rationale open |
| [0004](0004-untranslated-handles.md) | Every content entity has an untranslated handle | 2026-07-02 | Superseded by 0023 |
| [0005](0005-derived-globals.md) | Global values are derived, never stored | 2026-07-02 | Accepted, rationale open |
| [0006](0006-system-proposes-gm-disposes.md) | The system proposes, the GM disposes | 2026-07-03 | Accepted, rationale open |
| [0007](0007-manual-before-automatic.md) | Manual before automatic | 2026-07-03 | Accepted, rationale open |
| [0008](0008-outcome-matrix.md) | Effects target the deciding group or an explicit group (outcome matrix) | 2026-07-03 | Accepted, rationale open |
| [0009](0009-event-sourced-sessions.md) | Live sessions are event-sourced | 2026-07-04 | Accepted |
| [0010](0010-definitions-are-plain-crud.md) | Only sessions are event-sourced; definitions are plain CRUD | 2026-07-04 | Accepted, rationale open |
| [0011](0011-definition-snapshot.md) | A session runs on a snapshot of its definition | 2026-07-04 | Accepted |
| [0012](0012-game-clock.md) | Timers run on a pausable game clock, not wall-clock | 2026-07-04 | Accepted, rationale open |
| [0013](0013-capability-tokens.md) | Players get capability tokens, not accounts | 2026-07-04 | Accepted, rationale open |
| [0014](0014-invitation-only-registration.md) | Registration is invitation-only | 2026-07-05 | Accepted, rationale open |
| [0015](0015-session-belongs-to-creator.md) | A session belongs to its creator; the owner keeps an override | 2026-07-05 | Accepted |
| [0016](0016-release-model.md) | Releases: `-dev` versions, `--no-ff` merge to `main`, one script | 2026-07-06 | Accepted |
| [0017](0017-corrections-are-the-gms.md) | Groups confirm once; corrections are the GM's alone | 2026-07-06 | Accepted, rationale open |
| [0018](0018-session-play-language.md) | Each session has a play language; console and editor stay English | 2026-07-12 | Accepted, rationale open |
| [0019](0019-permanent-media-urls.md) | `/media/<id>/<filename>` is a permanent URL contract | 2026-07-12 | Accepted |
| [0020](0020-session-groups-and-archiving.md) | Sessions select their groups; played groups are archived, not deleted | 2026-07-18 | Accepted |
| [0021](0021-ui-vocabulary-vote-wildcard.md) | Code says election/sidequest, the UI says Vote/Wildcard | 2026-07-28 | Accepted |
| [0022](0022-overall-index.md) | A scenario-agnostic Overall Index replaces the Democracy Score | 2026-08-28 | Accepted |
| [0023](0023-key-name-title-vocabulary.md) | One vocabulary: key, name, title, description | 2026-10-28 | Accepted |
| [0024](0024-shared-scenario-vs-copies.md) | One shared scenario per game, or copies? | — | Proposed |
| [0025](0025-license.md) | License for the code (and the content) | — | Proposed |
| [0026](0026-metrics-prometheus-grafana.md) | Platform metrics: Prometheus format via PromEx, viewed in Grafana | 2026-11-09 | Accepted |
| [0027](0027-mcp-server.md) | An MCP server lets agents author scenarios and observe live shows | — | Proposed |
