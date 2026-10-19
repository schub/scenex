// Shared browser helpers for the tutorial generators (screenshots and video).

export const BASE = process.env.TUTORIAL_BASE_URL || "http://localhost:4100";
export const EMAIL = process.env.TUTORIAL_EMAIL || "director@scenex.example";
export const PASSWORD = process.env.TUTORIAL_PASSWORD || "common-ground-2026";

// Every page the tutorial shows is a LiveView; act only once it is connected,
// otherwise input typed before the socket joins is silently lost.
export async function live(page) {
  await page.waitForLoadState("networkidle");
  await page.waitForSelector(".phx-connected", { timeout: 15000 });
}

// LiveView patches the DOM asynchronously after a click.
export async function settle(page, ms = 400) {
  await page.waitForTimeout(ms);
  await page.waitForLoadState("networkidle");
}

export async function login(page) {
  await page.goto(BASE + "/users/log-in");
  await live(page);
  await page.fill("#login_form_password input[type=email]", EMAIL);
  await page.fill("#login_form_password input[type=password]", PASSWORD);
  await page.click("#login_form_password button:has-text('Log in only this time')");
  await page.waitForURL((u) => !u.pathname.includes("log-in"));
}

// Opens a scenario's editor from the list, by its handle as listed there.
export async function openEditor(page, handle) {
  await page.goto(BASE + "/scenarios");
  await live(page);
  // The "Open editor" link in the card whose title is exactly this handle.
  const href = await page.evaluate((h) => {
    const title = [...document.querySelectorAll("*")].find(
      (el) => el.children.length === 0 && el.textContent.trim() === h
    );
    let card = title?.parentElement;
    while (card && ![...card.querySelectorAll("a")].some((a) => a.textContent.includes("Open editor"))) {
      card = card.parentElement;
    }
    return [...card.querySelectorAll("a")].find((a) => a.textContent.includes("Open editor")).href;
  }, handle);
  await page.goto(href);
  await page.waitForURL(/\/scenarios\/[0-9a-f-]+$/);
  await live(page);
  return page.url();
}

export async function tab(page, section) {
  await page.click(`[role=tab][phx-value-section=${section}]`);
  await settle(page);
}

// A list entry in one of the editor's left-hand menus, by its handle.
export async function pick(page, event, handle) {
  await page.click(`[phx-click=${event}]:has-text("${handle}")`);
  await settle(page);
}

// The Edit button of one option row in the opened timeline element.
export async function editOption(page, handle) {
  await page.locator(`li:has-text("${handle}") [phx-click=edit_option]`).first().click();
  await settle(page);
}

// A timeline element's card in the GM console.
export function consoleElement(page, title) {
  return page.locator("section").filter({ has: page.locator(`h3:has-text("${title}")`) }).first();
}

// Chromium on macOS formats <input type="number"> by the system region (and no
// launch flag or locale overrides it), so a German Mac shows "8,0" in an
// English tutorial. For screenshots and the video only, number fields become
// text fields, which show the value exactly as the server renders it ("8.0").
// LiveView may patch the type back, hence the observer.
export function numbersAsText() {
  const convert = (root) =>
    root.querySelectorAll?.('input[type="number"]').forEach((input) => {
      input.type = "text";
    });
  new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.type === "attributes" && m.target.matches?.('input[type="number"]')) m.target.type = "text";
      m.addedNodes.forEach((n) => n.nodeType === 1 && (n.matches('input[type="number"]') ? (n.type = "text") : convert(n)));
    }
  }).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["type"] });
  document.addEventListener("DOMContentLoaded", () => convert(document));
}

export async function newContext(browser, extra = {}) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    locale: "en-US",
    colorScheme: "light",
    ...extra
  });
  await context.addInitScript(numbersAsText);
  // The console asks for confirmation before start/end/close.
  context.on("page", (p) => p.on("dialog", (d) => d.accept()));
  return context;
}
