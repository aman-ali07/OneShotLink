import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const work = fs.mkdtempSync(path.join(os.tmpdir(), "ots-file-e2e-"));
const file = path.join(work, "fixture.bin");
const downloads = path.join(work, "downloads");
const bytes = Buffer.from([0x00, 0x01, 0x7f, 0x80, 0xff, 0x41, 0x42, 0x43]);
fs.writeFileSync(file, bytes);
fs.mkdirSync(downloads);

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
    if (m.type() === "error" && !/status of (401|403|404|422)/.test(m.text())) errors.push(`console:${m.text()}`);
  });

  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#compose-heading");
  const fileToggle = await page.$$("button");
  for (const button of fileToggle) {
    if ((await button.evaluate((el) => el.textContent.trim())) === "File") {
      await button.click();
      break;
    }
  }
  await page.waitForSelector('input[type="file"]');
  const input = await page.$('input[type="file"]');
  await input.uploadFile(file);
  await page.click("button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });
  const link = await page.$eval("p.break-all", (el) => el.textContent.trim());
  assert(link.includes("/secret/"), "no one-time link for the file");

  const recipientContext = await browser.createBrowserContext();
  const recipient = await recipientContext.newPage();
  recipient.on("pageerror", (e) => errors.push(`recipient:${e.message}`));
  const client = await recipient.createCDPSession();
  await client.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: downloads });
  await recipient.goto(link, { waitUntil: "networkidle0" });
  await recipient.click("form button[type=submit]");
  await recipient.waitForSelector("#revealed-heading", { timeout: 10000 });
  await recipient.waitForSelector("#file-name");
  assert.equal(await recipient.$eval("#file-name", (el) => el.textContent.trim()), "fixture.bin");
  const downloadButton = await recipient.$$("button");
  for (const button of downloadButton) {
    if ((await button.evaluate((el) => el.textContent.trim())) === "Download file") {
      await button.click();
      break;
    }
  }

  let downloaded = null;
  for (let i = 0; i < 40; i += 1) {
    const found = fs.readdirSync(downloads).find((name) => name.endsWith(".bin"));
    if (found && !found.endsWith(".crdownload")) {
      downloaded = path.join(downloads, found);
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert(downloaded, "the file was never downloaded");
  assert.deepEqual(fs.readFileSync(downloaded), bytes, "downloaded bytes differ from the fixture");

  // Spent links show the terminal panel on load via the preview GET. Measure
  // that preview's status instead of logging a hard-coded "404".
  await recipient.goto(link, { waitUntil: "networkidle0" });
  await recipient.waitForSelector("#gone-heading", { timeout: 10000 });
  const replayStatus = await recipient.evaluate(async (url) => {
    const key = url.split("/secret/")[1].split(/[?#]/)[0];
    const response = await fetch(`/api/v3/guest/secret/${encodeURIComponent(key)}`);
    return response.status;
  }, link);
  assert.equal(replayStatus, 404, `replay preview returned ${replayStatus}`);
  assert.deepEqual(errors, [], `browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, filename: "fixture.bin", bytes: bytes.length, replay: replayStatus, errors }));
} finally {
  await browser.close();
  fs.rmSync(work, { recursive: true, force: true });
}
