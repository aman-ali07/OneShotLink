"""Advanced OneShotLink flow (stdlib only): passphrase, file, owner burn.

Usage: BASE_URL=http://127.0.0.1:3000 python3 examples/python/advanced.py
Requires AUTH_MODE=simple on the target instance. Never logs secret values.
"""
import base64
import http.cookiejar
import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:3000").rstrip("/")
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
stamp = str(int(time.time()))


def call(method, path, body=None, auth=False):
    headers = {"Origin": BASE}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with opener.open(request, timeout=10) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


def ok(condition, message):
    if not condition:
        raise AssertionError(message)


status, _ = call("POST", "/api/v3/signup", {
    "email": f"py-advanced-{stamp}@example.com",
    "password": f"advanced-example-password-{stamp}",
})
ok(status == 201, f"signup failed: {status}")

guarded = f"py-pass-{stamp}"
status, created = call("POST", "/api/v3/guest/conceal", {
    "secret": guarded, "ttl": 1800, "passphrase": "correct-horse",
})
ok(status == 201, f"create failed: {status}")
key = created["secret_key"]

status, preview = call("GET", f"/api/v3/guest/secret/{key}")
ok(status == 200 and preview["passphrase_required"] is True, "preview did not report the gate")
status, wrong = call("POST", f"/api/v3/guest/secret/{key}/reveal", {"passphrase": "wrong"})
ok(status == 401 and wrong["error"]["code"] == "invalid_passphrase", "wrong guess was not rejected")
status, right = call("POST", f"/api/v3/guest/secret/{key}/reveal", {"passphrase": "correct-horse"})
ok(status == 200 and right["secret_value"] == guarded, "right guess did not reveal")

payload = b"\x00\x01\xfe\xffAB"
status, file_created = call("POST", "/api/v3/guest/conceal", {
    "secret": base64.b64encode(payload).decode(), "ttl": 1800,
    "kind": "file", "filename": "fixture.bin",
})
ok(status == 201, f"file create failed: {status}")
status, file_result = call("POST", f"/api/v3/guest/secret/{file_created['secret_key']}/reveal", {})
ok(status == 200 and base64.b64decode(file_result["secret_value"]) == payload, "file round-trip failed")
ok(file_result["metadata"]["filename"] == "fixture.bin", "filename lost")

status, burned = call("POST", "/api/v3/secret/conceal", {"secret": "burn-me", "ttl": 1800})
ok(status == 201, "owner create failed")
status, result = call("DELETE", f"/api/v3/secret/{burned['secret_key']}", {})
ok(status == 200 and result["metadata"]["status"] == "burned", "burn failed")
status, _ = call("POST", f"/api/v3/guest/secret/{burned['secret_key']}/reveal", {})
ok(status == 404, "burned link was still live")

print(f"ok: passphrase={key[:8]} wrong=401 right=200 file={file_created['secret_key'][:8]} burn=burned replay=404")
