"""OneShotLink guest flow with the Python 3 standard library. No pip packages.

Usage: BASE_URL=http://127.0.0.1:3000 python3 examples/python/quickstart.py
"""

import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:3000")
SECRET_VALUE = f"python-example-{int(time.time())}"


def api(path, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"content-type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, {"raw": raw.decode(errors="replace")}


# Never hard-code a TTL: the operator may narrow the allowlist.
status, config = api("/api/v3/config")
assert status == 200, (status, config)
status, created = api("/api/v3/guest/conceal", "POST", {
    "secret": SECRET_VALUE, "ttl": config["default_ttl"],
})
assert status == 201, (status, created)
key = created["secret_key"]
assert key

# GET describes; it never spends the secret and never carries its value.
status, preview = api(f"/api/v3/guest/secret/{key}")
assert status == 200 and "secret_value" not in preview, (status, preview)

status, revealed = api(f"/api/v3/guest/secret/{key}/reveal", "POST", {})
assert status == 200 and revealed["secret_value"] == SECRET_VALUE, (status, revealed)

status, _ = api(f"/api/v3/guest/secret/{key}/reveal", "POST", {})
assert status == 404, status

print(f"ok: create={key[:8]} preview=no-content reveal=match replay=404")
