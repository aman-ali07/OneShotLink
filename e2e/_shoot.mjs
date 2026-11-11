import puppeteer from "puppeteer-core";
import fs from "node:fs";
const chrome = "/usr/bin/google-chrome";
const browser = await puppeteer.launch({ executablePath: chrome, args: ["--no-sandbox"] });
const out = {};
for (const [name, w, h] of [["desktop", 1280, 900], ["mobile", 375, 812]]) {
  const page = await browser.newPage();
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
  await page.goto("http://127.0.0.1:8099/", { waitUntil: "networkidle0" });
  const geo = await page.evaluate(() => {
    const de = document.documentElement;
    const cs = (sel, prop) => {
      const el = document.querySelector(sel);
      return el ? getComputedStyle(el)[prop] : null;
    };
    const overflows = [...document.querySelectorAll("body *")]
      .filter((el) => el.getBoundingClientRect().right > de.clientWidth + 1)
      .map((el) => el.tagName + "." + (el.className || "") + " right=" + Math.round(el.getBoundingClientRect().right))
      .slice(0, 6);
    return {
      scrollWidth: de.scrollWidth,
      clientWidth: de.clientWidth,
      scrollHeight: de.scrollHeight,
      h1Width: Math.round(document.querySelector("h1").getBoundingClientRect().width),
      h1Lines: Math.round(document.querySelector("h1").getBoundingClientRect().height / parseFloat(getComputedStyle(document.querySelector("h1")).lineHeight)),
      bodyColor: cs("body", "color"),
      bodyBg: cs("body", "backgroundColor"),
      ledeColor: cs(".lede", "color"),
      buttonBg: cs(".button", "backgroundColor"),
      buttonColor: cs(".button", "color"),
      smallColor: cs(".small", "color"),
      overflows,
    };
  });
  const file = `/home/aman/projects/onetime-secret/replica/screens/site-${name}.png`;
  await page.screenshot({ path: file, fullPage: true });
  out[name] = { geo, file, bytes: fs.statSync(file).size };
  await page.close();
}
await browser.close();
console.log(JSON.stringify(out, null, 2));
