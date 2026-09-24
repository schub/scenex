# Scenex — Architecture

How the system is put together and which properties must not be broken. This
document covers the *shape* and the *why*; the modules themselves document
their own detail, and are linked throughout rather than summarised here.

## 1. The three layers

The single load-bearing idea: **separate the generic engine from game-specific
content, and separate authored content from a live play-through.**

| Layer | What it is | Where it lives | Storage |
|---|---|---|---|
| **1. Engine** | The rules of physics: values, aggregation, conditions, effects. Identical for every game. | `Scenex.Engine` | Code — pure functions, no DB |
| **2. Definition** | One authored scenario: which values, groups, beats, options, endings exist. Reusable. | `Scenex.Authoring` | Plain CRUD in Postgres |
| **3. Session** | One live run of a definition, at one venue, on one day. | `Scenex.Play` | Event-sourced log + in-memory projection |

One definition → **many concurrent, isolated sessions**. The same scenario can
run in several cities at once without the sessions touching each other.

The payoff of the split: the identical engine code drives both the authoring
dry-run (simulate mode) and live play, so a scenario balanced in the editor
behaves the same on the night.

## 2. Contexts

```
Scenex.Accounts     Authentication (phx.gen.auth, magic link) and scopes.
Scenex.Authoring    Layer 2. The definition graph + authorization.
Scenex.Engine       Layer 1. PURE: Sim, Formula, Condition, Index, Scale.
Scenex.Play         Layer 3. Sessions, event log, capability tokens, runtime.
Scenex.Media        Per-scenario media library backing content embeds.
Scenex.I18n         Localized content fields (distinct from Gettext chrome).
```

`Scenex.Engine` depends on neither Ecto nor OTP. `Scenex.Play` is the only
place that wraps it in processes.

## 3. Invariants

These are the properties the design is built on. Changing one is an
architecture decision, not a tweak.

**The engine stays pure.** No Ecto, no processes, no I/O in `Scenex.Engine`.
This is what makes it exhaustively unit-testable and what lets simulate mode
and live play share one implementation.

**The event log is append-only.** `Scenex.Play.SessionEvent` rows are never
updated or deleted. A mistaken decision is corrected by appending a newer one;
the projection folds last-wins per decision slot. This buys undo,
crash-recovery, live charts and cross-venue analytics for free, and it is
expensive to retrofit — it is never cut.

**Global values are derived, never stored.** A global is computed from the
per-group values through that value's aggregation formula, every time. Nothing
writes a global directly.

**The system proposes, the GM disposes.** Nothing fires automatically in a
live show. The GM triggers every beat, adjudicates sidequests, breaks ties and
declares the end. Conditions, deadline defaults and ending matches are
*recommendations*. No dice, no hidden randomness.

**Manual before automatic.** Election votes can always be entered as a GM
hand-count tally; device-based individual voting is an enhancement, never a
dependency. Per-participant values are collected in the room and entered by
the GM.

**One person, one vote.** Vote weight is never derived from game state —
mechanics must not depend on content.

**Mechanics never depend on a specific game.** Any scenario-specific concept
that creeps into the engine is a bug. This is why the old "Democracy Score"
became the scenario-agnostic, author-labelled Overall Index.

**Authorization lives in the context, not the LiveView.** `Scenex.Authoring`
exposes `get_scenario_for_user/2`, `can_edit?/2`, `is_owner?/2`,
`get_user_role/2`. Route reads through `get_scenario_for_user/2`.

**The media URL shape is a permanent contract.** `/media/<id>/<filename>` must
survive any storage-backend change, because authors paste it into markdown.

## 4. Layer 1 — the engine

| Module | Responsibility |
|---|---|
| `Scenex.Engine.Sim` | The pure numeric state: per-group values, clamping, applying effects, deriving globals |
| `Scenex.Engine.Formula` | Aggregation formulas — folds one value's *per-group* numbers into its global (`avg`, `min`, `max`, `median`, `sum`, arithmetic, parens) |
| `Scenex.Engine.Condition` | Gates and ending recommendations — one comparison over `self(key)`, `global(key)`, literals and arithmetic |
| `Scenex.Engine.Index` | The Overall Index formula — combines the *globals of different values* by key into one headline metric |
| `Scenex.Engine.Scale` | Maps a number on a `min..max` range to one of N labelled bands |
| `Scenex.Engine.ValueSpec` | The engine-level projection of a `ValueDimension`, stripped of names and persistence |

`Formula` and `Index` are easy to confuse: `Formula` aggregates *across groups
within one value*; `Index` aggregates *across values*.

Boolean `and`/`or` in conditions is deliberately deferred.

## 5. Layer 2 — the definition

The graph hangs off `Scenex.Authoring.Scenario`. Rather than restate every
field here, see the schema moduledocs under `lib/scenex/authoring/`. The
concepts worth knowing before you read them:

**Handles vs. localized fields.** Every content entity carries a `handle` — a
required, non-translated organizational label, unique within its scope, used
by authors and the GM. Player-facing text lives in separate localized fields.

**`input_scope` on a value.** `:per_group` means each faction holds a number
and the global is aggregated across groups. `:per_participant` means
individuals report it directly (the well-being reality-check); it is collected
as a hand count and rendered through author-defined emoji steps
(`ValueDimensionStep`).

**Effects and the outcome matrix.** An `OptionEffect` with `group_id` nil
means "the deciding group" — that is the event case. A set `group_id` targets
an explicit group, which is how elections and sidequests express a per-group
outcome matrix.

**Director's notes.** A localized, GM-/performer-facing field on nearly every
content entity. Never shown to players.

**Long-form localized fields are Markdown** by convention, rendered through
`ScenexWeb.Markdown`. Not schema-enforced.

## 6. Layer 3 — a live session

```
GM console ─┐                              ┌─→ projected display (LiveView)
Group device ├─(commands)→ SessionServer ──┼─→ group devices
(QR token)  ─┘              │ holds projection
                            │ owns the game clock
                            │ owns timers
                            ├─ append event → Postgres   ← source of truth
                            ├─ fold via Engine → projection  ← derived, in memory
                            └─ PubSub.broadcast → all viewers
        restart? → replay the log on init → identical projection
```

One `Scenex.Play.SessionServer` per running session, supervised by
`Scenex.Play.SessionSupervisor` (a `DynamicSupervisor`) and found by id through
`Scenex.Play.Registry` — both started in `Scenex.Application`.

**Timers run against the game clock, not wall-clock.** The clock is pausable;
`game_time_ms` accumulates while live, and every appended event is stamped
with it. Deadlines and their default consequences are measured in elapsed
*game* time.

**The definition is snapshotted at session start** (`Scenex.Play.Definition`),
so mid-session edits to a scenario don't silently change a running game.

**The fold is pure** (`Scenex.Play.Projection`) and runs identically in the
live process and in replay-on-restart.

### The three screens

| Screen | Route | Access |
|---|---|---|
| GM console | `/sessions/:id/console` | Authenticated, session-scoped |
| Group board | `/play/:token` | Capability token, no login |
| Projected display | `/display/:token` | Capability token, read-only |

Authored content is only ever seen on the display and the group boards. The
console shows the GM everything, including numbers players never see.

## 7. Identity and permissions

**Two tiers.**

*Real accounts* — email plus magic link, via `phx.gen.auth`. Platform admins,
authors, game masters. Few, persistent. Auth is **scope-based**: routes assign
`@current_scope`, and contexts take `current_scope` as their first argument.
Use `@current_scope.user` in templates, never `@current_user`.

*Ephemeral capability tokens* — handed out as QR codes. A token grants access
to exactly one group (or the display) in exactly one session and dies with the
session. No account per player; the scope is baked into the token and the
group id is never taken from the client.

**Roles are scoped to a layer:** scenario membership (`owner` / `author` /
`viewer`) per definition; a session belongs to the author who created it, with
the scenario owner keeping an override as the recovery path for live events.
Scenario roles are unrelated to *playing*.

## 8. Internationalization

This is a data-model decision, not a feature. Two distinct mechanisms:

**UI chrome** — buttons, labels, errors — goes through Gettext.

**Authored content** — value names, group names, narratives, option texts,
endings, director's notes — is stored as a plain `jsonb` map of
`locale => string` and rendered per viewer by `Scenex.I18n`, falling back to
the scenario's `source_locale` and then to any translation that exists, so a
partly-translated game never shows blanks.

**The event log stays language-neutral** — it records which option by id, and
each viewer renders the text.

Supported content locales are listed in `Scenex.I18n` (currently en, de, es,
et, hu, it, no, pl, pt).

## 9. Vocabulary

The code and the UI use different words for timeline element kinds. Both are
current and intentional — the code names are the original design terms, the UI
names are what read better in the room.

| Code (`TimelineElement.kind`) | UI label | Who decides | Whose values move |
|---|---|---|---|
| `:event` | Event | each group separately | the deciding group's own |
| `:election` | **Vote** | all players, one person one vote; GM breaks ties | any groups' (outcome matrix) |
| `:sidequest` | **Wildcard** | one player; GM adjudicates success/failure | any groups' (outcome matrix) |

The mapping lives in `ScenexWeb.CoreComponents.kind_label/1`. The
partner-facing writing guide in `studio/docs/ai-context.md` uses the UI words.

> **Known doc drift:** the moduledoc of `Scenex.Authoring.TimelineElement`
> still says "v1 still treats kinds identically". That is no longer true — the
> editor, simulate mode and the console all handle the three kinds distinctly.
> Worth fixing next time that schema is touched.

## 10. Subsystems beyond the core loop

**Media library** (`Scenex.Media`) — per-scenario images, short video and
audio that authors embed in markdown content by URL. Bytes go through a
swappable `Scenex.Media.Storage` (local disk today); rows live in
`media_files`.

**Scoreboard pages** (`Scenex.Authoring.Page`) — pre-authored full-screen
slides for before a show, onboarding, intermissions. The GM can put one up at
any time regardless of session status; it takes over the display entirely and
never affects game state.

**Overall Index** (`Scenex.Engine.Index` + `Scenex.Authoring.OverallIndexBand`)
— the single derived headline metric a scenario rolls its values up into,
labelled by the author for their setting, with author-defined bands and a
gauge visualization range.

**Session group selection** (`Scenex.Play.SessionGroup`) — picks which of the
scenario's groups play a given session. Fixed at creation: the log replays
against it, so it must never change afterwards.

**Scenario invitations** (`Scenex.Authoring.ScenarioInvitation`) — invite a
collaborator onto a definition by email; accepted at `/invites/:token`.

**QR code PDF** (`ScenexWeb.SessionQrPdfController`) — downloads all of a
session's access QR codes as one printable PDF.

**Demo scenario** (`Scenex.DemoScenario`) — builds the CIVITAS mini-megagame
(alpha v0.2) for an owner; idempotent per user, one transaction.

## 11. Related documents

- [`../README.md`](../README.md) — what Scenex is, and how to run it locally
- [`deployment.md`](deployment.md) — the production VM, env vars, edge proxy
- [`releasing.md`](releasing.md) — branch model, versioning, cutting a release
- [`../AGENTS.md`](../AGENTS.md) — conventions for writing code here
- `studio/docs/concept/` — the game design source material this app models
