# 0024. One shared scenario per game, or copies?

- **Status:** Proposed
- **Date:** —

## Context

Common Ground is played by several theatres. Today they all work in **one**
shared scenario on scenex.org with all languages inside; the tutorial says so
explicitly ("You don't copy it, you don't rebuild it: you translate it",
`docs/tutorial/08-your-common-ground.md`). Local extras are beats with a
country/city prefix in the key.

This has already caused problems: one team's change reaches every other team
at once (keys translated into Hungarian, Hungarian set as source language), and
definitions have no history to undo it ([0010](0010-definitions-are-plain-crud.md)).

At the same time there's a request to copy a whole scenario.

## Options

1. **Shared only.** Keep one scenario; manage it with roles and a process
   (who may change the shared core, how changes are proposed).
2. **Copies only.** Each theatre works in its own copy; changes to the original
   don't reach them.
3. **Both, for different purposes.** Shared for performing one game; copies for
   starting a new game from an existing one (a fork).
4. **Shared with synchronized copies.** Copies that can pull changes from the
   original. Much more expensive; needs definition history first.

## Facts that constrain a copy

- Media rows are deleted with their scenario; a copy pointing at the
  original's `/media/…` URLs breaks when the original is deleted
  ([0019](0019-permanent-media-urls.md)). Absolute `https://scenex.org/media/…`
  links break in copies on other hosts.
- Archived groups exist only for old sessions
  ([0020](0020-session-groups-and-archiving.md)).
- Conditions and formulas reference value keys, not ids, so they survive a
  copy unchanged.

## Open

- Which option? This decides what the tutorial teaches.
- If copies: who may copy (owner, authors, viewers of a published scenario)?
  Copy media? All languages? Record `copied_from_id`?
- If shared: who may change the shared core, and how are changes agreed?

## Sources

- `docs/tutorial/08-your-common-ground.md`.
- Vault: `Projekte/Megagame/Todo-CommonGround.md`, section "Für das Meeting:
  Wie arbeiten wir am gemeinsamen Szenario?".
