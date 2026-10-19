// Shows the ElevenLabs account's character (credit) usage — free to call.
//
//     node video/credits.mjs

import { apiKey } from "./voice.mjs";

const response = await fetch("https://api.elevenlabs.io/v1/user/subscription", {
  headers: { "xi-api-key": await apiKey() }
});
const sub = await response.json();
if (!response.ok) throw new Error(`ElevenLabs ${response.status}: ${JSON.stringify(sub)}`);

const reset = sub.next_character_count_reset_unix
  ? new Date(sub.next_character_count_reset_unix * 1000).toISOString().slice(0, 10)
  : "—";
console.log(`plan:   ${sub.tier}`);
console.log(`used:   ${sub.character_count} of ${sub.character_limit} credits`);
console.log(`resets: ${reset}`);
