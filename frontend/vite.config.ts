import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";

// Dev: Vite proxies the API to the Rack app so the browser sees one origin.
// Prod: the build lands in ../public/app, which Roda serves with an SPA fallback.
export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  server: {
    port: 5173,
    fs: {
      // Only the one CSS dependency outside frontend/ needs to be reachable.
      // `allow: [".."]` exposed the whole repository root (including the
      // git-ignored .env with SECRET) through the dev server's /@fs/ route.
      allow: [
        fileURLToPath(new URL(".", import.meta.url)),
        fileURLToPath(new URL("../replica/design", import.meta.url)),
        // Read-only marketing page for the CTA-origin regression test. Site is
        // a static, non-secret directory; .env and the git root stay excluded.
        fileURLToPath(new URL("../site", import.meta.url)),
      ],
    },
    proxy: {
      "/api": {
        target: process.env.VITE_API_PROXY ?? "http://127.0.0.1:3100",
        changeOrigin: false,
      },
      "/health": {
        target: process.env.VITE_API_PROXY ?? "http://127.0.0.1:3100",
        changeOrigin: false,
      },
    },
  },
  build: {
    outDir: "../public/app",
    emptyOutDir: true,
    sourcemap: false,
  },
  // Component tests mount real SFCs; the API-client tests need no DOM but are
  // harmless under jsdom. Layout/contrast still needs the live axe gate.
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.ts"],
  },
});
