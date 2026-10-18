// Captures every screenshot used by docs/tutorial/ from a running Scenex
// instance seeded with Mars Colony (see run.sh). Each `shot` name is the image
// file the Markdown pages reference, so keep them stable.
//
//     node capture.mjs [output-dir]

import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";
import {
  BASE,
  consoleElement,
  editOption,
  live,
  login,
  newContext,
  openEditor,
  pick,
  settle,
  tab
} from "./lib.mjs";

const OUT = process.argv[2] || new URL("../docs/tutorial/images/", import.meta.url).pathname;
await mkdir(OUT, { recursive: true });

const browser = await chromium.launch();
const context = await newContext(browser);
const page = await context.newPage();
const taken = [];

// Viewport screenshot by default; `full` for the whole page, or a locator to
// crop to one element.
async function shot(name, target = page, { full = false } = {}) {
  const path = `${OUT}/${name}.png`;
  if (typeof target.goto === "function") {
    await target.waitForTimeout(300);
    await target.screenshot({ path, fullPage: full });
  } else {
    await target.scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);
    await target.screenshot({ path });
  }
  taken.push(name);
  console.log("  ✓", name);
}

// ── 1. Getting started ──────────────────────────────────────────────────────
console.log("Getting started");
await page.goto(BASE + "/users/log-in");
await live(page);
await shot("login");
await login(page);
await page.goto(BASE + "/scenarios");
await live(page);
await shot("scenarios");
const editorUrl = await openEditor(page);
await shot("editor-settings", page, { full: true });

// ── 2. Values ───────────────────────────────────────────────────────────────
console.log("Values & index");
await tab(page, "values");
await pick(page, "edit_value", "life_support");
await shot("values-life-support", page, { full: true });
await pick(page, "edit_value", "morale");
await shot("values-morale", page, { full: true });
await tab(page, "overall_index");
await shot("overall-index", page, { full: true });

// ── 3. Groups ───────────────────────────────────────────────────────────────
console.log("Groups");
await tab(page, "groups");
await pick(page, "edit_group", "command");
await shot("groups-command", page, { full: true });
await tab(page, "initial");
await shot("initial-values");

// ── 4. Timeline ─────────────────────────────────────────────────────────────
console.log("Timeline");
await tab(page, "timeline");
await pick(page, "open_event", "what_to_bring");
await shot("timeline-event", page, { full: true });
await pick(page, "open_event", "settling_in");
await editOption(page, "Battery bank");
await shot("timeline-option-gate", page, { full: true });
await page.click("text=← Back");
await settle(page);
await pick(page, "open_event", "green_thumb");
await shot("timeline-wildcard", page, { full: true });
await pick(page, "open_event", "earths_offer");
await shot("timeline-vote", page, { full: true });
await editOption(page, "Extend the mission");
await shot("timeline-vote-matrix", page, { full: true });
await page.click("text=← Back");
await settle(page);

// ── 5. Labels, endings, pages, media, members ───────────────────────────────
console.log("Labels, endings, pages, media, members");
await tab(page, "labels");
await pick(page, "edit_label", "cautious");
await shot("labels");
await tab(page, "endings");
await pick(page, "edit_ending", "colony_holds");
await shot("endings", page, { full: true });
await tab(page, "pages");
await pick(page, "edit_page", "Mission Briefing");
await shot("pages", page, { full: true });
await tab(page, "media");
await shot("media");
await tab(page, "members");
await shot("members");

// ── 6. Translation ──────────────────────────────────────────────────────────
console.log("Translation");
await page.click("[phx-click=set_locale][phx-value-locale=de]");
await settle(page);
await tab(page, "groups");
await pick(page, "edit_group", "engineering");
await shot("translate-de");
await page.click("[phx-click=set_locale][phx-value-locale=en]");
await settle(page);

// ── 7. Dry run ──────────────────────────────────────────────────────────────
console.log("Dry run");
await page.goto(editorUrl + "/simulate");
await live(page);
await shot("dryrun-start");
// Play the Prologue the careful way, then look at the board again.
for (const option of [
  "Spare parts",
  "Lab supplies",
  "Proven hydroponics",
  "Medicine stockpile",
  "Oxygen reserves"
]) {
  await page.click(`[phx-click=toggle_option]:has-text("${option}")`);
  await settle(page, 250);
}
await page.evaluate(() => window.scrollTo(0, 0));
await shot("dryrun-after-prologue");
await page.locator("h2:has-text('Endings'), h3:has-text('Endings')").first().scrollIntoViewIfNeeded();
await shot("dryrun-endings");

// ── 8. Sessions ─────────────────────────────────────────────────────────────
console.log("Sessions");
await page.goto(editorUrl + "/sessions");
await live(page);
await page.fill("input[name='session[label]']", "Youth Theatre Lisbon — 14 Nov");
await shot("session-new");
await page.click("button:has-text('Create session')");
await page.waitForURL(/\/console$/);
await live(page);
const consoleUrl = page.url();
await shot("console-draft");

// Access codes for every table and the wall.
for (const team of [
  "Engineering & Habitat",
  "Science & Exploration",
  "Agriculture & Life Systems",
  "Medical & Crew Welfare",
  "Command & Earth Relations",
  "projected display"
]) {
  await page.click(`button:has-text('+ Code: ${team}')`);
  await settle(page, 250);
}
const access = page.locator("section:has(h3:has-text('Access'))");
await shot("console-access", access);
const links = await page.$$eval("a[target=_blank]", (as) => as.map((a) => a.href));
const engineeringUrl = links.find((l) => l.includes("/play/"));
const displayUrl = links.find((l) => l.includes("/display/"));

// ── 9. Live show ────────────────────────────────────────────────────────────
console.log("Live show");
const display = await context.newPage();
await display.goto(displayUrl);
await live(display);
await shot("display-waiting", display);

await page.bringToFront();
await page.click("button:has-text('Welcome')");
await settle(page);
await shot("display-page-welcome", display);
await page.screenshot({ path: `${OUT}/console-pages.png`, clip: { x: 0, y: 0, width: 1440, height: 330 } });
taken.push("console-pages");
await page.click("button:has-text('Back to scoreboard')");
await settle(page);

await page.click("button:has-text('Start session')");
await settle(page);
await shot("console-live");

// What to Bring: Engineering decides on its own tablet, the GM enters the rest.
const board = await browser.newPage({
  viewport: { width: 820, height: 1180 },
  locale: "en-US",
  colorScheme: "light"
});
await board.goto(engineeringUrl);
await live(board);
await shot("board-waiting", board);

await consoleElement(page, "What to Bring").locator("button:has-text('Trigger')").click();
await settle(page);
await settle(board);
await shot("board-event", board, { full: true });
await shot("display-event", display);

await board.click("[phx-click=select]:has-text('3D printer')");
await settle(board);
await shot("board-confirm", board);
await board.click("[phx-click=choose]");
await settle(board);
await shot("board-chosen", board, { full: true });

async function gmChoose(title, choices) {
  const card = consoleElement(page, title);
  for (const option of choices) {
    await card.locator(`[phx-click=choose]:has-text("${option}")`).first().click();
    await settle(page, 250);
  }
  return card;
}

const prologue = await gmChoose("What to Bring", [
  "Lab supplies",
  "Seed vault",
  "Medicine stockpile",
  "Oxygen reserves"
]);
await shot("console-event-decided", prologue);
await shot("console-board", page.locator("table").first());
await settle(display, 600);
await shot("display-after-prologue", display);

// Touchdown, then Settling In — where Engineering's gate bites.
const touchdown = consoleElement(page, "Touchdown");
await touchdown.locator("button:has-text('Trigger')").click();
await settle(page);
await gmChoose("Touchdown", [
  "Solar field first",
  "Help unpack",
  "Test the soil first",
  "Open the common room",
  "Honest report"
]);

await consoleElement(page, "Settling In").locator("button:has-text('Trigger')").click();
await settle(page);
await settle(board);
await shot("board-gated", board, { full: true });
await gmChoose("Settling In", [
  "Bury the cables",
  "Share the lab",
  "Algae tanks",
  "Mental health program",
  "Colony council"
]);

// Morale tally #1 (scores 1–5, counted by show of hands).
const morale = page.locator("section:has(h3:has-text('Morale'))");
for (const [score, count] of [
  [5, 6],
  [4, 9],
  [3, 7],
  [2, 3],
  [1, 0]
]) {
  await morale.locator(`input[name='counts[${score}]']`).fill(String(count));
}
await shot("console-tally-form", morale);
await morale.locator("button:has-text('Record tally')").click();
await settle(page);
await shot("console-tally", morale);

// A Wildcard: The Find, adjudicated as a success.
const find = consoleElement(page, "The Find");
await find.locator("button:has-text('Trigger')").click();
await settle(page);
await find.locator("[phx-click=adjudicate]:has-text('success')").click();
await settle(page);
await shot("console-wildcard", find);

// Act 2: The Storm, with Command calling Earth.
await page.click("button:has-text('Sol 40')");
await settle(page);
await shot("display-page-act-break", display);
await page.click("button:has-text('Back to scoreboard')");
await settle(page);

const storm = consoleElement(page, "The Storm");
await storm.locator("button:has-text('Trigger')").click();
await settle(page);
await settle(board);
await shot("board-storm", board, { full: true });
await shot("console-deadline", storm);
await gmChoose("The Storm", [
  "Power down",
  "Track the storm",
  "Let the crops sleep",
  "Shelter in the core",
  "Call Earth"
]);
await shot("console-storm-decided", storm);

// The milder Rationing shade (Vitality is still "Getting By").
const rationing = page
  .locator("section")
  .filter({ has: page.locator("h3:has-text('Rationing')") })
  .filter({ hasText: "Shade: Holding Together" })
  .first();
await rationing.locator("button:has-text('Trigger')").click();
await settle(page);
for (const option of [
  "Shut one module",
  "Pause the research",
  "Ration the greenhouse",
  "Triage the equipment",
  "Fair shares"
]) {
  await rationing.locator(`[phx-click=choose]:has-text("${option}")`).click();
  await settle(page, 250);
}
await shot("console-shade", rationing);

// Earth's Offer: a hand-count vote.
await page.click("[phx-click=show_page]:has-text(\"Earth's Offer\")");
await settle(page);
await shot("display-page-offer", display);
await page.click("button:has-text('Back to scoreboard')");
await settle(page);

const vote = consoleElement(page, "Earth's Offer");
await vote.locator("button:has-text('Trigger')").click();
await settle(page);
await shot("display-vote", display);
for (const [option, votes] of [
  ["Sponsor deal", 7],
  ["Extend the mission", 12],
  ["Go it alone", 6]
]) {
  await vote.locator(`label:has-text("${option}")`).locator("..").locator("input[type=number]").fill(String(votes));
}
await vote.locator("label:has-text('Extend the mission') input[type=radio]").check();
await shot("console-vote", vote);
await vote.locator("button:has-text('Declare result')").click();
await settle(page);
await settle(display, 600);
await shot("display-vote-result", display);

// The end.
await page.click("button:has-text('End')");
await settle(page);
const endings = page.locator("section:has(h3:has-text('Choose the ending'))");
await shot("console-endings", endings);
await endings.locator("li").filter({ hasText: "recommended" }).first().locator("button").click();
await settle(page);
await settle(display, 800);
await shot("display-ending", display);

// The PDF of QR codes, for the venue printer.
const pdf = await page.request.get(consoleUrl.replace(/console$/, "qr_codes.pdf"));
console.log(`  ✓ qr_codes.pdf (${(await pdf.body()).length} bytes, not saved)`);

await browser.close();
console.log(`\n${taken.length} screenshots in ${OUT}`);
