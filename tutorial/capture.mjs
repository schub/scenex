// Captures every screenshot used by docs/tutorial/ from a running Scenex
// instance loaded by tutorial/setup.exs (Common Ground + Mars Colony). Each
// `shot` name is the image file the Markdown pages reference, so keep them
// stable.
//
//     node capture.mjs [output-dir]

import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";
import {
  BASE,
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

const CG = "COMMON GROUND";
const MARS = "mars_colony";

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


async function boardPage(url) {
  const board = await browser.newPage({
    viewport: { width: 820, height: 1180 },
    locale: "en-US",
    colorScheme: "light"
  });
  await board.goto(url);
  await live(board);
  return board;
}

// Creating a session lands in the classic console; the tutorial uses the new
// one (the classic console is on its way out).
async function newSession(editorUrl, label, { locale } = {}) {
  await page.goto(editorUrl + "/sessions");
  await live(page);
  await page.fill("input[name='session[label]']", label);
  if (locale) await page.selectOption("select[name='session[locale]']", locale);
  await page.click("button:has-text('Create session')");
  await page.waitForURL(/\/console$/);
  await live(page);
  await toNewConsole();
}

async function toNewConsole() {
  await page.click("#switch-console");
  await page.waitForURL(/\/console\/new/);
  await live(page);
}

// The new console's three areas.
const BEAT = "#beat-detail";
const ROOM = "#room";

// Selects a beat in the timeline list by its number ("6." — two beats can
// share a title).
async function beat(number) {
  await page
    .locator("#timeline li")
    .filter({ hasText: new RegExp(`^\\s*${number}\\.\\s`) })
    .locator("a")
    .first()
    .click();
  await settle(page);
  return page.locator(BEAT);
}

async function trigger(number) {
  const detail = await beat(number);
  await detail.locator("button:has-text('Trigger')").first().click();
  await settle(page, 600);
  return detail;
}

// The Access & QR drawer: makes the codes, returns their links, closes.
async function codes(groups, { shotName } = {}) {
  await page.click("#open-access");
  await settle(page, 500);
  const drawer = page.locator("#access-drawer");
  for (const g of groups) {
    await drawer.locator(`button:has-text("+ Code: ${g}")`).click();
    await settle(page, 250);
  }
  if (shotName) await shot(shotName);
  const links = await drawer.locator("a[target=_blank]").evaluateAll((as) => as.map((a) => a.href));
  await page.keyboard.press("Escape");
  await settle(page);
  return links;
}

async function choose(scope, keys) {
  for (const k of keys) {
    await scope.locator(`[phx-click=choose]:has-text("${k}")`).first().click();
    await settle(page, 250);
  }
}

async function showPage(key, display, name) {
  await page.locator(ROOM).locator(`[phx-click=show_page]:has-text("${key}")`).click();
  await settle(page, 900);
  if (name) await shot(name, display);
}

async function clearPage() {
  await page.locator("button:has-text('Back to scoreboard')").first().click();
  await settle(page);
}

const CG_GROUPS = [
  "Chamber of Commerce",
  "Arts, Culture, Sport",
  "Customer's Protection",
  "Voluntary Sector",
  "Public Services"
];

// ── Part 2: the editor (Common Ground) ──────────────────────────────────────
console.log("Editor");
await page.goto(BASE + "/users/log-in");
await live(page);
await shot("login");
await login(page);
await page.goto(BASE + "/scenarios");
await live(page);
await shot("scenarios");
const cgEditor = await openEditor(page, CG);
await shot("editor-settings", page, { full: true });

await tab(page, "values");
await pick(page, "edit_value", "stability");
await shot("values-stability", page, { full: true });
await pick(page, "edit_value", "well_being");
await shot("values-wellbeing", page, { full: true });
await tab(page, "overall_index");
await shot("overall-index", page, { full: true });

await tab(page, "groups");
await pick(page, "edit_group", "Chamber of Commerce");
await shot("groups-chamber");
await tab(page, "initial");
await shot("initial-values");

await tab(page, "timeline");
await pick(page, "open_event", "Key Event 1");
await shot("timeline-event", page, { full: true });
await editOption(page, "A) Chamber of Commerce - public market");
await shot("timeline-option", page, { full: true });
await page.click("text=← Back");
await settle(page);
await pick(page, "open_event", "Referendum 2");
await shot("timeline-vote", page, { full: true });
await editOption(page, "Social Media Policy A - Ban");
await shot("timeline-vote-matrix", page, { full: true });
await page.click("text=← Back");
await settle(page);
await pick(page, "open_event", "WILD CARD FREEZE COC");
await shot("timeline-wildcard", page, { full: true });

await tab(page, "pages");
await pick(page, "edit_page", "Common Ground Title");
await shot("pages", page, { full: true });
await tab(page, "media");
await shot("media", page, { full: true });
await tab(page, "members");
await shot("members");

// Translation: a first German name and title, saved for the German session.
console.log("Translation");
await page.click("[phx-click=set_locale][phx-value-locale=de]");
await settle(page);
await tab(page, "groups");
await pick(page, "edit_group", "Chamber of Commerce");
await page.fill("input[name='group[name][de]']", "Handelskammer");
await shot("translate-de");
await page.click("button:has-text('Save group')");
await settle(page);
await tab(page, "timeline");
await pick(page, "open_event", "ONBOARDING");
await page.fill("input[name='timeline_element[title][de]']", "Wählt euren Slogan!");
await page.click("button:has-text('Save element')");
await settle(page);
await page.click("[phx-click=set_locale][phx-value-locale=en]");
await settle(page);

// ── The dry run ─────────────────────────────────────────────────────────────
console.log("Dry run");
await page.goto(cgEditor + "/simulate");
await live(page);
await shot("dryrun-start");
for (const slogan of ["Slogan COC 1", "Slogan ASR 2", "Slogan CONA 1", "Slogan CA 2.0", "Slogan PS 3"]) {
  await page.click(`[phx-click=toggle_option]:has-text("${slogan}")`);
  await settle(page, 200);
}
await page.evaluate(() => window.scrollTo(0, 0));
await shot("dryrun-after");

// ── 🪐 Mars Colony, where it shows something Common Ground doesn't ───────────
console.log("Mars Colony (editor)");
const marsEditor = await openEditor(page, MARS);
await tab(page, "values");
await pick(page, "edit_value", "life_support");
await shot("values-mars-life-support", page, { full: true });
await tab(page, "timeline");
await pick(page, "open_event", "settling_in");
await editOption(page, "Battery bank");
await shot("timeline-option-gate-mars", page, { full: true });
await tab(page, "endings");
await pick(page, "edit_ending", "colony_holds");
await shot("endings-mars", page, { full: true });
await tab(page, "labels");
await pick(page, "edit_label", "cautious");
await shot("labels-mars");

// ── Part 3: an evening of Common Ground (in the new GM console) ─────────────
console.log("Session");
await page.goto(cgEditor + "/sessions");
await live(page);
await page.fill("input[name='session[label]']", "Common Ground — Friday Premiere");
await shot("session-new");
await page.click("button:has-text('Create session')");
await page.waitForURL(/\/console$/);
await live(page);
await page.screenshot({ path: `${OUT}/console-classic-switch.png`, clip: { x: 0, y: 0, width: 1440, height: 200 } });
taken.push("console-classic-switch");
await toNewConsole();
await shot("console-draft");

const links = await codes([...CG_GROUPS, "projected display"], { shotName: "console-access" });
const chamberUrl = links.find((l) => l.includes("/play/"));
const displayUrl = links.find((l) => l.includes("/display/"));

console.log("Live show");
// Projectors usually run at 1920×1080; the display is laid out for that.
const display = await context.newPage();
await display.setViewportSize({ width: 1920, height: 1080 });
await display.goto(displayUrl);
await live(display);
await shot("display-waiting", display);

await page.bringToFront();
await showPage("Common Ground Title", display, "display-page-title");
await showPage("Welcome to Lux", display, "display-page-welcome");
// The room panel is taller than a laptop screen; show all of it once.
await page.setViewportSize({ width: 1440, height: 1250 });
await settle(page);
await shot("console-room", page.locator(ROOM));
await page.setViewportSize({ width: 1440, height: 900 });
await settle(page);
await clearPage();

await page.click("button:has-text('Start session')");
await settle(page);
await shot("console-live");

const board = await boardPage(chamberUrl);
await shot("board-waiting", board);

// The warm-up: the Chamber of Commerce decides on its own tablet.
const slogans = await trigger(1);
await settle(board);
await shot("board-event", board);
await shot("display-event", display);
await board.click("[phx-click=select]:has-text('Come on in')");
await settle(board);
await shot("board-confirm", board);
await board.click("[phx-click=choose]");
await settle(board);
await shot("board-chosen", board);

await choose(slogans, ["Slogan ASR 2", "Slogan CONA 1", "Slogan CA 2.0", "Slogan PS 3"]);
await shot("console-event-decided");
await shot("console-board", page.locator(ROOM).locator("section").first());
await settle(display, 600);
await shot("display-after-slogans", display);

// Showing the room how everyone decided.
await slogans.locator("button:has-text('Decisions on screen')").click();
await settle(page, 600);
// Just the top of the beat: title and its buttons.
const top = await slogans.boundingBox();
await page.screenshot({
  path: `${OUT}/console-decisions-on-screen.png`,
  clip: { x: top.x, y: top.y, width: top.width, height: 150 }
});
taken.push("console-decisions-on-screen");
await settle(display, 600);
await shot("display-decisions", display);

// Asking the room.
await showPage("Happiness Survey", display, "display-page-survey");
const wellbeing = page.locator(ROOM).locator("section:has(h3:has-text('Well-Being'))");
for (const [score, count] of [[4, 9], [3, 14], [2, 8], [1, 3]]) {
  await wellbeing.locator(`input[name='counts[${score}]']`).fill(String(count));
}
await shot("console-tally-form", wellbeing);
await wellbeing.locator("button:has-text('Record tally')").click();
await settle(page);
await shot("console-tally", wellbeing);
await clearPage();

// Key Event 1, against the clock.
const ke1 = await trigger(2);
await shot("console-deadline");
await choose(ke1, [
  "A) Chamber of Commerce - public market",
  "B) Arts & CO",
  "B) Customer's Protections",
  "C) Voluntary Sector",
  "A) Public Services"
]);

// Two versions of Key Event 3 (6 = higher, 7 = lower): trigger the one that fits.
await trigger(6);
await shot("console-shade");

// The Freeze Card.
const freeze = await trigger(25);
await freeze.locator("[phx-click=adjudicate]:has-text('success')").click();
await settle(page);
await shot("console-wildcard", page.locator(BEAT));

// Referendum 2: the social media policy, with its options on the wall.
const vote = await trigger(12);
await settle(display, 600);
await shot("display-vote", display);
await vote.locator("button:has-text('Options on screen')").click();
await settle(page, 600);
await settle(display, 600);
await shot("display-ballot", display);
for (const [option, votes] of [
  ["Social Media Policy A - Ban", 9],
  ["Social Media Policy B - Regulate", 21],
  ["Social Media Policy C - Educate", 14]
]) {
  await vote.locator(`div:has(> label:has-text("${option}")) input[name^='tally']`).fill(String(votes));
}
await vote.locator("label:has-text('Social Media Policy B - Regulate') input[type=radio]").check();
await shot("console-vote");
await vote.locator("button:has-text('Declare result')").click();
await settle(page);
await settle(display, 800);
await shot("display-vote-result", display);

// The finale — Common Ground ends on a page (its endings are pages).
await page.click("button:has-text('End')");
await settle(page);
await showPage("Final - Good Ending", display, "display-page-final");

// ── Your Common Ground: a German session, half translated ───────────────────
console.log("German session");
await newSession(cgEditor, "Berlin — Probe", { locale: "de" });
const deLinks = await codes(["Handelskammer"]);
await page.click("button:has-text('Start session')");
await settle(page);
await trigger(1);
const deBoard = await boardPage(deLinks.find((l) => l.includes("/play/")));
await shot("board-german", deBoard);

// ── 🪐 Mars Colony on stage: its title page and a locked option ──────────────
console.log("Mars Colony (session)");
await newSession(marsEditor, "Mars Colony — Youth Theatre");
const marsLinks = await codes(["Engineering & Habitat", "projected display"]);
const marsDisplay = await context.newPage();
await marsDisplay.setViewportSize({ width: 1920, height: 1080 });
await marsDisplay.goto(marsLinks.find((l) => l.includes("/display/")));
await live(marsDisplay);
await page.bringToFront();
await showPage("Title", marsDisplay, "display-page-mars");
await clearPage();
await page.click("button:has-text('Start session')");
await settle(page);
for (const [number, option] of [
  [1, "3D printer"],
  [2, "Solar field first"]
]) {
  const detail = await trigger(number);
  await detail.locator(`[phx-click=choose]:has-text("${option}")`).first().click();
  await settle(page);
}
await trigger(3);
const marsBoard = await boardPage(marsLinks.find((l) => l.includes("/play/")));
await shot("board-gated-mars", marsBoard);

// Mars Colony has real endings: end the show and let the console recommend.
await page.bringToFront();
await page.click("button:has-text('End')");
await settle(page);
await page.locator("#timeline").locator("text=Choose the ending").click();
await settle(page);
await shot("console-endings-mars");

await browser.close();
console.log(`\n${taken.length} screenshots in ${OUT}`);

