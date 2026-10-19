// Records the screencast: speaks every scene of script.mjs (see voice.mjs
// for the voices), then plays the storyboard in a recorded browser — with a
// visible pointer — holding each scene as long as its line. Captions are
// rendered as separate images for the bar below the picture.
//
// Output in video/build/: frames/<n>.jpg (the picture, with exact paint
// times), audio/<n>.*, captions/<n>.png, timeline.json.
// assemble.mjs turns them into the final MP4.
//
//     node video/record.mjs                                  macOS voice
//     TUTORIAL_TTS=elevenlabs TUTORIAL_ELEVENLABS_VOICE=<id> node video/record.mjs

import { execFileSync } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { chromium } from "playwright";
import { live, login, newContext } from "../lib.mjs";
import { scenes } from "./script.mjs";
import { describe, speak } from "./voice.mjs";

const HERE = new URL(".", import.meta.url).pathname;
const BUILD = HERE + "build/";
const IMAGES = new URL("../../docs/tutorial/images/", import.meta.url).pathname;
// 1280×720 picture + an 80 px caption bar (added by assemble.mjs) = 1280×800.
// (The projected display gets crowded below 720 px of height.)
const SIZE = { width: 1280, height: 720 };
const CAPTION = { width: 1280, height: 80 };

await rm(BUILD, { recursive: true, force: true });
await mkdir(BUILD + "audio", { recursive: true });
await mkdir(BUILD + "captions", { recursive: true });

// ── 1. Narration ────────────────────────────────────────────────────────────
console.log(`Speaking ${scenes.length} lines with the ${describe()}`);
const durationOf = (file) =>
  parseFloat(
    execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file])
      .toString()
      .trim()
  );

const audio = [];
for (const [i, scene] of scenes.entries()) {
  const file = await speak(scene.say, `${BUILD}audio/${String(i).padStart(2, "0")}-${scene.id}`);
  audio.push({ file, seconds: durationOf(file) });
}
const total = audio.reduce((s, a) => s + a.seconds, 0);
console.log(`  ${total.toFixed(0)} s of narration`);

// ── 2. Browser overlay: the pointer ─────────────────────────────────────────
// Survives full page loads by keeping its position in sessionStorage. It is
// invisible until it moves — to click or to point at something — and fades
// out a few seconds after it comes to rest, so title cards, pictures and
// quiet moments stay clean.
const overlays = () => {
  const SHOW_FOR_MS = 3000;
  // Documents made with setContent have no usable storage.
  const load = (k, d) => { try { return sessionStorage.getItem(k) ?? d; } catch { return d; } };
  const save = (k, v) => { try { sessionStorage.setItem(k, v); } catch {} };
  const install = () => {
    if (document.getElementById("__cursor")) return;
    const cursor = document.createElement("div");
    cursor.id = "__cursor";
    Object.assign(cursor.style, {
      position: "fixed", width: "26px", height: "26px", borderRadius: "50%",
      border: "3px solid #ff5a00", background: "rgba(255,90,0,.25)",
      transform: "translate(-50%,-50%)", pointerEvents: "none", zIndex: 2147483647,
      transition: "background .15s, opacity .4s", opacity: "0"
    });
    const pos = JSON.parse(load("__pos", "[640,360]"));
    cursor.style.left = pos[0] + "px";
    cursor.style.top = pos[1] + "px";
    document.body.appendChild(cursor);

    let hideTimer;
    const show = () => {
      cursor.style.opacity = "1";
      clearTimeout(hideTimer);
      hideTimer = setTimeout(() => { cursor.style.opacity = "0"; }, SHOW_FOR_MS);
    };

    document.addEventListener("mousemove", (e) => {
      cursor.style.left = e.clientX + "px";
      cursor.style.top = e.clientY + "px";
      save("__pos", JSON.stringify([e.clientX, e.clientY]));
      show();
    }, true);
    document.addEventListener("mousedown", () => { show(); cursor.style.background = "rgba(255,90,0,.75)"; }, true);
    document.addEventListener("mouseup", () => { cursor.style.background = "rgba(255,90,0,.25)"; }, true);
  };
  if (document.body) install();
  else document.addEventListener("DOMContentLoaded", install);
};

// ── 3. Recording ────────────────────────────────────────────────────────────
const browser = await chromium.launch();

// Backstage: a logged-in page that drives what the camera shouldn't show.
const backstage = await newContext(browser);
const ctl = await backstage.newPage();
await login(ctl);

const studio = await newContext(browser, { viewport: SIZE });
await studio.addInitScript(overlays);
// The projected display is laid out for a 1920×1080 projector; show it at
// that size, scaled into the 1280×720 frame — from the very first paint.
await studio.addInitScript(() => {
  if (location.pathname.startsWith("/display/")) {
    document.documentElement.style.zoom = String(1280 / 1920);
  }
});
const cam = await studio.newPage();
await login(cam);
await cam.goto("about:blank");

// ── The camera: Chrome's screencast ─────────────────────────────────────────
// Every frame arrives with the wall-clock time it was painted, from the same
// clock that places the narration — so picture and voice line up exactly.
// (Playwright's own recordVideo stamps frames at a fixed rate instead, and
// drifts unevenly under load.) Frames only come when the picture changes;
// assemble.mjs holds each one until the next.
await mkdir(BUILD + "frames", { recursive: true });
const frames = [];
const screencast = await studio.newCDPSession(cam);
screencast.on("Page.screencastFrame", async ({ data, metadata, sessionId }) => {
  screencast.send("Page.screencastFrameAck", { sessionId }).catch(() => {});
  const file = `${BUILD}frames/${String(frames.length).padStart(6, "0")}.jpg`;
  frames.push({ file, at: metadata.timestamp });
  await writeFile(file, Buffer.from(data, "base64"));
});
await screencast.send("Page.startScreencast", {
  format: "jpeg",
  quality: 90,
  maxWidth: SIZE.width,
  maxHeight: SIZE.height
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const h = {
  cam,
  ctl,
  state: {},
  wait: (ms) => cam.waitForTimeout(ms),
  async go(url) {
    await cam.goto(url);
    await live(cam);
    await cam.waitForTimeout(400);
  },
  async locate(selector) {
    const el = cam.locator(selector).first();
    await el.waitFor({ state: "visible", timeout: 5000 });
    return el;
  },
  async moveTo(el) {
    await el.scrollIntoViewIfNeeded();
    const box = await el.boundingBox();
    await cam.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 30 });
  },
  // Point at a spot of a full-screen image (1280×720 coordinates).
  async pointAt(x, y) {
    await cam.mouse.move(x, y, { steps: 30 });
  },
  // Calm pacing: let the viewer find the pointer before the click, and see
  // the result after it.
  async click(selector) {
    const el = await h.locate(selector);
    await h.moveTo(el);
    await cam.waitForTimeout(450);
    await el.click();
    await cam.waitForTimeout(800);
  },
  async fill(selector, text) {
    const el = await h.locate(selector);
    await h.moveTo(el);
    await el.click();
    await el.fill("");
    await el.pressSequentially(text, { delay: 45 });
  },
  // Point at something without clicking; never fails the recording.
  async point(selector) {
    try {
      await h.moveTo(await h.locate(selector));
    } catch {
      console.warn(`    (nothing to point at: ${selector})`);
    }
  },
  async scroll(selector) {
    try {
      const el = await h.locate(selector);
      await el.evaluate((e) => e.scrollIntoView({ behavior: "smooth", block: "start" }));
      await cam.waitForTimeout(1200);
    } catch {
      console.warn(`    (nothing to scroll to: ${selector})`);
    }
  },
  async top() {
    await cam.evaluate(() => window.scrollTo({ top: 0, behavior: "smooth" }));
    await cam.waitForTimeout(700);
  },
  // A full-screen title card in Common Ground's colours, optionally over one
  // of the tutorial's images (dimmed).
  async card(title, subtitle, { image } = {}) {
    const background = image
      ? `linear-gradient(rgba(22,56,62,.72),rgba(22,56,62,.72)),url(${await dataUrl(image)}) center/cover`
      : "radial-gradient(circle at 70% 35%,#2f6f73,#16383E 70%)";
    await cam.setContent(`<!doctype html><html><body style="margin:0;height:100vh;display:flex;
      flex-direction:column;align-items:center;justify-content:center;text-align:center;
      background:${background};color:#fff;font-family:system-ui,sans-serif">
      <h1 style="font-size:76px;margin:0;color:#f6c915;letter-spacing:.5px">${title}</h1>
      <p style="font-size:30px;margin:18px 80px 0;opacity:.92">${subtitle}</p></body></html>`);
    await cam.evaluate(overlays);
  },
  async image(name, { fit = "cover", background = "#000" } = {}) {
    await cam.setContent(`<!doctype html><html><body style="margin:0;background:${background};
      height:100vh;display:flex;align-items:center;justify-content:center">
      <img src="${await dataUrl(name)}" style="width:100vw;height:100vh;object-fit:${fit}"></body></html>`);
    await cam.evaluate(overlays);
  }
};

// Images for cards come from docs/tutorial/images/ (PNG, JPG or SVG).
async function dataUrl(name) {
  const file = IMAGES + name.replace(/^\/?images\//, "");
  const type = file.endsWith(".svg") ? "image/svg+xml" : file.endsWith(".jpg") ? "image/jpeg" : "image/png";
  return `data:${type};base64,${(await readFile(file)).toString("base64")}`;
}

const t0 = Date.now();
const timeline = [];
for (const [i, scene] of scenes.entries()) {
  const start = (Date.now() - t0) / 1000;
  // Each scene lingers a little after its line, so the picture can sink in.
  const hold = audio[i].seconds + 1.6;
  console.log(`  ${String(i).padStart(2)} ${scene.id} (${hold.toFixed(1)} s)`);
  await scene.act(h);
  const elapsed = (Date.now() - t0) / 1000 - start;
  if (elapsed < hold) await sleep((hold - elapsed) * 1000);
  timeline.push({ id: scene.id, start, end: (Date.now() - t0) / 1000, text: scene.say, audio: audio[i].file });
}

// Caption bar images, one per scene.
const bar = await browser.newPage({ viewport: CAPTION });
for (const [i, scene] of scenes.entries()) {
  await bar.setContent(`<!doctype html><html><body style="margin:0;height:${CAPTION.height}px;
    display:flex;align-items:center;justify-content:center;background:#141418;color:#fff;
    font:500 21px/1.3 system-ui,sans-serif;text-align:center;padding:0 60px;box-sizing:border-box">
    ${scene.say.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</body></html>`);
  const file = `${BUILD}captions/${String(i).padStart(2, "0")}.png`;
  await bar.screenshot({ path: file });
  timeline[i].caption = file;
}

await screencast.send("Page.stopScreencast");
await sleep(500);
await studio.close();
await backstage.close();
await browser.close();

// Frame times relative to the first scene (t0), like the scene times.
const relFrames = frames.map((f) => ({ file: f.file, at: f.at - t0 / 1000 }));
await writeFile(
  BUILD + "timeline.json",
  JSON.stringify({ scenes: timeline, frames: relFrames }, null, 2)
);
console.log(`Recorded ${timeline.length} scenes, ${frames.length} frames`);
