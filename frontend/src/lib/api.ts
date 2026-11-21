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
  max_file_bytes: z.number().int().positive().optional(),
  version: z.string(),
});

const ReceiptSchema = z.object({
  identifier: z.string(),
  secret_ttl: z.number().int().positive(),
  created_at: z.number().int().optional(),
  passphrase_required: z.boolean(),
  kind: z.string().optional(),
  secret_url: z.string().optional(),
  // Lifecycle state from D-017: new | previewed | revealed | burned.
  status: z.enum(["new", "previewed", "revealed", "burned"]).optional(),
});

const WebhookSchema = z.object({
  id: z.string(),
  url: z.string(),
  events: z.array(z.string()),
  enabled: z.boolean(),
  created_at: z.number().int(),
});

const WebhookCreateSchema = WebhookSchema.extend({ signing_secret: z.string() });

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

const RequestMetadataSchema = z.object({
  label: z.string(),
  created_at: z.number().int().nullable().optional(),
  ttl: z.number().int(),
});

const RequestPreviewSchema = z.object({
  fulfilled: z.boolean(),
  metadata: RequestMetadataSchema,
});

const RequestItemSchema = RequestMetadataSchema.extend({
  request_key: z.string(),
  fulfilled: z.boolean(),
});

const CreateRequestResponseSchema = z.object({
  request_key: z.string().min(1),
  metadata: RequestMetadataSchema,
  links: z.object({ request: z.string().min(1) }),
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
export type RequestPreview = z.infer<typeof RequestPreviewSchema>;
export type RequestItem = z.infer<typeof RequestItemSchema>;
export type Webhook = z.infer<typeof WebhookSchema>;
export type Receipt = z.infer<typeof ReceiptSchema>;

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfter: number | null;
  // Correlation id from the X-Request-Id header (or the error envelope).
  // Keep it on the typed error so callers can quote it in support reports.
  readonly requestId: string | null;

  constructor(
    status: number,
    code: string,
    message: string,
    retryAfter: number | null = null,
    requestId: string | null = null,
  ) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.retryAfter = retryAfter;
    this.requestId = requestId;
  }
}

const DEFAULT_TIMEOUT_MS = 15_000;

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
  // A caller-supplied signal (view teardown) wins; otherwise cap every request
  // so a hung connection cannot leave a spinner or skeleton up forever.
  const timeoutSignal = options.signal ? undefined : AbortSignal.timeout(DEFAULT_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(path, {
      method: options.method,
      headers: options.body === undefined ? undefined : { "Content-Type": "application/json" },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: options.signal ?? timeoutSignal,
      credentials: "same-origin",
    });
  } catch (cause) {
    if (timeoutSignal?.aborted) {
      throw new ApiError(0, "timeout", "The server took too long to respond. Try again.");
    }
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
    const retryAfterRaw = response.headers.get("Retry-After");
    const retryAfter = retryAfterRaw !== null && /^\d+$/.test(retryAfterRaw) ? Number(retryAfterRaw) : null;
    const requestId = response.headers.get("X-Request-Id");
    const parsed = ErrorEnvelope.safeParse(payload);
    if (parsed.success) {
      throw new ApiError(
        response.status, parsed.data.error.code, parsed.data.error.message,
        retryAfter, requestId ?? parsed.data.error.request_id ?? null,
      );
    }
    throw new ApiError(
      response.status, "request_failed", "The request failed. Please try again.",
      retryAfter, requestId,
    );
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
  kind?: "text" | "file";
  filename?: string;
}): Promise<ConcealResponse> {
  const body: Record<string, unknown> = { secret: input.secret, ttl: input.ttl };
  if (input.passphrase) body.passphrase = input.passphrase;
  if (input.kind) body.kind = input.kind;
  if (input.kind === "file") body.filename = input.filename;
  return request("/api/v3/guest/conceal", ConcealResponseSchema, {
    method: "POST",
    body,
  });
}

const PeekSchema = z.object({
  passphrase_required: z.boolean(),
  metadata: z.object({
    kind: z.string().nullable(),
    filename: z.string().nullable().optional(),
    created_at: z.number().int().nullable().optional(),
    ttl: z.number().int(),
  }),
});
export type SecretPreview = z.infer<typeof PeekSchema>;

// GET is a non-consuming preview: chat unfurlers and the SPA can inspect a
// link without spending it. Only POST .../reveal returns plaintext.
export function peekSecret(key: string, signal?: AbortSignal): Promise<SecretPreview> {
  return request(`/api/v3/guest/secret/${encodeURIComponent(key)}`, PeekSchema, {
    method: "GET",
    signal,
  });
}

// Owner-only destruction: the payload is deleted without being returned.
export function burnSecret(key: string): Promise<{
  ok: boolean;
  metadata: { identifier: string; status: "burned" };
}> {
  return request(
    `/api/v3/secret/${encodeURIComponent(key)}`,
    z.object({
      ok: z.boolean(),
      metadata: z.object({ identifier: z.string(), status: z.literal("burned") }),
    }),
    { method: "DELETE", body: {} },
  );
}

export function revealSecret(key: string, passphrase?: string): Promise<RevealResponse> {
  const body = passphrase ? { passphrase } : {};
  return request(
    `/api/v3/guest/secret/${encodeURIComponent(key)}/reveal`,
    RevealResponseSchema,
    { method: "POST", body },
  );
}

export function getRequest(key: string, signal?: AbortSignal): Promise<RequestPreview> {
  return request(`/api/v3/requests/${encodeURIComponent(key)}`, RequestPreviewSchema, {
    method: "GET",
    signal,
  });
}

export function respondToRequest(key: string, secret: string): Promise<{ ok: boolean; label: string }> {
  return request(
    `/api/v3/requests/${encodeURIComponent(key)}/respond`,
    z.object({ ok: z.boolean(), label: z.string() }),
    { method: "POST", body: { secret } },
  );
}

export function listRequests(): Promise<{ requests: RequestItem[] }> {
  return request("/api/v3/requests", z.object({ requests: z.array(RequestItemSchema) }), {
    method: "GET",
  });
}

export function createRequest(label: string, ttl: number): Promise<z.infer<typeof CreateRequestResponseSchema>> {
  return request("/api/v3/requests", CreateRequestResponseSchema, {
    method: "POST",
    body: { label, ttl },
  });
}

export function revealRequest(key: string): Promise<RevealResponse> {
  return request(
    `/api/v3/requests/${encodeURIComponent(key)}/reveal`,
    RevealResponseSchema,
    { method: "POST", body: {} },
  );
}

export function listWebhooks(): Promise<{ webhooks: Webhook[] }> {
  return request("/api/v3/webhooks", z.object({ webhooks: z.array(WebhookSchema) }), {
    method: "GET",
  });
}

export function createWebhook(url: string, events: string[]): Promise<z.infer<typeof WebhookCreateSchema>> {
  return request("/api/v3/webhooks", WebhookCreateSchema, {
    method: "POST",
    body: { url, events },
  });
}

export function deleteWebhook(id: string): Promise<{ ok: boolean }> {
  return request(`/api/v3/webhooks/${encodeURIComponent(id)}`, z.object({ ok: z.boolean() }), {
    method: "DELETE",
  });
}

const DeliverySchema = z.object({
  id: z.string(),
  event: z.string(),
  status: z.string(),
  attempts: z.number().int(),
  response_code: z.number().int().nullable(),
  created_at: z.number().int(),
});
export type Delivery = z.infer<typeof DeliverySchema>;

export function listWebhookDeliveries(id: string): Promise<{ deliveries: z.infer<typeof DeliverySchema>[] }> {
  return request(`/api/v3/webhooks/${encodeURIComponent(id)}/deliveries`,
    z.object({ deliveries: z.array(DeliverySchema) }), { method: "GET" });
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "rate_limited") {
      return error.retryAfter
        ? `Too many requests. Try again in ${error.retryAfter} seconds.`
        : "Too many requests. Wait a minute and try again.";
    }
    if (error.code === "service_unavailable") {
      return "Storage is temporarily unavailable. Try again shortly.";
    }
    if (error.code === "timeout") {
      return error.message;
    }
    if (error.status === 403) {
      return "This action is not available on this instance or account.";
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
