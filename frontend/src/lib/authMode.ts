import { publicConfig } from "@/lib/config";

// Accounts are optional. A failed fetch hides the account entry points —
// sharing still works without them. `full` is deliberately unimplemented on the
// server (501), so it must not light up account navigation either.
let cached: Promise<boolean> | null = null;

export function accountsEnabled(): Promise<boolean> {
  cached ??= publicConfig()
    .then((config) => config.auth_mode === "simple")
    .catch(() => false);
  return cached;
}
