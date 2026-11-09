# 0023. One vocabulary: key, name, title, description

- **Status:** Accepted — supersedes [0004](0004-untranslated-handles.md)
- **Date:** 2026-10-28

## Context

[0004](0004-untranslated-handles.md) gave every content entity an untranslated
`handle`, while values kept their existing `key`. Localized fields had grown
different names for the same role (`text` on options, `label` on steps and
bands, `narrative` for bodies), and audience screens fell back to keys where a
name was missing. Around the same time, keys in Common Ground had been
translated into Hungarian by a partner team.

## Decision

Every content entity uses the same field names:

- `key` — the untranslated identifier (was `handle`). Value keys stay slugs
  because formulas reference them; all other keys are free text. Seen by
  authors and the GM, **never by the audience**.
- `name` — what a thing is called (was `text`, `label`).
- `title` — the headline of content with a body (timeline elements, endings).
- `description` — the long Markdown body (was `narrative`).
- Pages have only `key` and `content`; the key is the GM's button label (see
  `72fb2f1`, which dropped `Page.title`).

## Consequences

- One word per role across schema, editor, docs and tutorial.
- The migration only renames columns and indexes; no data to re-enter.
- Audience views (board, projector, QR sheet) no longer fall back to keys.
- `tutorial/setup.exs` still imports exports with the old column names.

## Sources

- `0066d49` refactor: one vocabulary for keys and names.
- `72fb2f1` Drop Page.title — redundant with handle.
- Vault: `Projekte/Megagame/Todo-CommonGround.md` ("Handles waren ins
  Ungarische übersetzt").
