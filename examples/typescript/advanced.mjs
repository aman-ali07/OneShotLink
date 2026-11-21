// Advanced OneShotLink flow (Node 18+ stdlib): passphrase, file, owner burn.
// Usage: BASE_URL=http://127.0.0.1:3000 node examples/typescript/advanced.mjs
// Requires AUTH_MODE=simple. Never logs secret values.
const BASE = (process.env.BASE_URL || "http://127.0.0.1:3000").replace(/\/$/, "");
const stamp = Date.now();
let cookie = "";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function call(method, path, body) {
  const headers = { Origin: BASE };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const response = await fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const setCookie = response.headers.get("set-cookie");
  if (setCookie) cookie = setCookie.split(";")[0];
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

const signup = await call("POST", "/api/v3/signup", {
  email: `ts-advanced-${stamp}@example.com`,
  password: `advanced-example-password-${stamp}`,
});
assert(signup.status === 201, `signup failed: ${signup.status}`);

const guarded = `ts-pass-${stamp}`;
const created = await call("POST", "/api/v3/guest/conceal", {
  secret: guarded, ttl: 1800, passphrase: "correct-horse",
});
assert(created.status === 201, "create failed");
const key = created.body.secret_key;

const preview = await call("GET", `/api/v3/guest/secret/${key}`);
assert(preview.status === 200 && preview.body.passphrase_required === true, "preview lost the gate");
const wrong = await call("POST", `/api/v3/guest/secret/${key}/reveal`, { passphrase: "wrong" });
assert(wrong.status === 401 && wrong.body.error.code === "invalid_passphrase", "wrong guess accepted");
const right = await call("POST", `/api/v3/guest/secret/${key}/reveal`, { passphrase: "correct-horse" });
assert(right.status === 200 && right.body.secret_value === guarded, "right guess failed");

const payload = Buffer.from([0, 1, 0xfe, 0xff, 0x41, 0x42]);
const fileCreated = await call("POST", "/api/v3/guest/conceal", {
  secret: payload.toString("base64"), ttl: 1800, kind: "file", filename: "fixture.bin",
});
assert(fileCreated.status === 201, "file create failed");
const fileResult = await call("POST", `/api/v3/guest/secret/${fileCreated.body.secret_key}/reveal`, {});
assert(Buffer.from(fileResult.body.secret_value, "base64").equals(payload), "file bytes changed");
assert(fileResult.body.metadata.filename === "fixture.bin", "filename lost");

const burnCreated = await call("POST", "/api/v3/secret/conceal", { secret: "burn-me", ttl: 1800 });
assert(burnCreated.status === 201, "owner create failed");
const burned = await call("DELETE", `/api/v3/secret/${burnCreated.body.secret_key}`, {});
assert(burned.status === 200 && burned.body.metadata.status === "burned", "burn failed");
const replay = await call("POST", `/api/v3/guest/secret/${burnCreated.body.secret_key}/reveal`, {});
assert(replay.status === 404, "burned link still live");

console.log(`ok: passphrase=${key.slice(0, 8)} wrong=401 right=200 file=${fileCreated.body.secret_key.slice(0, 8)} burn=burned replay=404`);
