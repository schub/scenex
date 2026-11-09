# 0004. Every content entity has an untranslated handle

- **Status:** Superseded by [0023](0023-key-name-title-vocabulary.md)
- **Date:** 2026-07-02

## Context

Editor lists showed localized names, so what an author saw depended on the
working locale and on which translations existed.

## Decision

Add a required, non-translated `handle` to every content entity, unique within
its scope, as an internal organizational label. Values keep their existing
`key`, which already played that role because formulas reference it.

## Consequences

- Every list shows a stable string regardless of locale.
- Two names for the same concept (`handle` vs. `key`) — resolved by
  [0023](0023-key-name-title-vocabulary.md).

## Sources

- `d47b85c` Add a required, non-translated `handle` to content entities.
- `fd2558d` Enforce unique handles within scope.
