import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const email = `e2e-request-${Date.now()}@example.com`;
const password = "e2e correct horse request";
const secret = `request-answer-${Date.now()}`;

const browser = await puppeteer.launch({
  executablePath: "/usr/bin/google-chrome",
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

const clickButton = async (page, text) => {
  const clicked = await page.evaluate((label) => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === label);
    if (!button) return false;
    button.click();
    return true;
  }, text);
  assert(clicked, `button not found: ${text}`);
};

try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(`pageerror:${e.message}`));
  page.on("console", (m) => {
    if (m.type() === "error" && !/status of (401|403|404|409|422)/.test(m.text())) errors.push(`console:${m.text()}`);
  });

  await page.goto(`${base}/signup`, { waitUntil: "networkidle0" });
  await page.type("#email", email);
  await page.type("#password", password);
  await page.type("#confirmation", password);
  await page.click("button[type=submit]");
  await page.waitForFunction(() => location.pathname === "/dashboard", { timeout: 10000 });

  await page.waitForSelector("#request-label");
  await page.type("#request-label", "API key please");
  await clickButton(page, "Create link");
  await page.waitForFunction(
    () => document.body.textContent.includes("API key please"),
    { timeout: 10000 },
  );

  const key = await page.evaluate(async () => {
    const res = await fetch("/api/v3/requests", { credentials: "same-origin" });
    const body = await res.json();
    return body.requests[0].request_key;
  });
  assert(key, "request key missing from API");

  await page.goto(`${base}/request/${key}`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#request-secret");
  const previewText = await page.$eval("main", (el) => el.textContent);
  assert(previewText.includes("API key please"), "label missing from responder view");
  await page.type("#request-secret", secret);
  await page.click("button[type=submit]");
  await page.waitForSelector("#request-sent-heading", { timeout: 10000 });

  await page.goto(`${base}/dashboard`, { waitUntil: "networkidle0" });
  await page.waitForFunction(() => document.body.textContent.includes("Answer received"), { timeout: 10000 });
  await clickButton(page, "Reveal answer");
  try {
    await page.waitForFunction((value) => document.body.textContent.includes(value), { timeout: 10000 }, secret);
  } catch (cause) {
    console.error("DEBUG_MAIN=" + (await page.$eval("main", (el) => el.textContent)));
    console.error("DEBUG_ERRORS=" + JSON.stringify(errors));
    throw cause;
  }

  const storage = await page.evaluate(() => JSON.stringify(localStorage));
  assert.equal(storage, "{}", "localStorage should stay empty");
  assert.deepEqual(errors, [], `browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, key, secret, errors }, null, 2));
} finally {
  await browser.close();
}
