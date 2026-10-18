# 1. How Scenex thinks

[← Contents](index.md) · [Next: Getting started →](02-getting-started.md)

Five ideas explain almost everything you will see in Scenex.

## Scenario and session

A **scenario** is the authored game: its groups, what it measures, its story
beats, choices and endings. You write it once in the **editor**.

A **session** is one live performance of a scenario — one venue, one
evening. You create a session from a scenario, run it from the **GM console**,
and afterwards it stays as a record of what that room decided.

One scenario can have many sessions, even at the same time in different
cities, and they never touch each other. When a session starts, Scenex takes a
snapshot of the scenario, so editing the scenario during a show cannot change
a game that is already running.

## The three screens

| Screen | Who looks at it | What it shows |
|---|---|---|
| **GM console** | the game master, on a laptop | everything: all numbers, all options, the director's notes, every control |
| **Group board** | each group, on one tablet or phone per table | the group's own values and its own choices |
| **Projected display** | the whole room, on a projector or big screen | the colony-wide numbers, the current beat, results, pages and the ending |

Players never log in. Each table scans a **QR code** that opens its group
board; the projector gets its own code.

## Values: per group and global

A scenario measures a small number of **values**. In Mars Colony they are
*Life Support*, *Supplies*, *Progress* and *Risk*.

Each group holds **its own number** for every value. The **global** number for
the whole room is calculated from the groups' numbers by a formula you choose
— for example the average, or the minimum. Nobody enters a global number;
it always follows from the groups.

A second kind of value is counted **per participant**: the game master asks
the room for a show of hands ("how are you feeling?") and types in the count.
Mars Colony uses this for *Morale*.

The **Overall Index** rolls the global values up into one headline score — in
Mars Colony it is called *Colony Vitality*.

## The timeline: three kinds of beat

The story is a list of **timeline elements** — the beats the game master
fires, in whatever order and at whatever pace suits the room.

| Kind | Who decides | Whose values change |
|---|---|---|
| **Event** | every group separately, each from its own options | the deciding group's own values |
| **Vote** | the whole room, one person one vote; the GM counts hands | any group's values (an *outcome matrix*) |
| **Wildcard** | nobody chooses — the GM judges *success* or *failure* | any group's values (an *outcome matrix*) |

Each choice an option makes is a set of **effects**: small plus or minus
changes to values.

## The game master decides

Scenex never fires anything on its own. The game master triggers every beat,
can correct any decision, breaks ties and chooses the ending. Where Scenex
makes suggestions — a recommended ending, a locked option, a default when time
runs out — they are exactly that: suggestions. There are no dice and no hidden
randomness.

Every action in a session is recorded in order. That means a mistake is fixed
by simply entering the right decision again (the latest one counts), and a
session survives a server restart without losing anything.

## A note on handles

Every piece of content has a **handle**: a short internal name such as
`what_to_bring` or `engineering`. Handles are for you and the game master —
players never see them, and they are never translated. What players see
(names, titles, story text) lives in separate fields that you can translate
into several languages.

---

[← Contents](index.md) · [Next: Getting started →](02-getting-started.md)
