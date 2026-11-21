import { describe, expect, it } from "vitest";
import siteHtml from "../../../site/index.html?raw";

const META = '<meta name="ots-app-url" content="" />';

/**
 * Run the marketing page's inline CTA script against a detached document with
 * a hostile (or valid) deploy-time meta value, using the jsdom environment
 * Vitest already provides. No Node APIs and no extra dependencies.
 */
function ctaHref(appUrl: string): string {
  expect(siteHtml).toContain(META);
  const html = siteHtml.replace(META, `<meta name="ots-app-url" content="${appUrl}" />`);
  const doc = document.implementation.createHTMLDocument("site");
  doc.open();
  doc.write(html);
  doc.close();
  const script = doc.querySelector("script:not([src])")?.textContent ?? "";
  expect(script).not.toBe("");
  new Function("document", script)(doc);
  return doc.getElementById("create-cta")?.getAttribute("href") ?? "";
}

describe("marketing site CTA origin", () => {
  it("uses an http(s) app origin when configured", () => {
    expect(ctaHref("https://app.example/")).toBe("https://app.example/");
  });

  it("keeps the same-origin default when unset", () => {
    expect(ctaHref("")).toBe("/");
  });

  it("ignores a javascript: or relative value instead of assigning it to href", () => {
    expect(ctaHref("javascript:alert(document.domain)//")).toBe("/");
    expect(ctaHref("//attacker.example")).toBe("/");
    expect(ctaHref("/local-path")).toBe("/");
  });
});
