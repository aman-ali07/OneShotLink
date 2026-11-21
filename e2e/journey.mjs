import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import puppeteer from "puppeteer-core";
import assert from "node:assert/strict";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const executablePath = fs.existsSync(chrome) ? chrome : "/usr/bin/chromium";

if (!fs.existsSync(executablePath)) {
  console.error(`No Chrome/Chromium at ${executablePath}; set CHROME_PATH.`);
  process.exit(1);
}

const secret = `e2e-secret-${Date.now()}`;
const guarded = `e2e-guarded-${Date.now()}`;
const multiByte = `e2e-multibyte-${Date.now()}`;
const multiBytePassphrase = "密钥口"; // 3 code units, 9 UTF-8 bytes (D-014)

let work;
const browser = await puppeteer.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
  const page = await browser.newPage();
  const width = Number(process.env.E2E_WIDTH || 1280);
  await page.setViewport({ width, height: width <= 480 ? 800 : 900 });
  const errors = [];
  page.on("pageerror", (error) => errors.push(`pageerror:${error.message}`));
  page.on("console", (message) => {
    if (
      message.type() === "error" &&
      // 422 is deliberate too: the short-passphrase probe below is refused.
      !/Failed to load resource: the server responded with a status of (401|404|422)/.test(
        message.text()
      )
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
  // The primary hand-off action must work in a real browser (jsdom-only mocks
  // cannot prove the clipboard/fallback path or its role=status feedback).
  await page.evaluate(() => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Copy link");
    if (!button) throw new Error("Copy link button missing");
    button.click();
  });
  await page.waitForFunction(
    () => [...document.querySelectorAll('[role="status"]')].some((e) => /Copied/i.test(e.textContent)),
    { timeout: 5000 },
  );
  const storageAfterCreate = await page.evaluate(() => ({
    local: JSON.stringify(localStorage),
    session: JSON.stringify(sessionStorage),
  }));

  await page.goto(link, { waitUntil: "networkidle0" });
  await page.waitForSelector("#reveal-heading");
  await page.click("form button[type=submit]");
  await page.waitForSelector("#revealed-heading", { timeout: 10000 });
  const revealed = await page.$eval("pre", (element) => element.textContent);
  await page.evaluate(() => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Copy secret");
    if (!button) throw new Error("Copy secret button missing");
    button.click();
  });
  await page.waitForFunction(
    () => [...document.querySelectorAll('[role="status"]')].some((e) => /Copied/i.test(e.textContent)),
    { timeout: 5000 },
  );

  // "Hide secret" must clear the plaintext in place and move focus to the
  // terminal heading — not merely rely on a reload to reach the gone state.
  await page.evaluate(() => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Hide secret");
    if (!button) throw new Error("Hide secret button missing");
    button.click();
  });
  await page.waitForSelector("#gone-heading", { timeout: 10000 });
  const hidden = await page.evaluate(() => ({
    focus: document.activeElement?.id,
    plaintextLeft: document.body.innerText.includes("e2e-secret-"),
    preLeft: document.querySelectorAll("pre").length,
  }));
  assert(hidden.focus === "gone-heading", "focus did not move to the terminal heading");
  assert(!hidden.plaintextLeft, "plaintext remained on screen after Hide secret");
  assert(hidden.preLeft === 0, "secret element remained in the DOM after Hide secret");

  // The non-consuming preview detects a spent link on load, so the terminal
  // panel appears directly — there is no second reveal POST to make.
  await page.reload({ waitUntil: "networkidle0" });
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
  // On a remote host the first reveal request may still be settling here; the
  // submit button is disabled while loading, so a click now would be ignored.
  await page.waitForSelector("form button[type=submit]:not([disabled])", { timeout: 10000 });
  await page.type("#reveal-passphrase", "wrong");
  await page.click("form button[type=submit]");
  await page.waitForSelector("[role=alert]", { timeout: 10000 });
  const wrongMessage = await page.$eval("[role=alert]", (element) => element.textContent.trim());
  const clearedOnRetry = await page.$eval("#reveal-passphrase", (element) => element.value === "");
  await page.waitForSelector("form button[type=submit]:not([disabled])", { timeout: 10000 });
  await page.type("#reveal-passphrase", "open-sesame");
  await page.click("form button[type=submit]");
  await page.waitForSelector("#revealed-heading", { timeout: 10000 });
  const guardedRevealed = await page.$eval("pre", (element) => element.textContent);

  // D-014: a passphrase under 8 bytes must never create a secret, and the
  // server must refuse it even if a client skips the field's own validation.
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#secret");
  await page.type("#secret", "short-pass-guard");
  await page.type("#passphrase", "short");
  await page.click("button[type=submit]");
  await page.waitForSelector('[role="alert"]', { timeout: 5000 });
  const shortPassphraseAlert = await page.$eval('[role="alert"]', (element) => element.textContent.trim());
  const createdWithShortPassphrase = await page.$("#result-heading");
  const shortPassphraseResponse = await page.evaluate(async () => {
    const response = await fetch("/api/v3/guest/conceal", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: "short-pass-direct", ttl: 1800, passphrase: "short" }),
    });
    return { status: response.status, body: await response.json() };
  });

  // D-014 counts UTF-8 bytes, not UTF-16 code units. A native minlength would
  // block this valid 9-byte passphrase before the app's byte rule ever ran.
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#secret");
  await page.type("#secret", multiByte);
  await page.type("#passphrase", multiBytePassphrase);
  await page.select("#ttl", "1800");
  await page.click("button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });
  const multiByteLink = await page.$eval("p.break-all", (element) => element.textContent.trim());
  const storageAfterMultiByteCreate = await page.evaluate(() => ({
    local: JSON.stringify(localStorage),
    session: JSON.stringify(sessionStorage),
  }));

  await page.goto(multiByteLink, { waitUntil: "networkidle0" });
  await page.click("form button[type=submit]");
  await page.waitForSelector("#reveal-passphrase", { timeout: 10000 });
  await page.waitForSelector("form button[type=submit]:not([disabled])", { timeout: 10000 });
  await page.type("#reveal-passphrase", multiBytePassphrase);
  await page.click("form button[type=submit]");
  await page.waitForSelector("#revealed-heading", { timeout: 10000 });
  const multiByteRevealed = await page.$eval("pre", (element) => element.textContent);
  const storageAfterReveal = await page.evaluate(() => ({
    local: JSON.stringify(localStorage),
    session: JSON.stringify(sessionStorage),
  }));

  // File secrets: upload a binary file, reveal once, see the download UI.
  work = fs.mkdtempSync(path.join(os.tmpdir(), "ots-e2e-"));
  const filePath = path.join(work, "e2e-file.bin");
  const fileBytes = Buffer.from([0x00, 0x01, 0xfe, 0xff, 0x41, 0x42]);
  fs.writeFileSync(filePath, fileBytes);
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.evaluate(() => {
    const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "File");
    if (!button) throw new Error("file mode button missing");
    button.click();
  });
  await page.waitForSelector("#file");
  await (await page.$("#file")).uploadFile(filePath);
  await page.waitForFunction(
    () => [...document.querySelectorAll("p")].some((p) => p.textContent.includes("e2e-file.bin")),
    { timeout: 10000 },
  );
  await page.click("form button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });
  const fileLink = await page.$eval("p.break-all", (element) => element.textContent.trim());
  await page.goto(fileLink, { waitUntil: "networkidle0" });
  await page.click("form button[type=submit]");
  await page.waitForFunction(
    () => [...document.querySelectorAll("button")].some((b) => b.textContent.includes("Download file")),
    { timeout: 10000 },
  );
  const fileUi = await page.$eval("main", (element) => element.textContent);
  // Spent links show the terminal panel on load via the preview GET.
  await page.reload({ waitUntil: "networkidle0" });
  await page.waitForSelector("#gone-heading", { timeout: 10000 });

  assert(link.includes("/secret/"), "result link is not a /secret/ URL");
  assert(!link.includes(secret), "plaintext leaked into the link");
  assert(revealed === secret, "revealed value did not match");
  assert(storageAfterCreate.local === "{}", "secret data was written to localStorage");
  assert(storageAfterCreate.session === "{}", "secret data was written to sessionStorage");
  assert(guardedRevealed === guarded, "guarded reveal did not match");
  assert(/8 bytes/i.test(shortPassphraseAlert), `wrong short-passphrase message: ${shortPassphraseAlert}`);
  assert(createdWithShortPassphrase === null, "a 5-byte passphrase created a secret");
  assert(multiByteRevealed === multiByte, "a valid 9-byte passphrase did not reveal the secret");
  assert(
    storageAfterMultiByteCreate.local === "{}" && storageAfterMultiByteCreate.session === "{}",
    "the multi-byte passphrase journey wrote to web storage"
  );
  assert(
    storageAfterReveal.local === "{}" && storageAfterReveal.session === "{}",
    "plaintext was written to web storage on reveal"
  );
  assert(shortPassphraseResponse.status === 422, "the server accepted a 5-byte passphrase");
  assert(
    shortPassphraseResponse.body?.error?.code === "validation_error",
    "short passphrase was refused with the wrong code"
  );
  assert(/not correct/i.test(wrongMessage), "wrong-passphrase message missing");
  assert(clearedOnRetry, "a wrong passphrase was not cleared for a one-type retry");
  assert(fileLink.includes("/secret/"), "file result link is not a /secret/ URL");
  assert(!fileLink.includes("e2e-file"), "file plaintext leaked into the link");
  assert(fileUi.includes("e2e-file.bin"), "file name missing from the reveal UI");
  assert(fileUi.includes("binary file"), "file size/type line missing");
  assert(errors.length === 0, `browser errors: ${errors.join(" | ")}`);

  console.log(JSON.stringify({ ok: true, link, fileLink, wrongMessage, errors }, null, 2));
} finally {
  await browser.close();
  if (work) fs.rmSync(work, { recursive: true, force: true });
}
