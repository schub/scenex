// Assembles the screencast from record.mjs's output: the picture from the
// screencast frames, each held until the next one (by their real paint
// times), every narration clip at its scene's start, the caption bar below
// the picture and soft subtitles. Writes video/build/scenex-tutorial.mp4
// (plus .srt).
//
//     node video/assemble.mjs

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";

const BUILD = new URL("build/", import.meta.url).pathname;
const { scenes, frames } = JSON.parse(await readFile(BUILD + "timeline.json", "utf8"));
const VOICE_DELAY = 0.3; // seconds between a scene's start and its narration

const duration = (file) =>
  parseFloat(
    execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file])
      .toString()
      .trim()
  );

// ── Subtitles ───────────────────────────────────────────────────────────────
const stamp = (s) => {
  const ms = Math.round(s * 1000);
  const pad = (n, w = 2) => String(n).padStart(w, "0");
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms / 60000) % 60)}:${pad(Math.floor(ms / 1000) % 60)},${pad(ms % 1000, 3)}`;
};

const srt = scenes
  .map((s, i) => {
    const from = s.start + VOICE_DELAY;
    const to = from + duration(s.audio);
    return `${i + 1}\n${stamp(from)} --> ${stamp(to)}\n${s.text}\n`;
  })
  .join("\n");
await writeFile(BUILD + "scenex-tutorial.srt", srt);

// ── The picture ─────────────────────────────────────────────────────────────
// Frame times are relative to the first scene (0 s). Start with the last
// frame painted before it, hold every frame until the next one, end with the
// last scene.
const total = scenes.at(-1).end;
const first = Math.max(0, frames.findLastIndex((f) => f.at <= 0));
const used = frames.slice(first).filter((f) => f.at < total);
const list = used
  .map((f, i) => {
    const from = Math.max(f.at, 0);
    const to = i + 1 < used.length ? used[i + 1].at : total;
    return `file '${f.file}'\nduration ${Math.max(to - from, 0.001).toFixed(4)}`;
  })
  .join("\n");
// The concat demuxer needs the last file repeated for its duration to count.
await writeFile(BUILD + "frames.txt", `${list}\nfile '${used.at(-1).file}'\n`);
console.log(`  picture: ${used.length} frames`);

// Inputs: 0 = picture, 1..n = narration clips, n+1..2n = caption bars.
const n = scenes.length;
const inputs = ["-f", "concat", "-safe", "0", "-i", BUILD + "frames.txt"];
scenes.forEach((s) => inputs.push("-i", s.audio));
scenes.forEach((s) => inputs.push("-i", s.caption));

const chains = [
  `[0:v]fps=30,scale=1280:720:force_original_aspect_ratio=decrease,` +
    `pad=1280:800:0:0:color=0x141418[v0]`
];
scenes.forEach((s, i) => {
  const ms = Math.round((s.start + VOICE_DELAY) * 1000);
  chains.push(`[${i + 1}:a]aresample=48000,adelay=${ms}|${ms}[a${i}]`);
  chains.push(
    `[v${i}][${n + 1 + i}:v]overlay=0:720:enable='between(t,${s.start.toFixed(2)},${s.end.toFixed(2)})'[v${i + 1}]`
  );
});
const mix =
  chains.join(";") +
  ";" +
  scenes.map((_, i) => `[a${i}]`).join("") +
  `amix=inputs=${n}:normalize=0:dropout_transition=0[voice]`;

const subIndex = 2 * n + 1;
execFileSync(
  "ffmpeg",
  [
    "-y", "-hide_banner", "-loglevel", "error",
    ...inputs,
    "-i", BUILD + "scenex-tutorial.srt",
    "-filter_complex", mix,
    "-map", `[v${n}]`, "-map", "[voice]", "-map", `${subIndex}:s`,
    "-t", total.toFixed(3),
    "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "160k",
    "-c:s", "mov_text", "-metadata:s:s:0", "language=eng",
    "-movflags", "+faststart",
    BUILD + "scenex-tutorial.mp4"
  ],
  { stdio: "inherit" }
);

const minutes = Math.floor(total / 60);
const seconds = Math.round(total % 60);
console.log(`Wrote ${BUILD}scenex-tutorial.mp4 (${minutes}:${String(seconds).padStart(2, "0")}) and .srt`);
