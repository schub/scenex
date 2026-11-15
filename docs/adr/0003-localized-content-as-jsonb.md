# 0003. Authored content is localized as `jsonb` maps; chrome uses Gettext

- **Status:** Accepted
- **Date:** 2026-07-02

## Decision

Two separate mechanisms:

- **UI chrome** (buttons, labels, errors) goes through Gettext.
- **Authored content** (names, titles, descriptions, director's notes) is a
  `jsonb` map `locale => string` on the row itself, rendered per viewer by
  `Scenex.I18n` with fallback to the scenario's `source_locale`, then to any
  translation that exists.

The event log stores ids, never text, so it stays language-neutral.

## Consequences (documented)

- Treated as "a data-model decision, not a feature": i18n-ready schema is on
  the "Never cut" list.
- A partly translated game never shows blanks.
- Every localized field is a map; queries and forms must handle that.

## Rationale

- **From day one:** the project is international, so i18n was a requirement
  from the start, not a later feature.
- **On the row:** translations are content — a translation belongs to the
  thing it translates, so it lives in the same row rather than in separate
  translation tables (Markus, 2026-11-15).

## Sources

- `fea558e` — "I18n: localized-content helper … UI stays on Gettext."
- Former implementation plan §2 "i18n (a data-model decision, not a feature)",
  §9.
- [`architecture.md`](../architecture.md) §8.
