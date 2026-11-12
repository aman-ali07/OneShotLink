import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ApiError,
  concealSecret,
  deleteAccount,
  errorMessage,
  getConfig,
  revealSecret,
} from "./api";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const receipt = {
  identifier: "abc123",
  secret_ttl: 1800,
  passphrase_required: false,
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("concealSecret", () => {
  it("posts the secret and parses the receipt", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        secret_key: "key123",
        receipt,
        links: { secret: "/secret/key123" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await concealSecret({ secret: "hello", ttl: 1800 });

    expect(result.secret_key).toBe("key123");
    const [path, init] = fetchMock.mock.calls[0]!;
    expect(path).toBe("/api/v3/guest/conceal");
    expect(init).toMatchObject({ method: "POST", credentials: "same-origin" });
    expect(JSON.parse(init.body)).toEqual({ secret: "hello", ttl: 1800 });
  });

  it("includes a passphrase only when non-empty", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ secret_key: "key123", receipt, links: { secret: "/secret/key123" } }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await concealSecret({ secret: "hello", ttl: 1800, passphrase: "open sesame" });

    expect(JSON.parse(fetchMock.mock.calls[0]![1].body)).toEqual({
      secret: "hello",
      ttl: 1800,
      passphrase: "open sesame",
    });
  });
});

describe("revealSecret", () => {
  it("encodes the key and returns the secret value", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        secret_value: "hello",
        metadata: { kind: "text", filename: null, created_at: 1, ttl: 1800 },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await revealSecret("a/b");

    expect(result.secret_value).toBe("hello");
    expect(fetchMock.mock.calls[0]![0]).toBe("/api/v3/guest/secret/a%2Fb/reveal");
  });

  it("maps a wrong passphrase to a typed ApiError without losing the message", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        jsonResponse(
          { error: { code: "invalid_passphrase", message: "That passphrase is not correct." } },
          401,
        ),
      ),
    );

    await expect(revealSecret("key", "wrong")).rejects.toMatchObject({
      name: "ApiError",
      status: 401,
      code: "invalid_passphrase",
    });
  });
});

describe("deleteAccount", () => {
  it("sends DELETE with the password and same-origin credentials", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ ok: true }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await deleteAccount({ password: "correct horse battery" });

    expect(result).toEqual({ ok: true });
    const [path, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(path).toBe("/api/v3/account");
    expect(init.method).toBe("DELETE");
    expect(JSON.parse(String(init.body))).toEqual({ password: "correct horse battery" });
    expect(init.credentials).toBe("same-origin");
  });

  it("surfaces a rejected password as a typed error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        jsonResponse({ error: { code: "invalid_credentials", message: "That password is not correct." } }, 401),
      ),
    );

    await expect(deleteAccount({ password: "wrong" })).rejects.toMatchObject({
      status: 401,
      code: "invalid_credentials",
    });
  });
});

describe("response validation", () => {
  it("rejects malformed JSON", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("<html>", { status: 502 })));

    await expect(getConfig()).rejects.toMatchObject({ code: "invalid_response" });
  });

  it("rejects a successful response with the wrong shape", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({ nope: true })));

    await expect(getConfig()).rejects.toMatchObject({ code: "invalid_response" });
  });

  it("reports an unreachable server as network_error", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("failed")));

    await expect(getConfig()).rejects.toMatchObject({ code: "network_error" });
  });
});

describe("errorMessage", () => {
  it("uses a stable message for rate limiting", () => {
    const error = new ApiError(429, "rate_limited", "Too many requests.");
    expect(errorMessage(error)).toMatch(/Too many requests/);
  });

  it("falls back for unknown errors", () => {
    expect(errorMessage(new Error("boom"))).toMatch(/Something went wrong/);
  });
});
