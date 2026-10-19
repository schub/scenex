// Shows one ElevenLabs voice's details — name, labels, description, and
// whether this account can use it (free; costs no credits).
//
//     node video/voice-info.mjs <voice-id>

import { apiKey } from "./voice.mjs";

const id = process.argv[2];
if (!id) throw new Error("usage: node video/voice-info.mjs <voice-id>");

const response = await fetch(`https://api.elevenlabs.io/v1/voices/${id}`, {
  headers: { "xi-api-key": await apiKey() }
});
console.log(`HTTP ${response.status}`);
const voice = await response.json();
if (!response.ok) {
  console.log(JSON.stringify(voice, null, 2).slice(0, 600));
} else {
  console.log(`name:        ${voice.name}`);
  console.log(`category:    ${voice.category}`);
  console.log(`labels:      ${JSON.stringify(voice.labels)}`);
  console.log(`description: ${voice.description ?? "—"}`);
  console.log(`models:      ${(voice.high_quality_base_model_ids || []).join(", ") || "—"}`);
  console.log(`sharing:     ${JSON.stringify(voice.sharing ? { status: voice.sharing.status, free_users_allowed: voice.sharing.free_users_allowed } : null)}`);
}
