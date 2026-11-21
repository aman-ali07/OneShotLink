import { getConfig, type PublicConfig } from "@/lib/api";

// One schema definition, one type. Re-export so callers keep importing from
// either module without duplicating the inference.
export type { PublicConfig } from "@/lib/api";

// One cached fetch for the whole SPA. Views must not ship their own TTL
// allowlist: an operator can change TTL_OPTIONS and the UI has to follow it.
let cached: Promise<PublicConfig> | null = null;

export function publicConfig(): Promise<PublicConfig> {
  cached ??= getConfig();
  return cached;
}

export async function ttlOptions(): Promise<number[]> {
  return (await publicConfig()).ttl_options;
}

export async function defaultTtl(): Promise<number> {
  return (await publicConfig()).default_ttl;
}
