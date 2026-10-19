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

// One image spanning several elements (e.g. two console cards).
async function shotSpan(name, locators) {
  await locators[0].scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  const boxes = await Promise.all(locators.map((l) => l.boundingBox()));
  const top = Math.min(...boxes.map((b) => b.y));
  const bottom = Math.max(...boxes.map((b) => b.y + b.height));
  await page.screenshot({
    path: `${OUT}/${name}.png`,
    clip: { x: 0, y: top - 8, width: page.viewportSize().width, height: bottom - top + 16 }
  });
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

async function newSession(editorUrl, label, { locale } = {}) {
  await page.goto(editorUrl + "/sessions");
  await live(page);
  await page.fill("input[name='session[label]']", label);
  if (locale) await page.selectOption("select[name='session[locale]']", locale);
  await page.click("button:has-text('Create session')");
  await page.waitForURL(/\/console$/);
  await live(page);
}

async function codes(groups) {
  for (const g of groups) {
    await page.click(`button:has-text("+ Code: ${g}")`);
    await settle(page, 250);
  }
  return page.$$eval("a[target=_blank]", (as) => as.map((a) => a.href));
}

async function choose(card, handles) {
  for (const h of handles) {
    await card.locator(`[phx-click=choose]:has-text("${h}")`).first().click();
    await settle(page, 250);
  }
}

async function showPage(handle, display, name) {
  await page.click(`[phx-click=show_page]:has-text("${handle}")`);
  await settle(page, 900);
  if (name) await shot(name, display);
}

async function clearPage() {
  await page.click("button:has-text('Back to scoreboard')");
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

// ── Part 3: an evening of Common Ground ─────────────────────────────────────
console.log("Session");
await page.goto(cgEditor + "/sessions");
await live(page);
await page.fill("input[name='session[label]']", "Common Ground — Friday Premiere");
await shot("session-new");
await page.click("button:has-text('Create session')");
await page.waitForURL(/\/console$/);
await live(page);
await shot("console-draft");

const links = await codes([...CG_GROUPS, "projected display"]);
await shot("console-access", page.locator("section:has(h3:has-text('Access'))"));
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
await page.screenshot({ path: `${OUT}/console-pages.png`, clip: { x: 0, y: 0, width: 1440, height: 330 } });
taken.push("console-pages");
await clearPage();

await page.click("button:has-text('Start session')");
await settle(page);
await shot("console-live");

const board = await boardPage(chamberUrl);
await shot("board-waiting", board);

// The warm-up: the Chamber of Commerce decides on its own tablet.
const slogans = consoleElement(page, "Choose your slogan");
await slogans.locator("button:has-text('Trigger')").click();
await settle(page);
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
await shot("console-event-decided", slogans);
await shot("console-board", page.locator("table").first());
await settle(display, 600);
await shot("display-after-slogans", display);

// Asking the room.
await showPage("Happiness Survey", display, "display-page-survey");
const wellbeing = page.locator("section:has(h3:has-text('Well-Being'))");
for (const [score, count] of [[4, 9], [3, 14], [2, 8], [1, 3]]) {
  await wellbeing.locator(`input[name='counts[${score}]']`).fill(String(count));
}
await shot("console-tally-form", wellbeing);
await wellbeing.locator("button:has-text('Record tally')").click();
await settle(page);
await shot("console-tally", wellbeing);
await clearPage();

// Key Event 1, against the clock.
const ke1 = consoleElement(page, "Positive Starting Proposal");
await ke1.locator("button:has-text('Trigger')").click();
await settle(page);
await shot("console-deadline", ke1);
await choose(ke1, [
  "A) Chamber of Commerce - public market",
  "B) Arts & CO",
  "B) Customer's Protections",
  "C) Voluntary Sector",
  "A) Public Services"
]);

// Two versions of Key Event 3: trigger only the one that fits.
const ke3 = page.locator("section").filter({ has: page.locator("h3:has-text('Irresistable Proposal')") });
const ke3High = ke3.filter({ hasText: "High Democracy Score" }).first();
const ke3Low = ke3.filter({ hasText: "Low Democracy Score" }).first();
await ke3High.locator("button:has-text('Trigger')").click();
await settle(page);
await shotSpan("console-shade", [ke3High, ke3Low]);

// The Freeze Card.
const freeze = consoleElement(page, "Freeze Card");
await freeze.locator("button:has-text('Trigger')").click();
await settle(page);
await freeze.locator("[phx-click=adjudicate]:has-text('success')").click();
await settle(page);
await shot("console-wildcard", freeze);

// Referendum 2: the social media policy.
const vote = consoleElement(page, "Referendum 2");
await vote.locator("button:has-text('Trigger')").click();
await settle(page);
await settle(display, 600);
await shot("display-vote", display);
for (const [option, votes] of [
  ["Social Media Policy A - Ban", 9],
  ["Social Media Policy B - Regulate", 21],
  ["Social Media Policy C - Educate", 14]
]) {
  await vote.locator(`div:has(> label:has-text("${option}")) input[name^='tally']`).fill(String(votes));
}
await vote.locator("label:has-text('Social Media Policy B - Regulate') input[type=radio]").check();
await shot("console-vote", vote);
await vote.locator("button:has-text('Declare result')").click();
await settle(page);
await settle(display, 800);
await shot("display-vote-result", display);

// The finale.
await page.click("button:has-text('End')");
await settle(page);
await showPage("Final - Good Ending", display, "display-page-final");

// ── Your Common Ground: a German session, half translated ───────────────────
console.log("German session");
await newSession(cgEditor, "Berlin — Probe", { locale: "de" });
const deLinks = await codes(["Handelskammer"]);
await page.click("button:has-text('Start session')");
await settle(page);
await consoleElement(page, "Wählt euren Slogan").locator("button:has-text('Trigger')").click();
await settle(page);
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
for (const [title, option] of [
  ["What to Bring", "3D printer"],
  ["Touchdown", "Solar field first"]
]) {
  const card = consoleElement(page, title);
  await card.locator("button:has-text('Trigger')").click();
  await settle(page);
  await card.locator(`[phx-click=choose]:has-text("${option}")`).first().click();
  await settle(page);
}
await consoleElement(page, "Settling In").locator("button:has-text('Trigger')").click();
await settle(page);
const marsBoard = await boardPage(marsLinks.find((l) => l.includes("/play/")));
await shot("board-gated-mars", marsBoard);

await browser.close();
console.log(`\n${taken.length} screenshots in ${OUT}`);
