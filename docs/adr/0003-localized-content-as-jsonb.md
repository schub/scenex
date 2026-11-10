# 0003. Authored content is localized as `jsonb` maps; chrome uses Gettext

- **Status:** Accepted, rationale open
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

## Open

- Why `jsonb` on the row rather than translation tables or a separate
  translations store? (Simplicity? Copying/exporting a scenario as one unit?)
- Why must i18n be in the data model from day one — the multi-country
  partner setup (Portugal, Hungary, …)?

## Sources

- `fea558e` — "I18n: localized-content helper … UI stays on Gettext."
- Former implementation plan §2 "i18n (a data-model decision, not a feature)",
  §9.
- [`architecture.md`](../architecture.md) §8.
