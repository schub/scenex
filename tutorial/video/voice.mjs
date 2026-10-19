// Turns one narration line into an audio file, with one of two engines:
//
//   * "say" (default) — the macOS voice; free, offline, robotic.
//   * "elevenlabs"    — natural voices; costs credits per character. Every
//     line is cached by (voice, model, text) in video/cache/, so re-recording
//     only pays for lines whose text changed. Never used unless asked for.
//
// Engine and voice come from the environment:
//
//   TUTORIAL_TTS=elevenlabs            switch to ElevenLabs
//   TUTORIAL_ELEVENLABS_VOICE=<id>     the voice id (see voices.mjs)
//   TUTORIAL_VOICE / TUTORIAL_RATE     the macOS voice and speed
//
// The ElevenLabs API key is read from ELEVENLABS_API_KEY, or from the env
// file ~/.config/scenex.org/scenex-tutorial.env (never from the repository).

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";

const CACHE = new URL("cache/", import.meta.url).pathname;
const ENV_FILE = `${homedir()}/.config/scenex.org/scenex-tutorial.env`;
const MODEL = process.env.TUTORIAL_ELEVENLABS_MODEL || "eleven_multilingual_v2";

export const engine = process.env.TUTORIAL_TTS === "elevenlabs" ? "elevenlabs" : "say";

export function describe() {
  return engine === "elevenlabs"
    ? `ElevenLabs voice ${process.env.TUTORIAL_ELEVENLABS_VOICE} (${MODEL})`
    : `macOS voice "${process.env.TUTORIAL_VOICE || "Samantha"}"`;
}

// How names are spoken. Captions keep the written form; only the voice gets
// the respelling ("Scenex" sounds like "scene" + "ex").
const PRONUNCIATION = [[/\bScenex\b/g, "Scene-ex"]];

export function spoken(text) {
  return PRONUNCIATION.reduce((t, [pattern, sound]) => t.replace(pattern, sound), text);
}

// Writes `text` as speech to `base` + extension; returns the file path.
export async function speak(text, base) {
  const words = spoken(text);
  return engine === "elevenlabs" ? elevenlabs(words, base) : say(words, base);
}

function say(text, base) {
  const file = base + ".aiff";
  execFileSync("say", [
    "-v", process.env.TUTORIAL_VOICE || "Samantha",
    "-r", process.env.TUTORIAL_RATE || "175",
    "-o", file,
    text
  ]);
  return file;
}

export async function apiKey() {
  if (process.env.ELEVENLABS_API_KEY) return process.env.ELEVENLABS_API_KEY;
  if (!existsSync(ENV_FILE)) throw new Error(`No ELEVENLABS_API_KEY and no ${ENV_FILE}`);
  const line = (await readFile(ENV_FILE, "utf8"))
    .split("\n")
    .find((l) => l.trim().startsWith("ELEVENLABS_API_KEY="));
  if (!line) throw new Error(`${ENV_FILE} has no ELEVENLABS_API_KEY=… line`);
  return line.split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "");
}

async function elevenlabs(text, base) {
  const voice = process.env.TUTORIAL_ELEVENLABS_VOICE;
  if (!voice) throw new Error("Set TUTORIAL_ELEVENLABS_VOICE to a voice id (see video/voices.mjs)");

  const key = createHash("sha256").update(`${voice}\n${MODEL}\n${text}`).digest("hex").slice(0, 24);
  const cached = `${CACHE}${key}.mp3`;
  const file = base + ".mp3";

  if (!existsSync(cached)) {
    const response = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: { "xi-api-key": await apiKey(), "content-type": "application/json" },
        body: JSON.stringify({ text, model_id: MODEL })
      }
    );
    if (!response.ok) {
      throw new Error(`ElevenLabs ${response.status}: ${(await response.text()).slice(0, 300)}`);
    }
    await mkdir(CACHE, { recursive: true });
    await writeFile(cached, Buffer.from(await response.arrayBuffer()));
    console.log(`    + generated (${text.length} characters)`);
  }

  await copyFile(cached, file);
  return file;
}
