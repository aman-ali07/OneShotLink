// Automated WCAG 2.2 AA gate. Runs axe-core inside the real browser against
// every static route plus the live reveal/revealed/gone phases. Any violation
// exits non-zero; rules are never excluded to make the gate pass (D-016).
import fs from "node:fs";
import axe from "axe-core";
import puppeteer from "puppeteer-core";

const base = process.env.BASE_URL ?? "http://127.0.0.1:3000";
const executablePath =
  process.env.CHROME_PATH ??
  ["/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"].find((p) => fs.existsSync(p));

if (!executablePath) throw new Error("CHROME_PATH is required (no system Chrome found)");

const TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"];
const VIEWPORTS = [
  { name: "mobile-320", width: 320, height: 720 },
  { name: "mobile-375", width: 375, height: 812 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 900 },
];
const browser = await puppeteer.launch({ executablePath, headless: true, args: ["--no-sandbox"] });
const failures = [];

async function audit(name, url, prepare, viewport = VIEWPORTS[2], dark = false) {
  const page = await browser.newPage();
  const pageErrors = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));
  try {
    await page.setViewport({ width: viewport.width, height: viewport.height });
    // The app honours reduced motion by disabling transitions. Auditing under
    // that media feature prevents an in-flight colour transition from tripping
    // axe's contrast rule on one sample but not the next (a flaky gate is no gate).
    await page.emulateMediaFeatures([
      { name: "prefers-reduced-motion", value: "reduce" },
      { name: "prefers-color-scheme", value: dark ? "dark" : "light" },
    ]);
    // CDP injection runs before page scripts and is not subject to the app's
    // strict CSP; addScriptTag would be blocked by script-src 'self'.
    await page.evaluateOnNewDocument(axe.source);
    await page.goto(url, { waitUntil: "networkidle0" });
    if (prepare) await prepare(page);
    const result = await page.evaluate(
      async (tags) => window.axe.run(document, { runOnly: { type: "tag", values: tags } }),
      TAGS,
    );
    const violations = result.violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      nodes: v.nodes.length,
      help: v.help,
      summary: v.nodes[0]?.failureSummary,
      targets: v.nodes.slice(0, 3).map((n) => n.target.join(" ")),
    }));
    // A one-time secret cannot be shown at several widths, so static routes
    // are audited at each viewport while the dynamic phases stay at desktop.
    const layout = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    }));
    const overflow = layout.scrollWidth > layout.clientWidth + 1;
    const stateName = dark ? `${name}-dark` : name;
    console.log(JSON.stringify({ name: stateName, viewport: viewport.name, url, violations, pageErrors, overflow }));
    if (violations.length) failures.push({ name: `${stateName}@${viewport.name}`, violations });
    // A runtime exception during a state change is a failure even when axe
    // sees no static violation: the state may have silently failed to render.
    if (pageErrors.length) {
      failures.push({
        name: `${stateName}@${viewport.name}`,
        violations: pageErrors.map((message) => ({ id: "page-error", help: message, nodes: 1 })),
      });
    }
    if (overflow) {
      failures.push({
        name: `${stateName}@${viewport.name}`,
        violations: [{ id: "horizontal-overflow", help: "Page overflows the viewport", nodes: 1 }],
      });
    }
  } finally {
    await page.close();
  }
}

try {
  // 1. Static routes. Account routes are audited in their signed-out state,
  //    which is what a default self-hosted instance actually shows.
  for (const [name, route] of [
    ["home", "/"],
    ["signin", "/signin"],
    ["signup", "/signup"],
    ["dashboard-signed-out", "/dashboard"],
    ["not-found", "/no-such-page"],
    ["secret-preview", "/secret/definitely-not-a-real-key-1234"],
    ["request-gone", "/request/definitely-not-a-real-key-1234"],
  ]) {
    for (const viewport of VIEWPORTS) {
      await audit(`${name}`, `${base}${route}`, undefined, viewport);
    }
  }

  // Dark mode is a shipped theme (tokens.css), not a decorative extra: audit
  // it at the narrowest and widest supported widths on the text-heavy routes.
  for (const [name, route] of [
    ["home", "/"],
    ["signup", "/signup"],
    ["dashboard-signed-out", "/dashboard"],
  ]) {
    for (const viewport of [VIEWPORTS[0], VIEWPORTS[3]]) {
      await audit(name, `${base}${route}`, undefined, viewport, true);
    }
  }

  // 2. Dynamic phases on the core journey. Create through the public API so
  //    the gate does not depend on an account or a specific auth mode.
  const response = await fetch(`${base}/api/v3/guest/conceal`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ secret: "a11y-gate-fixture", ttl: 1800 }),
  });
  if (!response.ok) throw new Error(`create for a11y gate failed: ${response.status}`);
  const { secret_key: key } = await response.json();
  const revealUrl = `${base}/secret/${key}`;

  await audit("reveal-idle", revealUrl);
  await audit("reveal-idle", revealUrl, undefined, VIEWPORTS[0], true);
  await audit("reveal-revealed", revealUrl, async (page) => {
    await page.click('button[type="submit"]');
    await page.waitForSelector("#revealed-heading");
  });
  // A never-valid key is detected by the non-consuming preview, so no POST is
  // needed; the terminal panel renders on load.
  await audit("reveal-gone", `${base}/secret/a-key-that-was-never-valid-1234`, async (page) => {
    await page.waitForSelector("#gone-heading");
  });

  // A passphrase-protected secret exercises the passphrase phase.
  const protectedResponse = await fetch(`${base}/api/v3/guest/conceal`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ secret: "a11y-gated-value", ttl: 1800, passphrase: "correct-horse" }),
  });
  if (!protectedResponse.ok) throw new Error(`protected create failed: ${protectedResponse.status}`);
  const protectedKey = (await protectedResponse.json()).secret_key;
  await audit("reveal-passphrase", `${base}/secret/${protectedKey}`, async (page) => {
    await page.click('button[type="submit"]');
    await page.waitForSelector("#reveal-passphrase");
  });
  // The wrong-passphrase error is a distinct accessibility state (live region,
  // focus, alert role) and must be audited too.
  await audit("reveal-passphrase-error", `${base}/secret/${protectedKey}`, async (page) => {
    await page.waitForSelector("#reveal-passphrase");
    await page.type("#reveal-passphrase", "definitely-wrong");
    await page.click('button[type="submit"]');
    await page.waitForSelector("[role=alert]");
  });

  // Negative control: prove the gate is not vacuous. Seed a deliberate
  // image-alt violation, confirm axe reports it, then discard the page.
  {
    const page = await browser.newPage();
    await page.evaluateOnNewDocument(axe.source);
    await page.goto(`${base}/`, { waitUntil: "domcontentloaded" });
    await page.evaluate(() => {
      const img = document.createElement("img");
      img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACw=";
      document.body.appendChild(img);
    });
    const detected = await page.evaluate(async () => {
      const result = await window.axe.run(document, { runOnly: { type: "rule", values: ["image-alt"] } });
      return result.violations.some((v) => v.id === "image-alt");
    });
    console.log(JSON.stringify({ name: "negative-control-image-alt", detected }));
    if (!detected) {
      failures.push({ name: "negative-control-image-alt", violations: [{ id: "gate-is-vacuous", help: "axe did not detect a seeded violation" }] });
    }
    await page.close();
  }

  if (failures.length) {
    console.error(`a11y gate failed: ${failures.length} page(s) with violations`);
    process.exitCode = 1;
  } else {
    console.log("a11y gate passed: 0 WCAG 2.2 AA violations across audited states");
  }
} finally {
  await browser.close();
}
