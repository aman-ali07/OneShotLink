// Complete journeys at phone widths. The a11y gate audits static routes at
// 320/768/1280 but exercises reveal phases at desktop only; this script drives
// the real create -> reveal -> gone, passphrase, account and request-responder
// flows at 375px and 320px, and asserts the static pages' skip links.
import assert from "node:assert/strict";
import fs from "node:fs";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL ?? "http://127.0.0.1:3000";
const executablePath =
  process.env.CHROME_PATH ??
  ["/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"].find((p) => fs.existsSync(p));
if (!executablePath) throw new Error("CHROME_PATH is required (no system Chrome found)");

const browser = await puppeteer.launch({ executablePath, headless: true, args: ["--no-sandbox"] });
const errors = [];
const results = [];

async function newPage(width, height = 812) {
  const page = await browser.newPage();
  page.on("pageerror", (error) => errors.push(`pageerror:${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error" && !/status of (401|404)/.test(message.text())) {
      errors.push(`console:${message.text()}`);
    }
  });
  await page.setViewport({ width, height, deviceScaleFactor: 1 });
  return page;
}

async function noOverflow(page, label) {
  const layout = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  assert(layout.scroll <= layout.client + 1, `${label}: horizontal overflow ${layout.scroll}>${layout.client}`);
  results.push({ label, width: layout.client, overflow: false });
}

async function targetsAtLeast44(page, label, selector) {
  const heights = await page.$$eval(selector, (els) => els.map((el) => Math.round(el.getBoundingClientRect().height)));
  assert(heights.length > 0, `${label}: no controls matched ${selector}`);
  // A 0px control is not "not measured" — it is a collapsed, untappable target.
  const tooSmall = heights.filter((h) => h < 44);
  assert.deepEqual(tooSmall, [], `${label}: controls under 44px: ${tooSmall.join(",")}`);
}

try {
  // 1. Core secret lifecycle at 375px, then replay at 320px.
  for (const width of [375, 320]) {
    const page = await newPage(width);
    await page.goto(`${base}/`, { waitUntil: "networkidle0" });
    await noOverflow(page, `home-${width}`);
    await targetsAtLeast44(page, `home-${width}`, "main button");
    const secret = `mobile-${width}-${Date.now()}`;
    await page.type("#secret", secret);
    await page.click("form button[type=submit]");
    await page.waitForSelector("#result-heading", { timeout: 10000 });
    await noOverflow(page, `result-${width}`);
    await targetsAtLeast44(page, `result-${width}`, "main button");

    const link = await page.$eval("p.break-all", (el) => el.textContent.trim());
    await page.goto(link, { waitUntil: "networkidle0" });
    await noOverflow(page, `reveal-idle-${width}`);
    await targetsAtLeast44(page, `reveal-idle-${width}`, "main button");
    await page.click("form button[type=submit]");
    await page.waitForSelector("#revealed-heading", { timeout: 10000 });
    const revealed = await page.$eval("pre", (el) => el.textContent);
    assert.equal(revealed, secret, `reveal-${width}: plaintext mismatch`);
    await noOverflow(page, `revealed-${width}`);
    await targetsAtLeast44(page, `revealed-${width}`, "main button");

    // Spent links show the terminal panel on load via the non-consuming GET.
    await page.goto(link, { waitUntil: "networkidle0" });
    await page.waitForSelector("#gone-heading", { timeout: 10000 });
    await noOverflow(page, `gone-${width}`);
    await page.close();
    results.push({ label: `secret-lifecycle-${width}`, ok: true });
  }

  // 2. Passphrase path at 375px: the field appears before any POST, a wrong
  //    value is cleared for one-type retry, and the right value reveals.
  {
    const page = await newPage(375);
    await page.goto(`${base}/`, { waitUntil: "networkidle0" });
    const guarded = `guarded-${Date.now()}`;
    await page.type("#secret", guarded);
    await page.type("#passphrase", "open-sesame");
    await page.click("form button[type=submit]");
    await page.waitForSelector("#result-heading", { timeout: 10000 });
    const link = await page.$eval("p.break-all", (el) => el.textContent.trim());
    await page.goto(link, { waitUntil: "networkidle0" });
    await page.waitForSelector("#reveal-passphrase", { timeout: 10000 });
    await noOverflow(page, "passphrase-prompt-375");
    await page.type("#reveal-passphrase", "wrong");
    await page.click("form button[type=submit]");
    await page.waitForSelector("[role=alert]", { timeout: 10000 });
    assert.equal(await page.$eval("#reveal-passphrase", (el) => el.value), "", "wrong passphrase not cleared");
    await page.type("#reveal-passphrase", "open-sesame");
    await page.click("form button[type=submit]");
    await page.waitForSelector("#revealed-heading", { timeout: 10000 });
    assert.equal(await page.$eval("pre", (el) => el.textContent), guarded, "guarded reveal mismatch");
    await page.close();
    results.push({ label: "passphrase-lifecycle-375", ok: true });
  }

  // 3. Account + request responder at 375px.
  {
    const page = await newPage(375);
    const stamp = Date.now();
    const email = `mobile-${stamp}@example.test`;
    const password = "mobile-passphrase-123";
    await page.goto(`${base}/signup`, { waitUntil: "networkidle0" });
    await noOverflow(page, "signup-375");
    await page.type("#email", email);
    await page.type("#password", password);
    await page.type("#confirmation", password);
    await page.click("button[type=submit]");
    await page.waitForFunction(() => location.pathname === "/dashboard", { timeout: 15000 });
    await page.waitForSelector("#receipts-heading", { timeout: 10000 });
    await noOverflow(page, "dashboard-375");

    await page.waitForSelector("#request-label", { timeout: 10000 });
    await page.type("#request-label", "Mobile API key");
    await page.evaluate(() =>
      [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Create link")?.click(),
    );
    await page.waitForFunction(() => document.body.textContent.includes("Mobile API key"), { timeout: 10000 });
    const key = await page.evaluate(async () => {
      const res = await fetch("/api/v3/requests", { credentials: "same-origin" });
      const body = await res.json();
      return body.requests[0].request_key;
    });
    assert(key, "request key missing from API");

    await page.goto(`${base}/request/${key}`, { waitUntil: "networkidle0" });
    await page.waitForSelector("#request-secret", { timeout: 10000 });
    await noOverflow(page, "responder-ready-375");
    await page.type("#request-secret", `mobile-answer-${stamp}`);
    await page.click("form button[type=submit]");
    await page.waitForSelector("#request-sent-heading", { timeout: 10000 });
    await noOverflow(page, "responder-sent-375");
    await page.close();
    results.push({ label: "account-request-responder-375", ok: true });
  }

  // 4. Static pages: served over HTTP (the pages use root-relative /styles.css,
  //    so file:// would test an unstyled page). Skip link is the first tab stop
  //    and moves focus to <main> (WCAG 2.4.1).
  {
    // Default to the SPA itself (which also has a skip link) so the gate has
    // no hidden dependency on a separate static-site port.
    const site = process.env.SITE_URL ?? base;
    const page = await newPage(320);
    await page.goto(`${site}/`, { waitUntil: "networkidle0" });
    // The router moves focus to <main> after navigation, so Tab would start
    // after the skip link. Reset focus to the document first.
    await page.evaluate(() => {
      document.body.setAttribute("tabindex", "-1");
      document.body.focus();
    });
    await page.keyboard.press("Tab");
    const focused = await page.evaluate(() => ({
      text: document.activeElement?.textContent?.trim(),
      cls: document.activeElement?.className,
    }));
    assert.equal(focused.text, "Skip to content", `skip link not first tab stop: ${JSON.stringify(focused)}`);
    await page.keyboard.press("Enter");
    const after = await page.evaluate(() => ({
      hash: location.hash,
      id: document.activeElement?.id,
      scroll: document.documentElement.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    assert.equal(after.hash, "#main", "skip link did not set #main");
    assert.equal(after.id, "main", "skip link did not focus <main>");
    assert(after.scroll <= after.client + 1, "static site overflows at 320px");
    await page.close();
    results.push({ label: "static-skip-link-320", ok: true });
  }

  assert.deepEqual(errors, [], `browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, checked: results.length, results, errors }, null, 2));
} finally {
  await browser.close();
}
