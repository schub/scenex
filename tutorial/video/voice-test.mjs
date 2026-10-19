// Speaks one scene's line with the configured voice, to listen before a full
// recording. With ElevenLabs the line is cached, so the full run reuses it.
//
//     TUTORIAL_TTS=elevenlabs TUTORIAL_ELEVENLABS_VOICE=<id> node video/voice-test.mjs [scene-id]

import { mkdir } from "node:fs/promises";
import { scenes } from "./script.mjs";
import { describe, speak, spoken } from "./voice.mjs";

const id = process.argv[2] || scenes[0].id;
const scene = scenes.find((s) => s.id === id);
if (!scene) throw new Error(`No scene "${id}"`);

const dir = new URL("build/", import.meta.url).pathname;
await mkdir(dir, { recursive: true });
console.log(`${describe()} says: ${spoken(scene.say)}`);
const file = await speak(scene.say, `${dir}test-${id}`);
console.log(`→ ${file}`);
