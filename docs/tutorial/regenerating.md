# Appendix: How this tutorial is made

[← Contents](index.md)

Every screenshot, the content reference and the balance report are generated
from a running Scenex instance. Change the scenario or the interface, run one
command, and the tutorial's pictures and tables are current again.

## One command

From the `scenex` directory:

```bash
tutorial/run.sh            # screenshots, content reference, balance report
tutorial/run.sh --video    # the same, plus the narrated screencast
```

What it does:

1. Drops and recreates a **separate database**, `scenex_tutorial`. Your normal
   development database is never touched.
2. Creates the account `director@mars-colony.example` and seeds Mars Colony
   for it (`tutorial/setup.exs` → `priv/repo/seeds_mars_colony.exs`).
3. Starts Scenex on port 4100.
4. `tutorial/capture.mjs` drives a real browser (Playwright) through the
   editor and a whole live session — console, two group boards and the
   projected display — and saves every image into `docs/tutorial/images/`.
5. `tutorial/reference.exs` writes [the complete content](mars-colony-content.md)
   from the database.
6. `priv/repo/balance_mars_colony.exs` writes [the balance report](mars-colony-balance.md).
7. With `--video`: records and assembles the screencast (see below).

The first run installs Playwright and its browser into `tutorial/node_modules`
(about 150 MB).

## What updates by itself — and what doesn't

| Changed … | Updates automatically | Needs a manual edit |
|---|---|---|
| numbers, texts, options in the seed | screenshots, content reference, balance report | tutorial text that quotes a number |
| the interface (layout, labels) | screenshots | text describing the old layout; `capture.mjs` if a button it clicks was renamed |
| a new feature | — | a new section and a new step in `capture.mjs` |

Image names are stable: `capture.mjs` saves `shot("console-vote")` as
`images/console-vote.png`, which the pages reference.

## Changing Mars Colony

The scenario's source is `priv/repo/seeds_mars_colony.exs`. Edit it, then:

```bash
mix run priv/repo/seeds_mars_colony.exs          # into your dev database
mix run priv/repo/balance_mars_colony.exs        # check the balance
tutorial/run.sh                                  # refresh the tutorial
```

The seed refuses to replace a Mars Colony that already has sessions in your
dev database, so it never deletes a session log. The illustration is
`priv/repo/mars_colony/jezero-crater.svg` (and the rendered `.png` next to
it).

## The video

`tutorial/run.sh --video` records the screencast:

- `tutorial/video/script.mjs` — the storyboard: every scene with its narration
  text and the browser actions shown while it is spoken.
- `tutorial/video/record.mjs` — speaks every narration line with the macOS
  voice (`say`), then plays the storyboard in a recorded browser with a
  visible mouse pointer, waiting exactly as long as each line takes.
- `tutorial/video/assemble.mjs` — combines recording, voice and subtitles with
  `ffmpeg` into `tutorial/video/build/scenex-tutorial.mp4` and `.srt`.

Choose another voice with `TUTORIAL_VOICE="Zoe (Premium)" tutorial/run.sh --video`
(install voices in *System Settings → Accessibility → Spoken Content*).

## Publishing on GitHub Pages

`docs/` is ready to be served by GitHub Pages: in the repository settings,
choose *Pages → Deploy from a branch → `main` / `docs`*. The tutorial is then
at `https://<user>.github.io/<repo>/tutorial/`.
