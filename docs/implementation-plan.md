# Scenex — Implementation Plan

> **Status:** planning → ready to execute
> **Author of record:** the maintainer (architect / supervisor). Claude writes the code.
> **Hard deadline:** **14 July 2026** — the eve of the first content-creation workshop (which starts 15 July 2026).
> **Today:** 1 July 2026 → build window ≈ **13 days**.
> **Deliverable at deadline:** a *workable beta of the whole system* — both the authoring CMS **and** the live-session engine — polished enough to (a) enter real game content, (b) run small-scale live playtests, and (c) **train partners** on both. Not pixel-perfect; things may change afterward. Little to no further software work is planned after the workshop, so this is effectively the finish line, not a checkpoint.

---

## 1. What we are building

**Scenex** is a multi-tenant web platform for **authoring and running** large, analog, role-based simulation games ("megagames"). Any specific game is **one** definition hosted on the platform; the platform itself is **generic**.

The single most important architectural idea, which everything below serves: **separate the generic engine from game-specific content, and separate authored content from a live play-through.** Three layers:

| Layer | What it is | How it's stored | Analogy |
|---|---|---|---|
| **1. Engine** | The rules of physics: values, aggregation, timeline, effects. Identical for every game. | **Code** (pure functions). | The game's rulebook. |
| **2. Definition** | A specific game — which values, groups, events, decisions exist. Reusable. | **CRUD** in Postgres. | A boxed game on the shelf. |
| **3. Session** | One live run of a definition, at one theatre, on one day, with real players. | **Event-sourced** append-only log + in-memory projection. | Tonight's actual game night. |

One definition → **many concurrent, isolated sessions** (the same game can run in several cities at the same time without touching each other).

---

## 2. Locked decisions (the foundation)

These were settled in discussion and are treated as fixed. Changing one is an architecture decision, not a tweak.

**Domain model**
- **Three layers** as above. Layer 2 is plain CRUD; **only Layer 3 is event-sourced.**
- **Values** carry an **`input_scope`**:
  - `per_group` — each faction holds a number; the global value is derived by aggregating across groups (Stability, Solidarity, Resources, …).
  - `per_participant` — each individual casts a vote; the "global" is aggregated across people (**Well-being**, the reality-check mechanic). Modelled generically via `input_scope`, but constrained to **at most one** per game for v1.
- **Global values are derived**, never entered directly — computed from group/participant values via an **aggregation formula** (mean / min / median / max / arithmetic, parentheses).
- **Sessions are event-sourced.** The live session is a growing, append-only list of facts (event triggered, decision entered, poll closed, deadline lapsed). Every scoreboard number is *derived* by folding the log. Nothing in live play is overwritten — only appended or corrected. This buys us **undo, live charts, crash-recovery, and cross-theatre analytics** for free.
- **One in-memory process per running session** (a `GenServer`) holds the current projection, owns the session's **game clock (pausable)** and **server-side timers**, and broadcasts changes. Sessions are **isolated and concurrent**; a crash or pause in one never touches another. Crash recovery = replay that session's log on process restart.
- **Timers run against a GM-controlled game clock**, not wall-clock. The GM can pause/resume; deadlines and their default (negative) consequences are measured against elapsed *game* time.

**Identity & permissions**
- **Two-tier identity:**
  - **Real accounts** (email + magic-link, `phx.gen.auth`): platform admins, authors, game masters. Few, persistent.
  - **Ephemeral capability tokens** (QR codes): a token grants write access to **exactly one group (or participant) in exactly one session**, expiring with the session. No account per player. The scope is baked into the token, so "a group can only edit its own group" is enforced by the token itself.
- **Roles are scoped to a layer:** platform admin (global) · definition membership `owner / author / viewer` (per definition) · session role `game master / audience` (per session) · capability tokens (per group/participant, per session).

**i18n (decided up front — it's a data-model decision, not a feature)**
- **UI chrome** → standard **Gettext** locale files.
- **Authored game content** → **localized fields** in the Layer-2 schema (value names, group names, event narratives, decision texts, poll wording). Rendered **per-viewer** with **fallback** to the definition's source locale. The event log stays language-neutral (records *which* decision by id; each viewer renders text in their own locale).

**Platform**
- **Multi-tenant**, single hosted platform for all theatres. Internet assumed available.

**Tech stack**
- **Elixir + Phoenix 1.8 + LiveView**, **PostgreSQL**, **Gettext**, minimal JS.
- Chosen on merits: our hardest requirements (one supervised process per session, per-session server-side timers, sub-second push to many viewers, event-sourcing + crash-recovery, concurrent isolated sessions) map **1:1 onto OTP/BEAM**, and LiveView collapses backend+frontend into one codebase — decisive for a 13-day build. The maintainer's Scala/actor-model fluency makes it supervisable and ownable despite being new to Elixir.

**Deployment & tooling**
- Source on **GitHub**; **GitHub Actions** for test/build.
- Image published to **GHCR**; deployed to a self-hosted **Debian VM** via **Docker Compose**, reusing the **existing Postgres container** (new DB + user).
- The app VM sits in a **VLAN** behind a **front VM running nginx that terminates TLS** and proxies in. So: **no Caddy** — the app listens on plain HTTP on the VLAN. nginx must forward **websockets** (Upgrade/Connection headers) and **`X-Forwarded-Proto/Host/For`**; Phoenix endpoint configured with the public `url:` host and correct `check_origin`.
- **Single always-on stateful node** (in-memory session state ⇒ no horizontal replicas). Fine at our scale; multi-node clustering (libcluster + Horde) is a deliberately-deferred "success problem."

---

## 3. Architecture in code

### Contexts (bounded modules)

```
Scenex.Accounts     # auth (phx.gen.auth), scopes  — Layer 2 identity
Scenex.Authoring    # game definitions: games, values, groups, events,
                            #   decisions, effects, translations  — Layer 2 (CRUD)
Scenex.Engine       # PURE functions: apply/2, aggregation, formula eval
                            #   — Layer 1 (no DB, no processes, fully testable)
Scenex.Play         # sessions, event log, capability tokens, runtime
                            #   — Layer 3 (event-sourced)
```

- **`Engine` is the heart and has no dependencies** on Ecto or processes. It is a set of pure functions: `apply(state, event) -> state`, `aggregate(values, formula)`, `Formula.parse/evaluate`. Because it's pure, it's used identically by **simulate mode** (Layer 2 dry-runs) and **live play** (Layer 3), and it's trivially unit-testable.
- **`Play` wraps the Engine with OTP:** a `Session` `GenServer` (one per live session) holds the projection, persists each incoming event to the append-only log, calls `Engine.apply/2` to update its in-memory state, and broadcasts via `Phoenix.PubSub`. A `DynamicSupervisor` + `Registry` manage the fleet of session processes (lookup by `session_id`).

### Runtime shape of one live session

```
GM console ─┐                             ┌─→ Live scoreboard (LiveView)
Group tablet ├─(actions)→ Session GenServer ┼─→ Audience display (LiveView)
(QR token)  ─┘             │  holds projection │
                           │  owns game clock  └─→ other group tablets
                           │  owns timers
                           ├─ append event → Postgres (log)  ← source of truth
                           ├─ Engine.apply/2 → new projection ← derived, in-memory
                           └─ PubSub.broadcast → all viewers
       restart? → replay log on init → projection rebuilt exactly
```

---

## 4. Data model

### Layer 2 — Definition (CRUD, `binary_id` / UUID PKs)

- **`Game`** — a definition. `source_locale`, `visibility` (`draft / invite_only / published`), timestamps. Owned via memberships.
- **`GameMembership`** — `(game, user, role: owner|author|viewer)`.
- **`ValueDefinition`** — belongs to a game. Fields: `key`, **`input_scope` (per_group | per_participant)**, `aggregation_formula` (string), `min`, `max`, `default`, display metadata. **Localized:** `name`, `description`.
- **`Group`** — belongs to a game (a faction). **Localized:** `name`, `description`.
- **`GroupInitialValue`** — `(group, value_definition, initial_number)` — upsert by unique key.
- **`Event`** — belongs to a game; ordered on the timeline (`position`), `trigger` (`manual` by GM for v1), `deadline_seconds` (game-time), default-consequence config. **Localized:** `title`, `narrative`. (Elections & sidequests: **modeled as generic events for v1**; specialized mechanics deferred.)
- **`Decision`** — belongs to an event; optional `group_id` scope; `escalation_type`. **Localized:** `text`.
- **`DecisionEffect`** — `(decision, value_definition, delta, target_scope)` — the deltas a decision applies. `target_scope` lets one decision shift **every** group's values differently (per the game's design). Upsert by unique key.

**Localized fields:** implemented as a `jsonb` map per field, `{ "en" => "...", "de" => "...", "pt" => "..." }`, with a small helper `t(field, locale)` doing per-viewer lookup + fallback to `game.source_locale`. (Chosen over a separate translations table for speed and because the field set is small and read-heavy. Revisit only if a translation-management UI needs per-field status — deferred.)

### Layer 3 — Session (event-sourced)

- **`Session`** — belongs to a `Game` (definition). `status` (`draft → live → paused → ended`), `clock_state` (accumulated game-time + running/paused + last-started-at), venue/label, timestamps.
- **`SessionEvent`** — the **append-only log**. `session_id`, `type` (`session_started`, `event_triggered`, `decision_entered`, `deadline_lapsed`, `poll_opened`, `poll_vote`, `poll_closed`, `correction`, …), `payload` (jsonb), `game_time_ms`, `sequence`, `inserted_at`. **Never updated or deleted** (corrections are appended).
- **`CapabilityToken`** — `session_id`, `scope` (`group:<id>` | `participant`), `role`, `token` (random), `expires_at`. Backs the QR codes.
- *(Projection is in-memory in the `GenServer`.* An optional `SessionSnapshot` for faster restart is **deferred** — logs are tiny at our scale.)

**Note on game content vs. code:** the still-open *value-set debate* (Stability vs. Legitimacy, 4 vs. 5 values) is **Layer-2 content**, authored in the CMS — it does **not** block the software. The generic value model is exactly why. For testing we seed a provisional example definition; finalizing the value set is a content task for the workshop.

---

## 5. i18n approach (concrete)

- `gettext` for all UI strings from commit one (`en` + at least `de`; `pt`, `es`, `it` as content demands).
- Localized content via the `jsonb`-per-field + `t/2` helper described above; **per-viewer locale** (from account preference or a locale switcher; audience display takes locale from its link), **fallback to `source_locale`**.
- Number/date formatting via `Cldr` if time allows; otherwise minimal. RTL not required for launch.

---

## 6. Deployment & tooling (concrete)

- **CI (GitHub Actions):** Postgres service container → `mix deps.get` → `mix compile --warnings-as-errors` → `mix format --check-formatted` → `mix test` (≈ our `precommit`); optional `credo`. Runs on push/PR.
- **CD:** on merge to `main`, build a multi-stage Docker image (compile `mix release` → slim runtime) → push to **GHCR** → deploy step SSHes to the VM, `docker compose pull && up -d`. Migrations run on release boot. (Manual-approval deploy at first if preferred.)
- **VM compose:** app container on the same Docker network as the existing Postgres container; app DB + user provisioned once.
- **Edge nginx** (front VM) — required snippet on the app's location:
  ```nginx
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header X-Forwarded-Host  $host;
  proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
  ```
  Phoenix prod endpoint: `url: [scheme: "https", host: "<public-host>", port: 443]`, `Plug.RewriteOn` for proto/host, and `check_origin` set to the public host (else websockets connect-then-close).
- **De-risk early:** stand up the *full deploy path* (empty Phoenix app → GHCR → VM → through the two-hop proxy, with a working LiveView websocket) on **Day 1–2**, not Day 13. The proxy/websocket/TLS chain is the classic thing that eats a day; find that day now.

---

## 7. The 13-day build schedule

Days are indicative, not contractual; the **phase order** is what matters. Highest-risk work (the live event-sourced session engine) is front-loaded behind an early-de-risked deploy and a proven pure Engine.

### Phase 0 — Foundations + deploy path *(Day 1)*
- `git init`; `mix phx.new dev/scenex --binary-id` (Phoenix 1.8, LiveView default); base config, `docs/` already present.
- `phx.gen.auth` (magic-link) + scopes; Gettext initialized.
- GitHub repo + Actions CI green; Dockerfile + release; **deploy hello-world LiveView to the VM through the edge proxy** and confirm the websocket connects over HTTPS. **Infra de-risked before feature work.**

### Phase 1 — Definition CMS + Engine core *(Days 2–5)*
- `Authoring` context + schemas (Game, membership, ValueDefinition w/ `input_scope`, Group, GroupInitialValue, Event, Decision, DecisionEffect) with **localized `jsonb` fields** and the `t/2` helper.
- LiveView CRUD for the whole definition graph (create a game; add values/groups/events/decisions/effects; set initial values). Authorization in the context (`can_edit?/2`, membership roles).
- **`Engine` (pure):** `Formula` parser/evaluator (crib the proven approach from the `planex` prototype), `aggregate/2`, `apply/2`, effect resolution across groups, clamping to min/max. **Heavy unit tests** — this is the core.

### Phase 2 — Simulate / test mode *(Days 6–7)*
- A CMS "dry-run" view: load a definition into an in-memory state, feed decisions/events manually, watch group + global values update via the **same `Engine`**. Enormous for workshop content-testing, and it validates the engine end-to-end **before** any realtime wiring. (This is also where authors "balance" a scenario.)

### Phase 3 — Live session engine (Layer 3) *(Days 8–11)*
The hard core. Built on the now-proven Engine + deploy path.
- `Play` context: `Session`, `SessionEvent` (append-only), `CapabilityToken`.
- **`Session` `GenServer`** + `DynamicSupervisor` + `Registry`: persist event → `Engine.apply/2` → broadcast via PubSub. **Replay-on-init** crash recovery.
- **Game clock** (pause/resume) + **server-side timers** (`Process.send_after` on game-time) firing **default consequences** on lapsed deadlines.
- **GM console** LiveView: start a session from a definition, trigger events, enter decisions, pause/resume, correct mistakes (append correction → recompute).
- **Live scoreboard** LiveView (group + derived global values, updating sub-second).
- **Capability tokens + QR generation**; **group-input** LiveView (token-scoped, edits only its own group).
- **Audience display** LiveView: read-only, projectable, public-link/token, no login.
- Concurrency check: two sessions of the same definition running isolated in parallel.

### Phase 4 — Well-being poll + i18n pass + polish *(Days 12–13, morning)*
- **Well-being** (`per_participant`): open/close a voting window, collect anonymous votes (one per participant token or open window), aggregate, and show the **reality-check comparison** (felt well-being vs. computed globals) on the scoreboard.
- i18n content pass + fallback verification; German UI; seed a provisional **example** definition for playtesting.
- UX polish sufficient for **training** (clear GM console, legible displays).

### Phase 5 — Hardening + rehearsal + partner docs *(Day 13, remainder + buffer)*
- End-to-end rehearsal: author → deploy → run a small live playtest through QR input, live scoreboard, clock pause, a timer firing a consequence, a well-being poll, the audience display.
- Short partner-facing guides: **"How to author a game"** and **"How to run a show."**
- Buffer for the inevitable.

---

## 8. Definition of Done (workshop beta)

- [ ] Author **and translate** a full game definition in the CMS (values w/ input_scope, groups, initial values, events, decisions, effects).
- [ ] **Simulate** a scenario in-CMS and see values evolve.
- [ ] Run a **live playtest end-to-end**: start a session from a definition; GM triggers events; groups/GM enter decisions (incl. via **QR**); **live scoreboard** updates for all viewers; **clock pauses/resumes**; a **deadline timer fires a default consequence**; a **well-being poll** runs and is compared to computed globals; **audience display** works.
- [ ] **Two sessions run concurrently, isolated.**
- [ ] A session **survives an app restart** (log replay).
- [ ] Deployed on the VM, reachable via the edge proxy over **HTTPS**, websockets working.
- [ ] Polished enough to **train partners** on authoring and running a show.

---

## 9. Risks & cut-lines

**Top risks (mitigation)**
1. **Live session engine — timers, clock, crash-recovery, concurrency** (Phase 3). *Mitigation:* front-loaded; built on a pre-proven pure Engine and a Day-1 deploy path; OTP makes the process model native.
2. **Two-hop proxy / websocket / TLS** breaking realtime. *Mitigation:* de-risked Day 1, not discovered Day 13.
3. **Scope vs. 13 days.** *Mitigation:* the cut-lines below; the event-sourced core is *never* cut (expensive to retrofit).

**Cut-lines, in the order they'd be dropped if behind:**
1. Audience-display *styling* (keep it functional/ugly).
2. Well-being poll *polish* (keep the mechanic, simplify the UI).
3. Cross-theatre **analytics UI** — the *data* is captured in the logs from day one; only the analysis views wait.
4. Translation-status dashboard.
5. Elections/sidequests as *special* mechanics (stay generic events).
6. `Cldr` number/date niceties.

**Never cut:** the three-layer split, the pure `Engine`, event-sourcing for Layer 3, i18n-ready schema, the two-tier identity model. These are the load-bearing decisions.

---

## 10. Immediate next action

Scaffold Phase 0: `mix phx.new dev/scenex --binary-id`, `phx.gen.auth`, CI green, and a hello-world LiveView deployed through the VM's edge proxy to prove the websocket path — **before** any feature work.

> **Name decided:** the platform is **Scenex** — OTP app `scenex`, modules `Scenex` / `ScenexWeb`. Individual games are content definitions inside it, not the platform.
