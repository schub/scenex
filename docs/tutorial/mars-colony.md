# Appendix: The Mars Colony scenario

[← Common Ground at a glance](common-ground.md) · [Contents](index.md) · [Complete content →](mars-colony-content.md)

Mars Colony is this tutorial's **second example**: a short, complete megagame
in a completely different world, which shows that Scenex isn't tied to one
kind of story. Where Common Ground doesn't use a building block — conditions,
labels, real endings, mixed formulas — the tutorial shows it in Mars Colony.

![Jezero Crater at dawn](images/jezero-crater.png)

|  |  |
|---|---|
| **Players** | about 25, aged 14–18 (five teams of five) |
| **Duration** | 45–60 minutes |
| **Language** | English (a German translation is planned) |
| **Load it** | `mix run priv/repo/seeds_mars_colony.exs` |

## The story

Twenty-five people are the crew of humanity's first permanent colony on Mars.
The story starts on Earth, the night before launch, and follows the colony
from touchdown through its first real crisis: a dust storm cripples the power
system the colony itself built.

It is meant to be **fun and constructive first** — building something
together — before it gets hard. The game is not *about* voting or politics;
negotiation and compromise come from the mechanics: the colony's Life
Support is its weakest team's, its Risk is its most reckless team's.

## The arc

| Part | Beats | What it does |
|---|---|---|
| **Prologue** (Earth) | What to Bring | low stakes; teaches the boards; every team fixes or ignores its weakness |
| **Act 1** (building) | Touchdown, Settling In; Wildcards *Green Thumb*, *The Find* | constructive choices whose consequences Act 2 calls back |
| **Act 2** (crisis) | The Storm, Rationing (one of two shades), Earth's Offer; Wildcards *Jury-Rig It*, *Triage*, *Off the Record* | every option costs something; the colony decides together |
| **Ending** | The Colony Holds · Getting By · On the Brink | sobering, never bleak |

Morale is counted twice by show of hands: at the end of Act 1 and at the
peak of the crisis.

## The five teams

| Team | Role | Starts strong in | Starts weak in |
|---|---|---|---|
| Engineering & Habitat | power, air, airlocks | Life Support | Progress |
| Science & Exploration | discoveries | Progress | Supplies |
| Agriculture & Life Systems | food and water | Life Support | Risk (high) |
| Medical & Crew Welfare | body and mind | Risk (low) | Supplies |
| Command & Earth Relations | leadership, the line to Earth | Supplies | Life Support |

Command starts as the colony's weakest link in Life Support — and Life
Support uses `min`. The first thing an attentive room discovers is that
Command's problem is everyone's problem.

## Design decisions

- **Functional teams, not factions.** Nobody is the villain; everyone wants
  the colony to survive, and everyone disagrees about how.
- **Asymmetric starting positions, identical rules.** Every team starts at 5
  everywhere, ±2 for one strength and one weakness.
- **Formulas carry the theme.** `min` for Life Support, `max` for Risk,
  `median` for Progress, `(avg + min) / 2` for Supplies.
- **Echoes are narrative, not mechanical.** What Engineering built in Act 1
  matters in Act 2 because the GM says so (the director's notes list every
  echo), not because of hidden conditions.
- **One shaded beat.** *Rationing* has a mild and a harsh version; the GM
  picks by Colony Vitality.
- **Earth is optional.** The Vote only happens if Command calls Earth during
  the storm.

## Balance

The numbers were checked with `priv/repo/balance_mars_colony.exs`, which
plays the scenario thousands of times through the same code a live session
uses, with different kinds of rooms:

| Room | Usual ending |
|---|---|
| **Careful** teams, lucky Wildcards | always *The Colony Holds* |
| **Careful** teams, unlucky Wildcards | *Getting By* |
| **Mixed** teams (think 70 % of the time) | mostly *Getting By* (≈ 90 %), sometimes *The Colony Holds* (≈ 8 %), rarely *On the Brink* (≈ 1 %) |
| **Random** choices | half *Getting By*, half *On the Brink* |
| **Reckless** teams | always *On the Brink* |

All three endings are reachable, the middle one is the common one, and the
best one has to be earned. The full, current numbers are in the
[balance report](mars-colony-balance.md), regenerated with the tutorial.

## Open points

These are deliberate placeholders, to be refined after the first playtest:

- the German translation;
- a second, internal Vote (how the colony splits its power among the teams),
  parked for now;
- sound and more images for the Pages.

---

[← Common Ground at a glance](common-ground.md) · [Contents](index.md) · [Complete content →](mars-colony-content.md)
