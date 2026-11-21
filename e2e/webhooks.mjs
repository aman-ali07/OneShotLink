import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const email = `e2e-hook-${Date.now()}@example.com`;
const password = "e2e correct horse hooks";
const url = "https://example.com/oneshotlink-hook";

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/google-chrome",
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

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

  await page.waitForSelector("#hook-url");
  await page.type("#hook-url", url);
  await page.$eval("#hook-url", (el) => el.closest("form").querySelector("button[type=submit]").click());
  try {
    await page.waitForFunction(
      () => document.body.textContent.includes("Copy this signing secret now"),
      { timeout: 10000 },
    );
  } catch (cause) {
    throw cause;
  }
  const secret = await page.$eval(".ots-inset .break-all", (el) => el.textContent.trim());
  assert.match(secret, /^[0-9a-f]{64}$/, "signing secret was not shown once");

  await page.waitForFunction((value) => document.body.textContent.includes(value), { timeout: 10000 }, url);
  const me = await page.evaluate(async () => {
    const res = await fetch("/api/v3/webhooks", { credentials: "same-origin" });
    const body = await res.json();
    return { count: body.webhooks.length, hasSecret: JSON.stringify(body).includes("signing_secret") };
  });
  assert.equal(me.count, 1, "endpoint was not listed by the API");
  assert.equal(me.hasSecret, false, "listing leaked the signing secret");

  // Creating a secret emits secret.created for the subscribed endpoint; the
  // deliveries panel must show it, proving the event path end to end.
  await page.evaluate(async () => {
    const res = await fetch("/api/v3/guest/conceal", {
      method: "POST", credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ secret: "webhook-fixture", ttl: 1800 }),
    });
    if (!res.ok) throw new Error(`conceal failed: ${res.status}`);
  });
  await page.evaluate(() => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.includes("View deliveries"));
    if (!button) throw new Error("View deliveries button missing");
    button.click();
  });
  await page.waitForFunction(
    () => document.body.textContent.includes("secret.created"),
    { timeout: 10000 },
  );

  const storage = await page.evaluate(() => JSON.stringify(localStorage));
  assert.equal(storage, "{}", "localStorage should stay empty");
  assert.deepEqual(errors, [], `browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, endpoint: url, errors }, null, 2));
} finally {
  await browser.close();
}
