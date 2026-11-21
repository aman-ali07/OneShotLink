// OneShotLink guest flow with Node 24's built-in fetch. No npm packages.
// Usage: BASE_URL=http://127.0.0.1:3000 node examples/typescript/quickstart.mjs
import assert from "node:assert/strict";

const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const secretValue = `ts-example-${Date.now()}`;

async function api(path, { method = "GET", body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json();
  return { status: response.status, data };
}

// The operator may narrow TTL_OPTIONS; use the advertised default.
const config = await api("/api/v3/config");
assert.equal(config.status, 200);
const created = await api("/api/v3/guest/conceal", {
  method: "POST",
  body: { secret: secretValue, ttl: config.data.default_ttl },
});
assert.equal(created.status, 201);
const key = created.data.secret_key;
assert.ok(key);

// GET describes; it never spends the secret and never carries its value.
const preview = await api(`/api/v3/guest/secret/${key}`);
assert.equal(preview.status, 200);
assert.equal(preview.data.secret_value, undefined);

const revealed = await api(`/api/v3/guest/secret/${key}/reveal`, {
  method: "POST",
  body: {},
});
assert.equal(revealed.status, 200);
assert.equal(revealed.data.secret_value, secretValue);

const replay = await api(`/api/v3/guest/secret/${key}/reveal`, {
  method: "POST",
  body: {},
});
assert.equal(replay.status, 404);

console.log(`ok: create=${key.slice(0, 8)} preview=no-content reveal=match replay=404`);
