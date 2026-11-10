# 0019. `/media/<id>/<filename>` is a permanent URL contract

- **Status:** Accepted
- **Date:** 2026-07-12

## Context

Authors embed images, short video and audio in Markdown content by pasting a
URL. Those URLs end up in stored text across many fields and translations.
Storage is local disk today, S3-compatible maybe later.

## Decision

- Media is per scenario (`Scenex.Media`, rows in `media_files`).
- The public URL is `/media/<id>/<filename>` and must survive any change of
  storage backend. Bytes sit behind the `Scenex.Media.Storage` behaviour.
- Only image/video/audio types are accepted. **SVG is excluded**: inline SVG
  served from our origin would be an XSS door.
- Filenames are sanitized; the serving controller supports HTTP range requests
  (iOS Safari won't play media without them) and caches hard
  (`immutable`).

## Consequences

- Storage can be swapped without touching authored content.
- A file's URL can never be reused for different bytes (hard caching).
- Media rows are deleted with their scenario (`on_delete: :delete_all`), so
  any URL pointing at another scenario's media breaks when that scenario is
  deleted. Relevant for copying scenarios — see
  [0024](0024-shared-scenario-vs-copies.md).
- Absolute URLs (`https://scenex.org/media/…`) work but tie content to one
  host; relative `/media/…` is the intended form.

## Sources

- `d28b6df` Per-scenario media library with stable public links.
- `lib/scenex_web/controllers/media_controller.ex`,
  `priv/repo/migrations/20260712211615_create_media_files.exs`.
- Vault: `Projekte/Megagame/Todo-CommonGround.md` (absolute image links in
  Common Ground "bricht nur in Kopien").
