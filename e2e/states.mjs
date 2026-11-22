// Cross-viewport journey for the states that were previously unproven in the
// browser: non-consuming preview, one-time reveal, uniform gone, invalid key,
// owner burn (destroyed) and already-viewed receipt status.
import fs from "node:fs";
import puppeteer from "puppeteer-core";
import assert from "node:assert/strict";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const executablePath = fs.existsSync(chrome) ? chrome : "/usr/bin/chromium";
if (!fs.existsSync(executablePath)) throw new Error("CHROME_PATH is required");

const VIEWPORTS = [
  { name: "desktop", width: 1280, height: 900 },
  { name: "mobile", width: 375, height: 812 },
];

const browser = await puppeteer.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});
const results = [];

try {
  for (const viewport of VIEWPORTS) {
    const page = await browser.newPage();
    await page.setViewport({ width: viewport.width, height: viewport.height });
    const errors = [];
    page.on("pageerror", (error) => errors.push(`pageerror:${error.message}`));
    page.on("console", (message) => {
      if (
        message.type() === "error" &&
        !/status of (401|404|422)/.test(message.text())
      ) errors.push(`console:${message.text()}`);
    });
    page.on("dialog", (dialog) => dialog.accept());

    const stamp = `${Date.now()}-${viewport.name}`;
    const secret = `states-${stamp}`;

    // Create through the real UI.
    await page.goto(`${base}/`, { waitUntil: "networkidle0" });
    await page.type("#secret", secret);
    await page.select("#ttl", "1800");
    await page.click("button[type=submit]");
    await page.waitForSelector("#result-heading", { timeout: 10000 });
    const link = await page.$eval("p.break-all", (el) => el.textContent.trim());

    // Preview must not consume: metadata is visible before any POST, and a
    // second visit still offers the reveal form.
    await page.goto(link, { waitUntil: "networkidle0" });
    await page.waitForSelector("#reveal-heading");
    const preReveal = await page.evaluate(() => document.body.innerText);
    assert(preReveal.includes("Text secret"), `${viewport.name}: preview metadata missing`);
    assert(!preReveal.includes(secret), `${viewport.name}: preview leaked plaintext`);
    await page.goto(link, { waitUntil: "networkidle0" });
    await page.waitForSelector("#reveal-heading");

    // Reveal once, then the terminal gone state on replay.
    await page.click('form button[type="submit"]');
    await page.waitForSelector("#revealed-heading", { timeout: 10000 });
    const revealed = await page.$eval("pre", (el) => el.textContent);
    assert(revealed === secret, `${viewport.name}: revealed value mismatch`);
    await page.reload({ waitUntil: "networkidle0" });
    await page.waitForSelector("#gone-heading", { timeout: 10000 });

    // Invalid key is a distinct state from a consumed one.
    await page.goto(`${base}/#/secret/${"x".repeat(180)}`, { waitUntil: "networkidle0" });
    await page.waitForSelector("#invalid-heading", { timeout: 10000 });

    // Owner burn: create a signed-in secret, then destroy it from the dashboard.
    const email = `states-${stamp}@example.com`;
    const password = "e2e correct horse battery";
    await page.goto(`${base}/#/signup`, { waitUntil: "networkidle0" });
    await page.type("#email", email);
    await page.type("#password", password);
    await page.type("#confirmation", password);
    await page.click("button[type=submit]");
    await page.waitForFunction(() => location.hash === "#/dashboard", { timeout: 10000 });

    const guarded = `burn-${stamp}`;
    await page.goto(`${base}/`, { waitUntil: "networkidle0" });
    await page.type("#secret", guarded);
    await page.select("#ttl", "1800");
    await page.click("button[type=submit]");
    await page.waitForSelector("#result-heading", { timeout: 10000 });
    const burnLink = await page.$eval("p.break-all", (el) => el.textContent.trim());

    await page.goto(`${base}/#/dashboard`, { waitUntil: "networkidle0" });
    await page.waitForFunction(() => document.body.innerText.includes("Destroy now"), { timeout: 10000 });
    const destroyButtons = await page.$$("button");
    for (const button of destroyButtons) {
      const text = await button.evaluate((el) => el.textContent || "");
      if (text.includes("Destroy now")) {
        await button.click();
        break;
      }
    }
    await page.waitForFunction(() => document.body.innerText.includes("Destroyed by you"), { timeout: 10000 });

    // The burned link is already terminal: the non-consuming preview detects
    // the missing object and renders "gone" without any reveal POST.
    await page.goto(burnLink, { waitUntil: "networkidle0" });
    await page.waitForSelector("#gone-heading", { timeout: 10000 });

    // Already-viewed: an owner-created secret that was revealed must be labelled
    // as such on the dashboard, with no plaintext retained.
    const viewed = `viewed-${stamp}`;
    await page.goto(`${base}/`, { waitUntil: "networkidle0" });
    await page.type("#secret", viewed);
    await page.select("#ttl", "1800");
    await page.click("button[type=submit]");
    await page.waitForSelector("#result-heading", { timeout: 10000 });
    const viewedLink = await page.$eval("p.break-all", (el) => el.textContent.trim());
    await page.goto(viewedLink, { waitUntil: "networkidle0" });
    await page.click('form button[type="submit"]');
    await page.waitForSelector("#revealed-heading", { timeout: 10000 });
    await page.goto(`${base}/#/dashboard`, { waitUntil: "networkidle0" });
    await page.waitForFunction(() => document.body.innerText.includes("Already viewed — destroyed"), { timeout: 10000 });
    const dashboardText = await page.evaluate(() => document.body.innerText);
    assert(!dashboardText.includes(viewed), `${viewport.name}: dashboard retained revealed plaintext`);

    assert(errors.length === 0, `${viewport.name}: browser errors ${errors.join(" | ")}`);
    results.push({ viewport: viewport.name, preview: "no-consume", reveal: "once", burn: "destroyed", errors: 0 });
    await page.close();
  }

  console.log(JSON.stringify({ ok: true, results }, null, 2));
} finally {
  await browser.close();
}
