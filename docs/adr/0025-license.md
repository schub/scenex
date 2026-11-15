# 0025. Code under Apache-2.0, content and docs under CC BY 4.0

- **Status:** Accepted
- **Date:** 2026-11-15

## Context

The repository had no LICENSE. Scenex is meant to be used by partner theatres
in several countries. It can all be open source, and everybody may use the
code as they want (Markus, 2026-11-15). Most of the code is written by AI.

## Decision

- **Code:** Apache License 2.0 (`LICENSE`).
- **Documentation and bundled scenario content** (`docs/` including the
  tutorial, Mars Colony, the demo scenario): Creative Commons Attribution 4.0
  (CC BY 4.0).
- Copyright 2026 Markus Schubert, stated in `NOTICE`.

## Alternatives considered

- **AGPL-3.0**, so modified hosted versions must share their changes. Lost:
  the goal is that anyone may use the code as they want, not to bind them. A
  copyleft also leans on copyright to enforce it, and copyright in largely
  AI-written code is uncertain (protection generally requires human
  authorship).
- **MIT.** Equally permissive, but without Apache-2.0's explicit patent grant
  from contributors — which matters a little more once other people
  contribute.
- **CC BY-SA 4.0** for content. Lost: share-alike would force derived
  scenarios onto the same license; attribution only is closer to "use it as
  you want".

## Consequences

- Anyone may use, change and redistribute Scenex, also commercially and in
  closed products, keeping the license and `NOTICE`.
- The licenses cover what ships in this repository.

## Sources

- Markus, 2026-11-15 ([#14](https://github.com/schub/scenex/issues/14)).
- Vault: `Projekte/Megagame/Common Ground.md`, section "Open / to confirm".
