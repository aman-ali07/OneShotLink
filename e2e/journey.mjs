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

  // D-014: a passphrase under 8 bytes must never create a secret, and the
  // server must refuse it even if a client skips the field's own validation.
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#secret");
  await page.type("#secret", "short-pass-guard");
  await page.type("#passphrase", "short");
  const passphraseField = await page.$eval("#passphrase", (element) => ({
    minLength: element.minLength,
    tooShort: element.validity.tooShort,
  }));
  await page.click("button[type=submit]");
  await new Promise((resolve) => setTimeout(resolve, 500));
  const createdWithShortPassphrase = await page.$("#result-heading");
  const shortPassphraseResponse = await page.evaluate(async () => {
    const response = await fetch("/api/v3/guest/conceal", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: "short-pass-direct", ttl: 1800, passphrase: "short" }),
    });
    return { status: response.status, body: await response.json() };
  });

  // File secrets: upload a binary file, reveal once, see the download UI.
  const filePath = "/tmp/opencode/e2e-file.bin";
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
  await page.reload({ waitUntil: "networkidle0" });
  await page.click("form button[type=submit]");
  await page.waitForSelector("#gone-heading", { timeout: 10000 });

  assert(link.includes("/secret/"), "result link is not a /secret/ URL");
  assert(!link.includes(secret), "plaintext leaked into the link");
  assert(revealed === secret, "revealed value did not match");
  assert(storageAfterCreate === "{}", "secret data was written to localStorage");
  assert(guardedRevealed === guarded, "guarded reveal did not match");
  assert(passphraseField.minLength === 8, `passphrase minlength is ${passphraseField.minLength}`);
  assert(passphraseField.tooShort, "a 5-byte passphrase was not flagged as too short");
  assert(createdWithShortPassphrase === null, "a 5-byte passphrase created a secret");
  assert(shortPassphraseResponse.status === 422, "the server accepted a 5-byte passphrase");
  assert(
    shortPassphraseResponse.body?.error?.code === "validation_error",
    "short passphrase was refused with the wrong code"
  );
  assert(/not correct/i.test(wrongMessage), "wrong-passphrase message missing");
  assert(fileLink.includes("/secret/"), "file result link is not a /secret/ URL");
  assert(!fileLink.includes("e2e-file"), "file plaintext leaked into the link");
  assert(fileUi.includes("e2e-file.bin"), "file name missing from the reveal UI");
  assert(fileUi.includes("binary file"), "file size/type line missing");
  assert(errors.length === 0, `browser errors: ${errors.join(" | ")}`);

  console.log(JSON.stringify({ ok: true, link, fileLink, wrongMessage, errors }, null, 2));
} finally {
  await browser.close();
}
