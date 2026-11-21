import fs from "node:fs";
import puppeteer from "puppeteer-core";
import assert from "node:assert/strict";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const executablePath = fs.existsSync(chrome) ? chrome : "/usr/bin/chromium";

if (!fs.existsSync(executablePath)) {
  console.error(`No Chrome/Chromium at ${executablePath}; set CHROME_PATH.`);
  process.exit(1);
}

const email = `e2e-${Date.now()}@example.com`;
const password = "e2e correct horse battery";
const secret = `account-secret-${Date.now()}`;

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
      !/Failed to load resource: the server responded with a status of (401|404)/.test(message.text())
    ) {
      errors.push(`console:${message.text()}`);
    }
  });

  await page.goto(`${base}/signup`, { waitUntil: "networkidle0" });
  await page.type("#email", email);
  await page.type("#password", password);
  await page.type("#confirmation", password);
  await page.click("button[type=submit]");
  await page.waitForFunction(() => location.pathname === "/dashboard", { timeout: 10000 });
  await page.waitForSelector("h1");
  assert((await page.$eval("h1", (el) => el.textContent)).includes("Your account"), "dashboard did not load after signup");

  // An authenticated conceal creates an owner receipt.
  await page.goto(`${base}/`, { waitUntil: "networkidle0" });
  await page.type("#secret", secret);
  await page.select("#ttl", "1800");
  await page.click("button[type=submit]");
  await page.waitForSelector("#result-heading", { timeout: 10000 });

  await page.goto(`${base}/dashboard`, { waitUntil: "networkidle0" });
  await page.waitForSelector("#receipts-heading");
  const dashboardText = await page.$eval("main", (el) => el.textContent);
  assert(/Expires in/.test(dashboardText), "receipt did not appear on the dashboard");
  assert(!dashboardText.includes(secret), "dashboard leaked the secret plaintext");

  await page.reload({ waitUntil: "networkidle0" });
  await page.waitForSelector("#receipts-heading");

  const signOut = await page.$$("button");
  const signOutButton = await Promise.all(
    signOut.map(async (button) => ({ button, text: await button.evaluate((el) => el.textContent.trim()) })),
  ).then((items) => items.find((item) => item.text === "Sign out")?.button);
  assert(signOutButton, "sign out button not found");
  await signOutButton.click();
  await page.waitForFunction(() => location.pathname === "/", { timeout: 10000 });

  await page.goto(`${base}/dashboard`, { waitUntil: "networkidle0" });
  await page.waitForSelector("h1");
  assert((await page.$eval("main", (el) => el.textContent)).includes("Sign in"), "signed-out dashboard did not prompt");

  await page.goto(`${base}/signin`, { waitUntil: "networkidle0" });
  await page.type("#email", email);
  await page.type("#password", password);
  await page.click("button[type=submit]");
  await page.waitForFunction(() => location.pathname === "/dashboard", { timeout: 10000 });
  await page.waitForSelector("#receipts-heading");

  const storage = await page.evaluate(() => ({
    local: JSON.stringify(localStorage),
    session: JSON.stringify(sessionStorage),
  }));
  assert(storage.local === "{}", `localStorage should stay empty, got ${storage.local}`);
  assert(storage.session === "{}", `sessionStorage should stay empty, got ${storage.session}`);

  // Account deletion is the last step: it ends the session for good.
  await page.waitForSelector("#delete-password");
  await page.type("#delete-password", password);
  const deleteButton = await page
    .$$("button")
    .then(async (buttons) =>
      Promise.all(
        buttons.map(async (button) => ({ button, text: await button.evaluate((el) => el.textContent.trim()) })),
      ),
    )
    .then((items) => items.find((item) => item.text === "Delete my account")?.button);
  assert(deleteButton, "delete account button not found");
  // Two-step confirmation: the first click only arms deletion.
  await deleteButton.click();
  await page.waitForFunction(
    () => [...document.querySelectorAll("button")].some((b) => b.textContent.includes("Confirm deletion")),
    { timeout: 10000 },
  );
  await deleteButton.click();
  await page.waitForFunction(() => location.pathname === "/", { timeout: 10000 });

  const meStatus = await page.evaluate(async () => (await fetch("/api/v3/account/me")).status);
  assert(meStatus === 401, `deleted account still resolves, me returned ${meStatus}`);

  await page.goto(`${base}/signin`, { waitUntil: "networkidle0" });
  await page.type("#email", email);
  await page.type("#password", password);
  await page.click("button[type=submit]");
  // `<main>` lives in the App shell, so waiting for it resolves before the
  // async sign-in finishes. Wait for the rejected-credentials alert instead.
  await page.waitForSelector("#signin-error", { timeout: 10000 });
  assert(
    (await page.evaluate(() => location.pathname)) === "/signin",
    "signed in after the account was deleted",
  );

  // MIN_PASSWORD_BYTES is 12: a 6-character CJK password is 18 UTF-8 bytes and
  // must be accepted, even though a native minlength would count only 6.
  const cjkEmail = `e2e-cjk-${Date.now()}@example.com`;
  const cjkPassword = "密码口令测试";
  await page.goto(`${base}/signup`, { waitUntil: "networkidle0" });
  await page.type("#email", cjkEmail);
  await page.type("#password", cjkPassword);
  await page.type("#confirmation", cjkPassword);
  await page.click("button[type=submit]");
  await page.waitForFunction(() => location.pathname === "/dashboard", { timeout: 10000 });

  assert(errors.length === 0, `browser errors: ${errors.join("; ")}`);
  console.log("accounts journey ok");
} finally {
  await browser.close();
}
