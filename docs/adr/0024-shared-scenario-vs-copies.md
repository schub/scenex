# 0024. A scenario can be shared or copied; the platform supports both

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Several teams can play the same game. Today the Common Ground teams all work
in **one** shared scenario with all languages inside, and one team's change
has already reached every other team at once (keys translated into
Hungarian, Hungarian set as source language), with no history to undo it
([0010](0010-definitions-are-plain-crud.md)). At the same time there was a
request to copy a whole scenario.

How a particular production organises its teams is the project's business,
not the platform's. Scenex is a generic platform for this kind of game; it
only has to make both ways possible.

## Decision

Both are valid, and the platform doesn't prefer one:

- **Share:** a team keeps using an existing scenario and adds its own
  translations.
- **Copy:** a team copies a scenario and adapts the copy to its needs, with
  all the side effects that has.

Copying is a feature that makes the platform more flexible:

- Anyone with at least read access to a scenario may copy it.
- A copy is a copy, not a fork: the two are never synchronised afterwards,
  and the copy doesn't record where it came from.
- By default the whole scenario is copied, with all languages. Choosing which
  languages to copy is a nice-to-have.
- Images (media) are copied too.

## Consequences

- A copy's Markdown must point at the copy's own images, not the
  original's: media rows are deleted with their scenario
  ([0019](0019-permanent-media-urls.md)), so links into the original would
  break once it is deleted.
- Conditions and formulas reference value keys, not ids, so they survive a
  copy unchanged.
- Archived groups exist only for old sessions
  ([0020](0020-session-groups-and-archiving.md)); a copy has no sessions.
- Protecting a shared scenario from one team's mistakes stays a matter of
  roles and of how the teams work together.

## Sources

- Markus, 2026-11-16 ([#13](https://github.com/schub/scenex/issues/13)).
- Vault: `Projekte/Megagame/Todo-CommonGround.md`, section "Für das Meeting:
  Wie arbeiten wir am gemeinsamen Szenario?".
