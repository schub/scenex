// Measures audio/video sync of the last video: finds the hard cuts in the
// picture (title cards, full-screen images) and compares each with the start
// of its scene in timeline.json — where the narration is placed.
//
//     node video/sync-check.mjs

import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";

const BUILD = new URL("build/", import.meta.url).pathname;
const { scenes } = JSON.parse(await readFile(BUILD + "timeline.json", "utf8"));

// showinfo reports on stderr.
const log = spawnSync(
  "ffmpeg",
  ["-hide_banner", "-i", BUILD + "scenex-tutorial.mp4", "-vf", "select='gt(scene,0.35)',showinfo", "-f", "null", "-"],
  { encoding: "utf8", env: { ...process.env, LC_ALL: "C" } }
).stderr;
const cuts = [...(log.matchAll(/pts_time:([\d.]+)/g) ?? [])].map((m) => parseFloat(m[1]));

// Scenes that open with a card or a full-screen image cut hard.
const hard = ["megagame", "nobody-wins", "room-tables", "loop", "script", "part-blocks", "mars", "showtime", "later", "goodbye"];
console.log("scene            starts   cut in video   video is");
for (const id of hard) {
  const scene = scenes.find((s) => s.id === id);
  if (!scene) continue;
  const near = cuts.filter((c) => Math.abs(c - scene.start) < 8);
  if (near.length === 0) {
    console.log(`${id.padEnd(16)} ${scene.start.toFixed(1).padStart(6)}   (no cut found)`);
    continue;
  }
  const cut = near.reduce((a, b) => (Math.abs(b - scene.start) < Math.abs(a - scene.start) ? b : a));
  const diff = cut - scene.start;
  console.log(
    `${id.padEnd(16)} ${scene.start.toFixed(1).padStart(6)}   ${cut.toFixed(1).padStart(10)}   ${Math.abs(diff).toFixed(1)} s ${diff < 0 ? "early" : "late"}`
  );
}
