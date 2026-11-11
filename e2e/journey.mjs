import fs from "node:fs";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const executablePath = fs.existsSync(chrome) ? chrome : "/usr/bin/chromium";

if (!fs.existsSync(executablePath)) {
  console.error(`No Chrome/Chromium at ${executablePath}; set CHROME_PATH.`);
  process.exit(1);
}

const secret = `e2e-secret-${Date.now()}`;
const guarded = `e2e-guarded-${Date.now()}`;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const browser = await puppeteer.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(`pageerror:${error.message}`));
  page.on("console", (message) => {
    if (
      message.type() === "error" &&
      !/Failed to load resource: the server responded with a status of (401|404)/.test(message.text())
    ) {
      errors.push(`console:${message.text()}`);
    }
  });

  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#secret");
  await page.type("#secret", secret);
  await page.select("#ttl", "1800");
  await page.click("button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });
  const link = await page.$eval("p.break-all", (element) => element.textContent.trim());
  const storageAfterCreate = await page.evaluate(() => JSON.stringify(localStorage));

  await page.goto(link, { waitUntil: "networkidle0" });
  await page.waitForSelector("#reveal-heading");
  await page.click("form button[type=submit]");
  await page.waitForSelector("#revealed-heading", { timeout: 10000 });
  const revealed = await page.$eval("pre", (element) => element.textContent);

  await page.reload({ waitUntil: "networkidle0" });
  await page.waitForSelector("#reveal-heading");
  await page.click("form button[type=submit]");
  await page.waitForSelector("#gone-heading", { timeout: 10000 });

  // A wrong passphrase must not consume the secret; the correct one must.
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.type("#secret", guarded);
  await page.type("#passphrase", "open-sesame");
  await page.select("#ttl", "1800");
  await page.click("button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });
  const guardedLink = await page.$eval("p.break-all", (element) => element.textContent.trim());

  await page.goto(guardedLink, { waitUntil: "networkidle0" });
  await page.click("form button[type=submit]");
  await page.waitForSelector("#reveal-passphrase", { timeout: 10000 });
  await page.type("#reveal-passphrase", "wrong");
  await page.click("form button[type=submit]");
  await page.waitForSelector("[role=alert]", { timeout: 10000 });
  const wrongMessage = await page.$eval("[role=alert]", (element) => element.textContent.trim());
  await page.$eval("#reveal-passphrase", (element) => {
    element.value = "";
    element.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.type("#reveal-passphrase", "open-sesame");
  await page.click("form button[type=submit]");
  await page.waitForSelector("#revealed-heading", { timeout: 10000 });
  const guardedRevealed = await page.$eval("pre", (element) => element.textContent);

  assert(link.includes("/secret/"), "result link is not a /secret/ URL");
  assert(!link.includes(secret), "plaintext leaked into the link");
  assert(revealed === secret, "revealed value did not match");
  assert(storageAfterCreate === "{}", "secret data was written to localStorage");
  assert(guardedRevealed === guarded, "guarded reveal did not match");
  assert(/not correct/i.test(wrongMessage), "wrong-passphrase message missing");
  assert(errors.length === 0, `browser errors: ${errors.join(" | ")}`);

  console.log(JSON.stringify({ ok: true, link, wrongMessage, errors }, null, 2));
} finally {
  await browser.close();
}
