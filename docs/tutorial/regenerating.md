# Appendix: How this tutorial is made

[← Contents](index.md)

Every screenshot, both content references and the balance report are
generated from a running Scenex instance. Change a scenario or the
interface, run one command, and the tutorial's pictures and tables are
current again. (The text is written by hand — see the table below.)

## One command

From the `scenex` directory:

```bash
tutorial/run.sh               # screenshots, content references, balance report
tutorial/run.sh --video       # the same, plus the narrated screencast
tutorial/run.sh --video-only  # only the screencast
tutorial/run.sh --serve       # only build the tutorial database and serve it
```

What it does:

1. Drops and recreates a **separate database**, `scenex_tutorial`. Your normal
   development database is never touched.
2. Creates the account `director@scenex.example` (password
   `common-ground-2026`) and loads two scenarios for it
   (`tutorial/setup.exs`):
   - **Common Ground**, from an export of scenex.org (see below), and
   - **Mars Colony**, from `priv/repo/seeds_mars_colony.exs`.
3. Starts Scenex on port 4100 (with `--serve`, it stops here: open
   <http://localhost:4100> and click along).
4. `tutorial/capture.mjs` drives a real browser (Playwright) through the
   editor and a whole live session — console, group boards and projector —
   and saves every image into `docs/tutorial/images/`.
5. `tutorial/reference.exs` writes the complete content pages of
   [Common Ground](common-ground-content.md) and
   [Mars Colony](mars-colony-content.md).
6. `priv/repo/balance_mars_colony.exs` writes the
   [Mars Colony balance report](mars-colony-balance.md).
7. With `--video`: records and assembles the screencast.

The first run installs Playwright and its browser into `tutorial/node_modules`
(about 150 MB).

## Refreshing Common Ground from scenex.org

The tutorial uses a copy of Common Ground, kept **outside** this repository
in `studio/data/common-ground/`. To refresh it:

1. On the server, dump the production database
   (`docker exec oracle-postgres pg_dump -U oracle -Fc scenex_prod`) and pack
   `/opt/containers/scenex/media`.
2. Restore the dump into a local Postgres 17 (e.g. an OrbStack/Docker
   container) and unpack the media.
3. Run

   ```bash
   tutorial/common_ground/export.sh postgres://oracle:oracle@localhost:5433/scenex_prod <media-folder>
   ```

The export takes **only the scenario's content**: no accounts, no member
emails, no sessions. On the way, it keeps English only, sets English as the
source language and makes media links relative (`/media/…`).

## What updates by itself — and what doesn't

| Changed … | Updates automatically | Needs a manual edit |
|---|---|---|
| texts, options, numbers of a scenario | screenshots, content references, balance report | tutorial text that quotes them |
| the interface (layout, labels) | screenshots | text describing the old layout; `capture.mjs` if a button it clicks was renamed |
| a new feature | — | a new section and a new step in `capture.mjs` |

Image names are stable: `capture.mjs` saves `shot("console-vote")` as
`images/console-vote.png`, which the pages reference.

## The video

- `tutorial/video/script.mjs` — the storyboard: every scene with what's on
  screen, its narration, and the clicks shown while it is spoken.
  `node video/storyboard.mjs` turns it into `video/storyboard.md`, a table
  to review the text before recording.
- `tutorial/video/record.mjs` — speaks every line (`voice.mjs`), then plays
  the storyboard in a recorded browser with a visible pointer, holding each
  scene as long as its line plus a short pause. It also renders one caption
  image per scene.
- `tutorial/video/assemble.mjs` — combines picture, voice and captions with
  `ffmpeg` into `tutorial/video/build/scenex-tutorial.mp4` (1280×800: the
  720p picture plus a caption bar underneath) and a `.srt` subtitle file.
  Browser recordings run a few percent slow under load; the assembler
  measures that and corrects it, so voice and picture stay in sync.

### Voices

By default the narration uses a macOS voice — free, but robotic. Another one:
`TUTORIAL_VOICE="Zoe (Premium)" tutorial/run.sh --video`.

For a natural voice, use ElevenLabs:

```bash
node tutorial/video/voices.mjs                 # list your voices (free)
TUTORIAL_TTS=elevenlabs TUTORIAL_ELEVENLABS_VOICE=XrExE9yKIg1WjnnlVkGX tutorial/run.sh --video-only
```

The published video uses **Matilda** (`XrExE9yKIg1WjnnlVkGX`, one of
ElevenLabs' built-in voices). On the free plan only built-in voices work
through the API; voices from the Voice Library need a paid plan.
`node tutorial/video/voice-test.mjs <scene-id>` speaks a single line to
listen to first (it's cached, so the full run reuses it).

Names that need help are respelled for the voice only — "Scenex" is spoken
as "Scene-ex" (see `PRONUNCIATION` in `voice.mjs`); captions keep the
written form.

The API key is read from `~/.config/scenex.org/scenex-tutorial.env`
(`ELEVENLABS_API_KEY=…`), never from the repository. ElevenLabs charges per
character — the whole narration is about 5,700 — so every line is cached in
`tutorial/video/cache/`: a re-recording only pays for lines whose text
changed.

## Publishing on GitHub Pages

`docs/` is ready for GitHub Pages: in the repository settings choose
*Pages → Deploy from a branch → `main` / `docs`*. The tutorial is then at
`https://<user>.github.io/<repo>/tutorial/`.
