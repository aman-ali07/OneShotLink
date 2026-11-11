import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
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
      // replica/design/tokens.css is imported from outside frontend/.
      allow: [".."],
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
});
