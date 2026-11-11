import fs from "node:fs";
import puppeteer from "puppeteer-core";

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

  const storage = await page.evaluate(() => JSON.stringify(localStorage));
  assert(storage === "{}", `localStorage should stay empty, got ${storage}`);
  assert(errors.length === 0, `browser errors: ${errors.join("; ")}`);
  console.log("accounts journey ok");
} finally {
  await browser.close();
}
