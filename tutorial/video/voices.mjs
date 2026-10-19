// Lists the ElevenLabs voices available to the account (free — listing costs
// no credits): id, name and labels such as gender, accent and age.
//
//     node video/voices.mjs [filter]

import { apiKey } from "./voice.mjs";

const filter = (process.argv[2] || "").toLowerCase();
const response = await fetch("https://api.elevenlabs.io/v1/voices", {
  headers: { "xi-api-key": await apiKey() }
});
if (!response.ok) throw new Error(`ElevenLabs ${response.status}: ${await response.text()}`);

const { voices } = await response.json();
for (const v of voices) {
  const labels = Object.entries(v.labels || {}).map(([k, val]) => `${k}: ${val}`).join(", ");
  const line = `${v.voice_id}  ${v.name}  (${labels})`;
  if (!filter || line.toLowerCase().includes(filter)) console.log(line);
}
