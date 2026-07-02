# Scenex — Game Design

This document specifies the *generic* game mechanics that Scenex implements.
It is software-free: it describes rules, roles, and dramaturgy, not schemas or
code. Specific games (values, groups, events, texts) are **content** authored
on top of these mechanics.

## 1. What kind of game this is

Scenex games are **megagames staged as theatrical performances**: large,
role-based simulation games about collective decision-making under pressure,
run live in front of — and *with* — the people in the room.

- **The audience is the players.** Everyone present (typically 30–60 people)
  is assigned to a group and plays. There is no passive spectator tier.
- **The game master (GM) is the director.** The GM controls pacing, triggers
  events, adjudicates outcomes, and steers the dramaturgy. Performers may
  support the GM in character.
- **The system is the instrument, not the play.** It keeps score, makes
  consequences visible, and remembers everything. The drama happens between
  people; the system never generates it and never takes control.

### Design principles

1. **The system proposes, the GM disposes.** Every automated evaluation
   (conditions, defaults, ending recommendations) is a recommendation. The GM
   can always decide otherwise.
2. **Core mechanics never depend on specific content.** No rule may reference
   a particular value, group, or event by name. Anything content-specific
   belongs in the game definition, not the mechanics.
3. **One person, one vote.** Collective decisions are egalitarian. Voting
   power is never derived from game state.
4. **Manual before automatic.** Nothing fires on its own during a show. A
   hand count must always be able to replace a device; a GM decision must
   always be able to replace an automation.
5. **All content is localized.** Every authored text — player-facing and
   GM-facing — exists per locale with fallback, so the same game can run in
   different countries.

## 2. Core model

### Values

A **value** is an abstract metric the game tracks (e.g. stability,
solidarity, resources, risk — whatever the game defines).

- Values are held **per group**. Each group has its own current number for
  each value.
- Each value may define a **min/max range**; per-group values are clamped to
  it. Effects that would push past the bound are absorbed by it.
- Each value defines an **aggregation formula** (`min`, `max`, `avg`,
  `median`, `sum`, combinable with arithmetic) that derives a single
  **global value** from the per-group values. Globals are always derived —
  never stored, never edited directly. The only way to move a global is to
  move per-group values.
- A value's **input scope** is either *per group* (the normal case: the
  group's number changes through decisions) or *per participant*
  (individuals report it directly, e.g. a personal well-being reading;
  collected at runtime, not derived from group play).

### Groups

A **group** is a player faction with its own profile:

- **Starting values** express the group's identity numerically (asymmetric
  starting positions instead of asymmetric rules).
- Narrative profile (goal, tensions, guiding questions) is content that
  shapes role-play; it has no mechanical weight.

### Timeline

A game is an **ordered timeline of events**, triggered manually by the GM.
The order is authored; the GM decides *when* (and whether) each event fires,
adapting pacing to the room.

Events may carry a **deadline**: a time window (measured against the game
clock) for the decision it demands. If the deadline lapses, the authored
**default option** becomes the decision. Time pressure is a core dramatic
device: not deciding is also a decision, and the world makes it for you.

## 3. The three event kinds

Each event kind operates at a different social scale. This symmetry is the
backbone of the design:

| Kind          | Who acts               | Scale       |
| ------------- | ---------------------- | ----------- |
| **Event**     | each group separately  | group       |
| **Election**  | all players together   | collective  |
| **Sidequest** | one individual player  | individual  |

### 3.1 Events (group scale)

A crisis or development that demands a response from each group.

- Each group receives its own set of **decision options** (typically 2–4).
- After internal discussion, the group picks one option.
- The chosen option's **effects** (deltas per value) apply to **the deciding
  group's own values only**. Globals shift indirectly through aggregation.
- Options may carry **labels** (author-defined, e.g. escalation markers) —
  presentation and discussion aids with no mechanical weight.

Groups affect each other *socially* (negotiation between events) and
*mathematically* (through the shared globals) — never by directly editing
another group's values.

### 3.2 Elections (collective scale)

The moment the whole room decides one question together. Elections are the
mechanical expression of intergroup politics: because outcomes are
asymmetric, groups have opposing stakes in the same result and must campaign,
persuade, ally, and betray.

Procedure:

1. **Discussion phase** — an open negotiation window (the deadline mechanic,
   reused as campaign time).
2. **Vote** — every player casts one vote on the same set of options.
   Majority wins. One person, one vote, regardless of group or game state.
3. **Tie** — the GM breaks it (director's power).
4. **Consequence** — the winning option applies an **asymmetric effect
   matrix**: per-group deltas, authored per option. An election creates
   winners and losers; an outcome that hits everyone identically is
   dramaturgically dead and should be avoided by authors (the mechanics
   allow it, the craft advises against it).

Vote collection is implementation-neutral: individual devices where
available, a GM-entered hand-count tally always as fallback. A show never
depends on connectivity.

### 3.3 Sidequests (individual scale)

A task given to a **single player**, creating subplots and spotlight moments
while the main timeline breathes.

- **Assignment** happens at runtime: the GM picks the player (and thereby the
  group). A sidequest may optionally be authored as bound to a specific
  group; by default it is assignable to anyone.
- **Secret or public** is a social choice, not a mechanical one. The GM
  decides how to hand it over (guided by the author's director's notes); the
  player decides whom to tell. Secrecy, disclosure, and betrayal are played,
  not enforced.
- **Resolution:** the GM adjudicates success or failure. Tasks should be
  *performative* — things a player can visibly do or fail to do (persuade
  another group, hold a speech, broker a deal). No dice, no chance: the room
  saw what happened, the GM calls it.
- **Consequence:** the sidequest carries two authored effect bundles —
  **success** and (optional) **failure** — applied to **the assignee's
  group's values**. An empty failure bundle means failing simply costs the
  opportunity.

Sidequests double as the game's **repair valve**: a group pinned at a value's
floor can earn its way back through individual effort — mechanically useful,
dramatically a redemption arc.

## 4. Closing the loop

Decisions change values; these mechanisms make values change the game back.

### 4.1 Gates (conditional options)

Any option — on events and elections alike — may carry an optional
**condition** over the current game state. If the condition is unmet, the
option cannot be chosen.

- Gated options are shown **greyed out with the reason, never hidden**.
  Visible temptation is drama: "we cannot afford it" is a scene.
- Condition language (v1): a single comparison between two arithmetic
  expressions over value references —
  - `self(key)` — the deciding group's current value (event options only),
  - `global(key)` — the derived global value,
  - numbers and `+ - * /` with parentheses.
  - Comparators: `>= <= > < == !=`.
  - Examples: `self(resources) >= 3`, `global(risk) < 8`.
- On election options, only `global(...)` is meaningful (there is no single
  deciding group).
- Boolean combinations (`and` / `or`) are deferred.

Gates give *stock-like* values (things you spend) their meaning and let the
world's state open or close paths.

### 4.2 Thresholds (the GM as the conditional logic)

There is **no automated event triggering**. The GM watches the board and
decides at runtime which event fires next and when — that flexibility *is*
the feature. The live board must therefore make the state legible at a
glance; it replaces automation.

Optionally (later), the system may show **hints** — "global risk crossed 8;
consider the escalation event" — reusing the gate condition language. Hints
notify; they never fire anything.

### 4.3 Endings

A game defines a set of **endings**: authored final scenes (title, narrative,
director's notes). An ending is pure content — it applies no effects and
computes nothing; the game is over.

- Each ending may carry an optional **condition** over the final state
  (same language as gates, `global(...)` only) plus a priority.
- When the GM declares the game over, the system evaluates all conditions
  against the final board and **recommends** the matching endings.
- **The GM picks — and may override.** Conditions are recommendations, like
  everything else.

Endings are the payoff of the whole loop: the room's accumulated choices
select the final scene. Authors should provide a small set (3–5) of
meaningfully different finales, including at least one reachable from
unclamped middle states, so every performance ends *somewhere* earned.

## 5. Director's notes

Almost every content entity — the game, groups, values, events, options,
sidequests, endings — carries a **director's notes** field: localized,
GM-/performer-facing text that is never shown to players.

This is where authors talk to the people running the show: staging
instructions, timing hints, delivery ("hand this sidequest over secretly"),
contingency advice ("if the room is flat, skip the discussion and go straight
to the vote"). It deliberately replaces rigid flags: a flag encodes one bit;
notes carry the bit, the why, and the how.

## 6. Deliberately out of scope (for now)

Recorded so they are decisions, not oversights:

- **Rule-changing election outcomes** (winner sets a flag that later content
  is conditioned on) — a powerful second layer, deferred.
- **Weighted voting** (vote power derived from a value) — rejected for v1:
  it would couple core mechanics to content and break the egalitarian
  principle.
- **Automated event triggering** — rejected: the GM owns pacing.
- **Chance mechanics** (dice, randomness) — rejected: outcomes are performed
  and adjudicated, not rolled.
- **Cross-group effects on event options** (one group's decision directly
  editing another group's values) — not part of v1; elections are the
  intergroup consequence mechanism. Revisit only if playtests show the
  groups feel mechanically isolated.
- **Boolean operators in conditions** — deferred until real content needs
  them.
