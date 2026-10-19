// Writes video/storyboard.md — the screencast's script as a readable table
// (screen + narration per scene), for reviewing the text before recording.
//
//     node video/storyboard.mjs

import { writeFile } from "node:fs/promises";
import { scenes } from "./script.mjs";

// Roughly 2.4 spoken words per second, plus the pause record.mjs adds.
const seconds = (text) => text.split(/\s+/).length / 2.4 + 1.6;
const total = scenes.reduce((sum, s) => sum + seconds(s.say), 0);
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

let at = 0;
const rows = scenes.map((s, i) => {
  const row = `| ${i + 1} | ${clock(at)} | ${s.screen} | ${s.say} |`;
  at += seconds(s.say);
  return row;
});

await writeFile(
  new URL("storyboard.md", import.meta.url),
  `# Video storyboard

> Generated from \`tutorial/video/script.mjs\` by \`node video/storyboard.mjs\` —
> edit the script, not this file. Times are estimates (≈ ${clock(total)} in total).

| # | ≈ at | On screen | Narration |
|---|---|---|---|
${rows.join("\n")}
`
);
console.log(`Wrote video/storyboard.md (${scenes.length} scenes, ≈ ${clock(total)})`);
