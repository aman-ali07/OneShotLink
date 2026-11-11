import { z } from "zod";

const ErrorEnvelope = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    request_id: z.string().optional(),
  }),
});

const ConfigSchema = z.object({
  ttl_options: z.array(z.number().int().positive()),
  default_ttl: z.number().int().positive(),
  auth_mode: z.string(),
  ui_enabled: z.boolean(),
  max_secret_bytes: z.number().int().positive(),
  version: z.string(),
});

const ReceiptSchema = z.object({
  identifier: z.string(),
  secret_ttl: z.number().int().positive(),
  created_at: z.number().int().optional(),
  passphrase_required: z.boolean(),
  kind: z.string().optional(),
  secret_url: z.string().optional(),
});

const CustomerSchema = z.object({
  id: z.string(),
  email: z.string(),
  role: z.string(),
  created_at: z.number().int().nullable().optional(),
});

const AccountSchema = z.object({ customer: CustomerSchema });
const ReceiptsSchema = z.object({ receipts: z.array(ReceiptSchema) });
const OkSchema = z.object({ ok: z.boolean() });

const ConcealResponseSchema = z.object({
  secret_key: z.string().min(1),
  receipt: ReceiptSchema,
  links: z.object({ secret: z.string().min(1) }),
});

const RevealResponseSchema = z.object({
  secret_value: z.string(),
  metadata: z.object({
    kind: z.string().nullable(),
    filename: z.string().nullable(),
    created_at: z.number().int().nullable(),
    ttl: z.number().int(),
  }),
});

export type PublicConfig = z.infer<typeof ConfigSchema>;
export type ConcealResponse = z.infer<typeof ConcealResponseSchema>;
export type RevealResponse = z.infer<typeof RevealResponseSchema>;
export type Customer = z.infer<typeof CustomerSchema>;
export type Receipt = z.infer<typeof ReceiptSchema>;

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

interface RequestOptions {
  method: "GET" | "POST" | "DELETE";
  body?: unknown;
  signal?: AbortSignal;
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  options: RequestOptions,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, {
      method: options.method,
      headers: options.body === undefined ? undefined : { "Content-Type": "application/json" },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: options.signal,
      credentials: "same-origin",
    });
  } catch (cause) {
    if (cause instanceof DOMException && cause.name === "AbortError") throw cause;
    throw new ApiError(0, "network_error", "The server could not be reached. Check your connection and try again.");
  }

  const text = await response.text();
  let payload: unknown = null;
  if (text.length > 0) {
    try {
      payload = JSON.parse(text);
    } catch {
      throw new ApiError(response.status, "invalid_response", "The server returned an unreadable response.");
    }
  }

  if (!response.ok) {
    const parsed = ErrorEnvelope.safeParse(payload);
    if (parsed.success) {
      throw new ApiError(response.status, parsed.data.error.code, parsed.data.error.message);
    }
    throw new ApiError(response.status, "request_failed", "The request failed. Please try again.");
  }

  const parsed = schema.safeParse(payload);
  if (!parsed.success) {
    throw new ApiError(response.status, "invalid_response", "The server returned an unexpected response.");
  }
  return parsed.data;
}

export function getConfig(signal?: AbortSignal): Promise<PublicConfig> {
  return request("/api/v3/config", ConfigSchema, { method: "GET", signal });
}

export function concealSecret(input: {
  secret: string;
  ttl: number;
  passphrase?: string;
}): Promise<ConcealResponse> {
  const body: Record<string, unknown> = { secret: input.secret, ttl: input.ttl };
  if (input.passphrase) body.passphrase = input.passphrase;
  return request("/api/v3/guest/conceal", ConcealResponseSchema, {
    method: "POST",
    body,
  });
}

export function revealSecret(key: string, passphrase?: string): Promise<RevealResponse> {
  const body = passphrase ? { passphrase } : {};
  return request(
    `/api/v3/guest/secret/${encodeURIComponent(key)}/reveal`,
    RevealResponseSchema,
    { method: "POST", body },
  );
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "rate_limited") {
      return "Too many requests. Wait a minute and try again.";
    }
    return error.message;
  }
  return "Something went wrong. Please try again.";
}

export function getAccount(): Promise<{ customer: Customer }> {
  return request("/api/v3/account/me", AccountSchema, { method: "GET" });
}

export function listReceipts(): Promise<{ receipts: Receipt[] }> {
  return request("/api/v3/account/receipts", ReceiptsSchema, { method: "GET" });
}

export function signUp(input: { email: string; password: string }): Promise<{ customer: Customer }> {
  return request("/api/v3/signup", AccountSchema, { method: "POST", body: input });
}

export function signIn(input: { email: string; password: string }): Promise<{ customer: Customer }> {
  return request("/api/v3/signin", AccountSchema, { method: "POST", body: input });
}

export function signOut(): Promise<{ ok: boolean }> {
  return request("/api/v3/signout", OkSchema, { method: "POST", body: {} });
}

export function changePassword(input: {
  currentPassword: string;
  newPassword: string;
}): Promise<{ ok: boolean }> {
  return request("/api/v3/account/password", OkSchema, {
    method: "POST",
    body: { current_password: input.currentPassword, new_password: input.newPassword },
  });
}

export function deleteAccount(input: { password: string }): Promise<{ ok: boolean }> {
  return request("/api/v3/account", OkSchema, {
    method: "DELETE",
    body: { password: input.password },
  });
}
