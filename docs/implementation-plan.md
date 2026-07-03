# Scenex — Implementation Plan

> **Status:** in execution — Phases 0–2 built; design hardened; Phase 2.5 (design alignment) is next.
> **Author of record:** the maintainer (architect / supervisor). Claude writes the code.
> **Hard deadline:** **14 July 2026** — the eve of the first content-creation workshop (which starts 15 July 2026).
> **Today:** 3 July 2026 → remaining build window ≈ **11 days**.
> **Deliverable at deadline:** a *workable beta of the whole system* — both the authoring CMS **and** the live-session engine — polished enough to (a) enter real game content, (b) run small-scale live playtests, and (c) **train partners** on both. Not pixel-perfect; things may change afterward. Little to no further software work is planned after the workshop, so this is effectively the finish line, not a checkpoint.
>
> **Authoritative mechanics spec:** the game design document (`docs/concept/game-design-concept-and-mechanics.md` in the parent project). This plan maps those mechanics onto software; where the two disagree, the design document wins.

---

## 1. What we are building

**Scenex** is a multi-tenant web platform for **authoring and running** large, analog, role-based simulation games ("megagames") staged as theatrical performances. Any specific game is **one** definition hosted on the platform; the platform itself is **generic**.

The single most important architectural idea, which everything below serves: **separate the generic engine from game-specific content, and separate authored content from a live play-through.** Three layers:

| Layer | What it is | How it's stored | Analogy |
|---|---|---|---|
| **1. Engine** | The rules of physics: values, aggregation, conditions, effects. Identical for every game. | **Code** (pure functions). | The game's rulebook. |
| **2. Definition** | A specific game — which values, groups, events, options, endings exist. Reusable. | **CRUD** in Postgres. | A boxed game on the shelf. |
| **3. Session** | One live run of a definition, at one venue, on one day, with real players. | **Event-sourced** append-only log + in-memory projection. | Tonight's actual game night. |

One definition → **many concurrent, isolated sessions** (the same game can run in several cities at the same time without touching each other).

---

## 2. Locked decisions (the foundation)

Settled in discussion and treated as fixed. Changing one is an architecture decision, not a tweak.

**Game mechanics** (full spec in the game design document; the load-bearing points):

- **Three timeline element kinds, three social scales.** This symmetry drives the model:

  | Kind | Who decides | Whose values change |
  |---|---|---|
  | **Event** | each group separately | the deciding group's own values |
  | **Election** | all players (one person, one vote; majority; GM breaks ties) | any groups' values (**outcome matrix**: per-group deltas authored per option) |
  | **Sidequest** | one player; **GM adjudicates** success/failure | any groups' values (outcome matrix per outcome bundle) |

- **Conditional options ("gates").** Any option may carry a condition on game state — `self(key)` (deciding group's value; event options only) and `global(key)`, one comparison, arithmetic allowed. Unmet options are **shown greyed-out with the reason, never hidden**.
- **Endings.** Authored final scenes with optional conditions on the final globals + priority. At game end the system **recommends** matching endings; **the GM picks and may override**. Endings apply no effects.
- **Director's notes (`director_notes`).** A localized, GM-/performer-facing text field on nearly every content entity. Never shown to players.
- **The system proposes, the GM disposes.** Nothing fires automatically in a live show: the GM triggers every timeline element, adjudicates sidequests, breaks ties, declares the end. Conditions, defaults, and ending matches are *recommendations*. No dice, no hidden randomness.
- **Manual before automatic.** Election votes can always be entered as a GM hand-count tally; device-based individual voting is an enhancement, not a dependency. Well-being is collected analog (smiley coins) and entered by the GM.
- **One person, one vote.** Vote weight is never derived from game state (mechanics must never depend on content).

**Domain model**

- **Three layers** as above. Layer 2 is plain CRUD; **only Layer 3 is event-sourced.**
- **Values** carry an **`input_scope`**:
  - `per_group` — each faction holds a number; the global value is derived by aggregating across groups.
  - `per_participant` — individuals report it directly (the well-being reality-check); at most one per game for v1. Bounds (`min`/`max`/`default`) apply to per-group values only.
- **Global values are derived**, never entered directly — computed via an **aggregation formula** (mean / min / median / max / sum, arithmetic, parentheses). Values are clamped to their `min`/`max` range.
- **Every content entity carries a `handle`** — a required, non-translated organizational label, unique within its scope; localized fields hold the player-facing content.
- **Author-defined labels** (name + color + icon, game-scoped, reusable) categorize options — presentation-only, no mechanical weight.
- **Sessions are event-sourced.** The live session is a growing, append-only list of facts (event triggered, option chosen, tally entered, sidequest adjudicated, ending selected). Every scoreboard number is *derived* by folding the log. Nothing in live play is overwritten — only appended or corrected. This buys **undo, live charts, crash-recovery, and cross-venue analytics** for free.
- **One in-memory process per running session** (a `GenServer`) holds the current projection, owns the session's **game clock (pausable)** and **server-side timers**, and broadcasts changes. Sessions are **isolated and concurrent**. Crash recovery = replay the log on restart.
- **Timers run against a GM-controlled game clock**, not wall-clock. Deadlines and their default consequences are measured against elapsed *game* time.

**Identity & permissions**

- **Two-tier identity:**
  - **Real accounts** (email + magic-link, `phx.gen.auth`): platform admins, authors, game masters. Few, persistent.
  - **Ephemeral capability tokens** (QR codes): a token grants write access to **exactly one group (or participant) in exactly one session**, expiring with the session. No account per player; scope baked into the token.
- **Roles are scoped to a layer:** platform admin (global) · definition membership `owner / author / viewer` (per definition) · session role `game master` (per session) · capability tokens (per group/participant, per session).

**i18n (a data-model decision, not a feature)**

- **UI chrome** → **Gettext** locale files.
- **Authored content** → **localized `jsonb` fields** (`%{"en" => …, "de" => …}`) on names, narratives, option texts, endings, **and director's notes** — rendered per-viewer with fallback to the definition's `source_locale`. The event log stays language-neutral (ids, not text).

**Platform / tech / deployment** *(unchanged)*

- **Multi-tenant**, single hosted platform. **Elixir + Phoenix 1.8 + LiveView**, **PostgreSQL**, **Gettext**, minimal JS — the per-session process / timers / realtime-push / event-sourcing requirements map 1:1 onto OTP.
- GitHub + Actions CI → GHCR image → self-hosted Debian VM via Docker Compose, reusing the existing Postgres container. App VM in a VLAN behind an nginx front VM terminating TLS (websocket upgrade headers + `X-Forwarded-*` + `check_origin` on the public host). **Single always-on stateful node**; clustering is a deferred success-problem.

---

## 3. Architecture in code

### Contexts

```
Scenex.Accounts     # auth (phx.gen.auth), scopes — Layer 2 identity
Scenex.Authoring    # game definitions: scenarios, values, groups, timeline elements,
                    #   options, effects, labels, endings — Layer 2 (CRUD)
Scenex.Engine       # PURE: Sim (state + effects + clamping), Formula
                    #   (aggregation), Condition (gates/endings evaluation)
                    #   — Layer 1 (no DB, no processes)
Scenex.Play         # sessions, event log, capability tokens, runtime
                    #   — Layer 3 (event-sourced)
```

- **`Engine` has no dependencies** on Ecto or processes. Pure functions used identically by the CMS dry-run (Layer 2) and live play (Layer 3): `Sim.new/apply_effect/globals`, `Formula.parse/evaluate`, and (new) `Condition.parse/evaluate` for gates and ending recommendations.
- **`Play` wraps the Engine with OTP:** a `Session` `GenServer` per live session persists each event to the append-only log, folds it into the in-memory projection via the Engine, and broadcasts via `Phoenix.PubSub`. `DynamicSupervisor` + `Registry` manage the fleet.

### Runtime shape of one live session

```
GM console ─┐                              ┌─→ Live scoreboard (LiveView)
Group device ├─(actions)→ Session GenServer ┼─→ projected display (LiveView)
(QR token)  ─┘             │ holds projection │
                           │ owns game clock  └─→ other group devices
                           │ owns timers
                           ├─ append event → Postgres (log)   ← source of truth
                           ├─ Engine fold  → new projection   ← derived, in-memory
                           └─ PubSub.broadcast → all viewers
        restart? → replay log on init → projection rebuilt exactly
```

---

## 4. Data model

### Layer 2 — Definition (CRUD, `binary_id` PKs; localized fields are `jsonb` maps)

Built (✓) or planned (＋):

- ✓ **`Scenario`** — `handle`, `source_locale`, `visibility` (`draft/invite_only/published`). Localized: `name`, `description`. ＋ `director_notes`.
- ✓ **`ScenarioMembership`** — `(scenario, user, role: owner|author|viewer)`.
- ✓ **`ValueDimension`** — `key` (slug, unique per scenario), `input_scope`, `aggregation` formula, `min`/`max`/`default_value`, `position`. Localized: `name`, `description`. ＋ `director_notes`.
- ✓ **`Group`** — `handle` (unique per scenario), `position`. Localized: `name`, `description`. ＋ `director_notes`.
- ✓ **`GroupInitialValue`** — `(group, value_dimension, initial)`, upsert by unique key.
- ✓ **`TimelineElement`** — `handle` (unique per scenario), `position`, **`kind` (`event | election | sidequest`)**, `trigger` (`manual`), `deadline_seconds`. Localized: `title`, `narrative`. ＋ `director_notes`. Kind determines the mechanics (see below); v1 currently treats kinds identically — **that changes in Phase 2.5**.
- ✓ **`DecisionOption`** — belongs to timeline element; `handle` (unique per timeline element), `is_default`, `position`. Localized: `text`. ＋ `director_notes`, ＋ **`condition`** (gate string, nullable). For **event** kind: `group_id` required (the deciding group). For **election** kind: `group_id` nil (options belong to the whole room). For **sidequest** kind: exactly two options — the `success` and `failure` outcome bundles (failure may be effect-less).
- ✓ **`OptionEffect`** — `(option, value_dimension, delta)`, upsert by unique key. ＋ **optional `group_id`**: `nil` = "the deciding group" (event options); set = explicit target group (**the outcome matrix** for election and sidequest options).
- ✓ **`Label`** + join table — scenario-scoped, reusable, presentation-only (name, color, icon).
- ＋ **`Ending`** — belongs to scenario; `handle`, `priority`, **`condition`** (on globals, nullable). Localized: `title`, `narrative`, `director_notes`.

**Condition language (Engine.Condition):** one comparison (`>= <= > < == !=`) between two arithmetic expressions over `self(key)`, `global(key)`, and numbers. `self()` is invalid on election options and endings (no single deciding group). Boolean `and/or` deferred.

### Layer 3 — Session (event-sourced)

- **`Session`** — belongs to a `Scenario`. `status` (`draft → live → paused → ended`), `clock_state`, venue label, chosen `ending_id` (set at the end).
- **`SessionEvent`** — the **append-only log**: `session_id`, `type`, `payload` (jsonb), `game_time_ms`, `sequence`. Types include: `session_started`, `event_triggered`, `option_chosen`, `deadline_lapsed` (default applied), `election_opened`, `vote_tally_entered` *(or `vote_cast` for device voting)*, `election_resolved`, `sidequest_assigned`, `sidequest_adjudicated`, `wellbeing_tally_entered`, `correction`, `session_ended`, `ending_selected`. **Never updated or deleted.**
- **`CapabilityToken`** — `session_id`, `scope` (`group:<id>` | `participant`), `token`, `expires_at`. Backs the QR codes. Group tokens are core; participant tokens (device voting) are an enhancement.
- *(Projection lives in the `GenServer`; snapshots deferred — logs are tiny at our scale.)*

**Game content vs. code:** the value-set debate (which values, 4 vs 5) is **Layer-2 content** and does not block software. A full example definition is seeded from the legacy paper-prototype content for testing and demos.

---

## 5. i18n approach *(unchanged, plus notes)*

- `gettext` for UI strings (`en` + `de` minimum; `pt`, `es`, `it` as content demands).
- Localized content via `jsonb`-per-field + the `I18n.t` helper, per-viewer locale, fallback to `source_locale`. **Director's notes are localized like any other content field.**
- Long-form localized fields are **Markdown** by convention (rendered, not schema-enforced).

---

## 6. Deployment & tooling *(unchanged)*

- **CI:** Postgres service → `mix deps.get` → compile `--warnings-as-errors` → format check → `mix test`. On push/PR.
- **CD:** merge to `main` → multi-stage image (`mix release`) → GHCR → SSH deploy, `docker compose pull && up -d`. Migrations on boot.
- **Edge nginx** needs websocket upgrade headers + `X-Forwarded-Proto/Host/For`; Phoenix prod endpoint gets the public `url:` host and `check_origin`. Details in `docs/deployment.md`.
- ⚠️ **The full deploy path is still unproven** (blocked on public hostname + push approval from the maintainer). This was meant to be Day-1 de-risking; it is now the **oldest open risk** — do it at the first opportunity, before Phase 3 realtime work depends on it.

---

## 7. Build schedule (revised)

Progress so far, then the remaining ~11 days. Phase order matters more than day numbers.

### ✓ Phase 0 — Foundations *(done)*
Phoenix 1.8 scaffold (`binary_id`), `phx.gen.auth` (magic link) + scopes, Gettext, landing page. **Deploy de-risk still outstanding — see §6.**

### ✓ Phase 1 — Definition CMS + Engine core *(done)*
- Pure `Engine`: `Formula` parser/evaluator, `ValueSpec`, `Sim` (seeding, clamping, effects, derived globals). Heavily unit-tested.
- `Authoring` context + all Layer-2 schemas above (✓ items), localized fields, handles with scoped uniqueness, labels, upsert helpers, context-level authorization.
- CMS editor LiveViews: game settings, values (scope-aware bounds), groups, initial-values grid, events → options → effects, labels. Working-locale switcher.

### ✓ Phase 2 — Simulate / dry-run *(done)*
Ephemeral what-if view driving the same pure Engine: pick options per group per event, watch per-group values + derived globals recompute; clamp flags; reset. Validated against seeded example content.

### ＋ Phase 2.5 — Design alignment *(Days 1–3 of the remaining window)*
Bring the software up to the hardened game design:
1. **`Engine.Condition`** — parse/evaluate the gate language (pure, test-first; powers gates, ending recommendations, and future GM hints).
2. **Schema migrations:** `director_notes` on content entities; `condition` on options; optional `group_id` on `OptionEffect` (outcome matrices); `Ending` entity; election options without group; sidequest success/failure option pairs.
3. **CMS:** election option editor with the **per-group effect matrix grid**; sidequest editor (outcome bundles); endings editor; director's-notes fields; condition input with validation.
4. **Dry-run upgrade:** elections (pick a winner → matrix applies), gates (locked options greyed out with reason), sidequest adjudication (choose success/failure + assignee group), ending recommendations at the end. The dry-run becomes a full content-balancing tool for the workshop.

### ＋ Phase 3 — Live session engine (Layer 3) *(Days 4–8)*
The hard core, built on the proven Engine.
- `Play` context: `Session`, `SessionEvent` (append-only), `CapabilityToken`.
- `Session` `GenServer` + `DynamicSupervisor` + `Registry`: persist event → fold → broadcast. **Replay-on-init** crash recovery.
- **Game clock** (pause/resume) + server-side timers firing **default consequences** on lapsed deadlines.
- **GM console:** start session, trigger timeline elements, enter group decisions, **run elections** (open → GM-entered hand-count tally → resolve matrix; tie = GM picks), **assign & adjudicate sidequests**, pause/resume, append corrections, **declare end → see recommended endings → select one**.
- **Live scoreboard** (groups + globals, sub-second updates) and a read-only **projected display** (public link, no login).
- **Capability tokens + QR**; group-input LiveView (token-scoped: a group enters its own event decisions).
- Concurrency check: two isolated sessions of one definition in parallel.

### ＋ Phase 4 — Well-being + i18n pass + polish *(Days 9–10)*
- **Well-being** (`per_participant`): collected analog (smiley coins), **GM enters the tally**; the scoreboard shows the reality-check comparison (felt vs. computed). Device-based collection only if time allows.
- i18n content pass + fallback verification; German UI.
- UX polish sufficient for **training** (clear GM console, legible displays).

### ＋ Phase 5 — Hardening + rehearsal + partner docs *(Day 11 + buffer)*
- End-to-end rehearsal: author → dry-run → live playtest (QR input, election with tally, sidequest, deadline default firing, clock pause, ending selection, projected display).
- Short partner guides: **"How to author a game"** / **"How to run a show."**
- Buffer for the inevitable.

---

## 8. Definition of Done (workshop beta)

- [ ] Author **and translate** a full definition in the CMS: values, groups, initial values, **events, elections (with outcome matrices), sidequests, endings, conditions, labels, director's notes**.
- [ ] **Dry-run** a scenario end-to-end in the CMS: gates lock/unlock, elections apply matrices, sidequests adjudicate, endings get recommended.
- [ ] Run a **live playtest end-to-end**: GM triggers elements; groups enter decisions via **QR**; an **election** resolves from a GM tally; a **sidequest** is assigned and adjudicated; a **deadline fires a default consequence**; the **clock pauses/resumes**; the **well-being tally** is entered and compared; the GM **ends the session and selects a recommended ending**; scoreboard + projected display update live.
- [ ] **Two sessions run concurrently, isolated.** A session **survives an app restart** (log replay).
- [ ] Deployed on the VM, reachable via the edge proxy over **HTTPS**, websockets working.
- [ ] Polished enough to **train partners** on authoring and running a show.

---

## 9. Risks & cut-lines

**Top risks**
1. **Live session engine** (timers, clock, crash-recovery, concurrency) — front-loaded right after design alignment; OTP makes the process model native; Engine already proven by the dry-run.
2. **Deploy path unproven** (two-hop proxy / websocket / TLS) — the oldest open item; blocked on maintainer input; do it before Phase 3 realtime work.
3. **Scope vs. 11 days** — mitigated by the cut-lines; the event-sourced core is never cut (expensive to retrofit).

**Cut-lines, in drop order if behind:**
1. Projected-display and scoreboard *styling* (functional over pretty).
2. **Device-based individual voting** (elections keep the GM hand-count tally — the design guarantees this fallback anyway).
3. Well-being *digital collection* (GM tally entry stays).
4. Cross-venue **analytics UI** (the logs capture the data from day one; views can wait).
5. **Ending auto-recommendation** (GM picks manually from the list; conditions evaluated later).
6. Translation-status dashboard; `Cldr` niceties.

**Never cut:** the three-layer split, the pure `Engine` (incl. `Condition`), event-sourcing for Layer 3, i18n-ready schema (incl. `director_notes`), the two-tier identity model, the outcome-matrix model. These are load-bearing.

---

## 10. Immediate next action

**Phase 2.5, step 1:** implement `Engine.Condition` (pure parser/evaluator for the gate language), test-first — it unblocks gates, endings, and the dry-run upgrade. In parallel, when the maintainer supplies the public hostname and push approval: prove the full deploy path (§6).

> **Name decided:** the platform is **Scenex** — OTP app `scenex`, modules `Scenex` / `ScenexWeb`. Individual games are content definitions inside it, not the platform.
