# AI context: writing scenario content for the Portugal Scenex session

This document is **context for an AI assistant**, not reading material for the
human author. Give it to the assistant before it starts helping a dramaturg or
director write Events, Votes, or Wildcards for this scenario. Its job is to
make sure the assistant's suggestions are things the platform can actually do
— not a plausible-sounding but incorrect guess at "how these games usually
work."

If you are the assistant reading this: the mechanical rules below are exact
and binding — the platform will reject or misinterpret content that doesn't
follow them. The *story* — who these institutions are, what tensions define
this particular Portuguese scenario, how sympathetically or critically to
portray any group — is entirely the human author's call, not something to
infer or default from this document. Ask, don't assume, whenever the
dramaturgy is unclear; never guess at the mechanics.

## 1. What this platform is

Scenex runs live, facilitator-led "megagame" sessions: a room full of
participants is split into fixed groups, each seated together with their own
screen. A game master (GM) runs the session in real time, manually triggering
authored story beats ("timeline elements") in whatever order and pace fits
the room. Each beat presents narrative and, depending on its kind, lets one
or more groups make a decision. Every decision nudges a small set of tracked
numeric values, per group and in aggregate — the session's "score" is the
visible, moving consequence of what the room chose.

There are three screens: a shared projected **scoreboard** (global values
only, for the whole room to see), each group's own **group board** (that
group's own values plus its own current decisions), and the GM's own
**console** (full visibility, all controls). Authored content is only ever
seen on the scoreboard and group boards — never write content assuming the
GM console's exact numbers are visible to players; they generally aren't.

## 2. This project's cast: five fixed groups

This scenario always has exactly these five groups, seated in the room for
the whole session:

- **Arts and Culture** — cultural institutions, artists, heritage and the
  creative sector.
- **Public Service** — civil servants and public administration; the people
  who run the machinery of government day to day.
- **Citizen Assembly** — a body of ordinary residents, standing in for the
  public at large.
- **Chamber of Commerce** — organized business and employer interests.
- **Consumer Association** — advocacy for everyday consumers and households.

That's the full roster — don't invent additional groups, and don't assume any
one of these five is more "important" than the others; a well-built event
usually gives two or more of them genuinely different stakes in the same
moment. Their specific politics, alliances, and grievances in this particular
story are the author's to define — this document only fixes their existence
and their institutional role, nothing else.

## 3. This project's tracked values

Four values are tracked for this project, each as a **separate number per
group** (so "Stability" is really five numbers, one per group) plus one
**derived global number** per value, computed from those five by a formula
the author sets once (see §7):

- **Stability**
- **Solidarity**
- **Resources**
- **Fairness** (renamed from "Inclusion" partway through development — same
  value, same mechanics, just the new name everywhere it's shown)

All four share the same numeric scale in this project (confirm the exact
min/max with the author if it matters for a specific number you're
proposing — don't assume a scale). Only options can move these numbers;
nothing else changes them mid-session.

There is also **Well-being**, mechanically different from the four above: a
single **per-participant** value, not tracked per group. It is *never* moved
by an option's effect — the GM collects it directly from the room as a
hand-count (a show of hands read into the console) at whatever moments they
choose, independent of the story beats. Do not write option effects that
target well-being; there is no such thing.

## 4. The Democracy Score

This project also derives one further number, the **Democracy Score**: a
single formula (same formula language as §7) combining the four *global*
values above — Stability, Solidarity, Resources, Fairness; well-being is
explicitly excluded, since it isn't part of the same per-group system. It's
configured once for the whole scenario (not per-event) and shown to the room
on the scoreboard as one of five labeled bands, best to worst: **In Bloom,
Resilient, Fragile, Critical, Breakdown** — never as a raw number. You don't
need to write anything for this directly; it updates automatically from the
same effects that move the four values.

## 5. The three kinds of beat

The product UI for this project uses renamed labels for two of the three —
**"Vote"** (was "election") and **"Wildcard"** (was "sidequest"). Use those
names when talking to the author; they map directly to the mechanics below.

### Event

The default, most common kind. Presents narrative plus a **separate set of
options for each involved group** — a group only ever sees its own options,
never another group's. You don't have to give every group options on every
event; only add options for the groups actually implicated in that beat.

- Each option can apply a **value delta** — by default to the *deciding
  group's own* values, but an option can optionally target a *different*
  group explicitly too, so one group's choice can ripple onto another's
  numbers. Use that deliberately, for specific dramatic moments — not as the
  default shape of every option.
- Each option can carry a **gate**: a condition that must be true for the
  option to be selectable. A locked option is always shown, greyed out, with
  its condition visible — never hidden. Gates on event options may reference
  either the deciding group's own current value (`self(key)`) or a global
  value (`global(key)`).
- An event can optionally have a **deadline** (a countdown, in seconds). If
  set, at most **one option per group** may be flagged as that group's
  *default*. If the deadline lapses and a group never decided, its
  default-flagged option (if any) is applied automatically. **If a group has
  no default-flagged option, nothing happens for that group when the
  deadline lapses — it simply stays undecided, permanently.** Whether a
  default exists at all is the author's choice per group, per event; it is
  not required.
- The GM can also close an event manually at any time, deadline or not. This
  never applies a default — it only stops taking new answers. The only way a
  default option is ever auto-applied is a deadline actually lapsing.

### Vote (election)

One shared ballot for the **whole room**, not per group — there is only one
set of options, and everyone in the room votes on the same question (the
actual voting — a show of hands, etc — happens live in the room; the GM
enters the final tally and declares the result).

- Options are **not tied to a group** and can carry a full **outcome
  matrix**: different effects on different groups' values from the same
  winning option (e.g. a "Yes" result could raise one group's Resources
  while lowering another's).
- Gates are allowed but **global-only** (`global(key)`) — a room-wide vote
  can't be gated on any single group's own number.
- Same deadline/default idea as events, but there's only **one** default for
  the whole vote (the option declared the winner automatically if nobody
  reports a result before the deadline), not one per group.

### Wildcard (sidequest)

A beat with exactly two possible outcomes — **Success** or **Failure** —
that nobody in the room chooses. The GM alone decides which outcome
happened, on their own judgment, whenever they choose to resolve it (a
random event, a hidden complication, a die roll, pure narrative call — the
story decides how).

- No gates (nothing is being selected by a player, so there's nothing to
  lock).
- No deadline and no default — the GM resolves it whenever they like, with
  no automatic fallback either way.
- Like a Vote, each outcome (Success/Failure) can carry a full per-group
  outcome matrix of effects.

## 6. Writing option effects

- An effect is a **delta** (added to, not set as, the target's current
  number) on one of the four values, for one group. An option can carry
  several effects at once, across different values and/or different groups.
- Deltas are clamped to that value's authored min/max — you can't push a
  group below its floor or above its ceiling, so an oversized delta simply
  saturates rather than error.
- Scale delta size to the moment: a minor procedural choice might move a
  value by 1; a genuinely dramatic turn might move it 3–5. Check the actual
  configured min/max with the author before assuming what "small" and "big"
  mean numerically for this project.

## 7. Global values and the aggregation formula

Each value's global number is computed from the five groups' current numbers
by a formula, written once per value (not per event) using this language:

- Aggregations over the five groups' values: `min`, `max`, `avg` (or
  `average`), `median`, `sum`.
- Combine with `+ - * /` and parentheses; unary minus is allowed.
- Examples: `"avg"` (a plain average), `"(avg + min) / 2"` (rewards keeping
  every group reasonably content, not just the average, since the worst-off
  group pulls the score down).

The Democracy Score (§4) uses the exact same formula language, just
evaluated over the four *global* values instead of one value's five
per-group numbers.

## 8. Gate/condition syntax, exactly

- `self(key)` — the deciding group's own current value. **Event options
  only.**
- `global(key)` — the derived global value. Allowed on both Event and Vote
  options.
- `key` is the value's short slug, lowercase — `stability`, `solidarity`,
  `resources`, `fairness` — never its display name.
- Exactly **one** comparator per condition: `>= <= > < == !=`. Arithmetic
  (`+ - * /`, parentheses, unary minus) is allowed on either side.
- Boolean combinations (`and`/`or`) are **not supported** — a condition is a
  single comparison. If a beat genuinely needs "both X and Y," that's a sign
  it should be two separate gated options, or a note to the GM, not one
  condition.
- Examples: `self(resources) >= 3`, `global(stability) < 4`,
  `(self(stability) + self(solidarity)) / 2 > 5`.

## 9. Endings

A scenario needs at least one ending to close on. Endings are pure narrative
— they apply no effects of their own. Each may optionally carry a
**recommendation condition**, evaluated only against **global** values
(`global(key)`, no `self()` — an ending isn't any one group's decision), used
to suggest which ending fits the final state. The GM always makes the final
call and may pick a different ending than the recommendation; the condition
is guidance, not a hard gate.

## 10. Other authoring tools available

- **Labels**: small colored tags an author can attach to options (e.g.
  "Aggressive," "Diplomatic") for quick visual read at the table. Purely
  cosmetic — they carry no numbers and never affect the simulation.
- **Director's notes**: a hidden, GM-only text field available on values,
  groups, elements, options, and endings — separate from the public
  narrative. Use it for staging guidance, improvisation prompts, or
  background the GM needs but players never see.
- All narrative and option text is **Markdown**, and can embed images/video.
  Write it in the session's actual play language.

## 11. Practical guidance

- Not every group needs a stake in every event — a beat that only involves
  two or three groups is completely normal; don't pad options onto
  uninvolved groups.
- Across the whole scenario, make sure every one of the five groups gets
  meaningful beats of its own — check the full roster isn't quietly
  neglected over the run.
- Prefer differentiating the *institutional* interest behind each group's
  options over generic "good choice / bad choice" framing — the same event
  should read as a genuinely different dilemma from each seated group's
  side of the room.
- Cross-group effects (an option that also moves another group's numbers)
  are a real tool, not an edge case — but use them for specific, legible
  "your choice affects them too" moments, not as a default habit, or the
  causality gets hard to read at the table.
- The boards show value *changes* visually (an accent highlight for a rise,
  a hollow outline for a fall against where it stood a moment ago), so
  genuine swings in both directions read better live than a long run of
  same-direction nudges.
- Keep option text concise — it renders as a button label, not a paragraph;
  put the color and nuance in the narrative above it.

## Quick glossary

| In this project's UI | Underlying mechanic (code, this doc's cross-references) |
|---|---|
| Vote | election |
| Wildcard | sidequest |
| Event | event (unchanged) |

Everything else in this document already uses the current, correct UI
wording.
