# Go-live reminder — OneShotLink

Plain-language note to self. The **app is done**: 142 backend specs, 12 Vitest tests, four
browser journeys (text, accounts, file), clean typecheck/build, brand sweep, and free-tier-safe
checks all pass.
What remains is not code — it is hosting, a public address, and two sign-offs.

> Rule from `AGENTS.md`: do not say "production ready" or "zero-knowledge" in public copy
> until the items below are closed with evidence. Until then, call it **production-packaged,
> go-live pending** or **free-tier beta**.

## The four blockers, in simple words

- [ ] **1. A real address with HTTPS (T-70 / B5).** Today the app only runs on this computer.
      People need a public `https://` address. We rehearsed TLS with a throwaway certificate and
      it passed, but a real domain/certificate has never been tested. Final proof:
      `HOST=https://<your-real-host> script/preflight.sh` must exit `0`.

- [ ] **2. Redis must not be reachable from the host itself (B6 / T-71).** Redis is where the
      encrypted secrets live. Inside Docker it is already password-protected and has no internet
      access. On a normal VPS the server's own OS can still reach port 6379, so we add one narrow
      firewall rule. It is already applied on **this** machine; a new server needs it again:
      `DEPLOYMENT.md §4.0`. On a managed/free Redis this becomes the provider's job — record
      that decision instead of assuming the rule carried over.

- [ ] **3. Legal pages served publicly (B2).** `site/privacy.html` and `site/terms.html` exist but
      are not live anywhere. Social preview images also need a real absolute URL.

- [ ] **4. Finish the name check (B4).** `OneShotLink` looked clear in the places already checked
      (US trademark wordmark, app stores, domains, package registries). Still outstanding: a few
      more registries, social handles, a normal web search, and a lawyer's opinion. This is about
      avoiding a naming dispute, not about software.

## Reality check before buying a VPS

You said: **free tiers only for now; buy a real VPS when people actually start using it.**
That is a sensible plan. Free tiers can host a real beta, with three honest caveats:

1. **Paid domain not required at first.** A free `https://` subdomain from a host is a real
   hostname with a real certificate — that can close blocker 1 for the beta, as long as the
   preflight gate passes there. A custom domain can come later with the VPS.
2. **Free compute sleeps.** Render's free web service (and similar tiers) spin down when idle;
   the first request after a pause takes tens of seconds. Fine for a beta, not for a launch.
3. **Free Redis is usually not durable.** Secrets are encrypted and expire by TTL anyway, but a
   free Redis can vanish on restart. Say so in the beta's UI copy and do not promise persistence
   or backups until you have paid storage. Backups written to `/backups` need a persistent disk,
   which free tiers rarely offer.

## Free-tier-first path (verify current tier terms before committing — they change)

### Step A — static marketing site (free, easy)
- Put `site/` on **Cloudflare Pages** or **Vercel** (both give free HTTPS on a `*.pages.dev` /
  `*.vercel.app` address). No backend needed for these files.
- Keep privacy/terms links working; set an absolute `og:image` once the URL exists.
- This closes the "legal pages live" part of blocker 3.

### Step B — the actual app (free, with caveats)
The app needs a long-running Ruby server (Puma) **and** Redis, so Vercel/Cloudflare Pages alone
cannot run it. They are for static files only.

- Deploy the existing `Dockerfile` as a **Render free web service** (or another free container
  host). It gives a free `https://<app>.onrender.com` address with a valid certificate.
- Use a **free TLS Redis endpoint** (for example Upstash free tier) via
  `REDIS_URL=rediss://…`. The app already supports `rediss://` with a password and folds
  `REDIS_PASSWORD` into the URL.
- Required app env on the host: `SECRET` (32+ bytes, generated there), `REDIS_PASSWORD`,
  `HOST=<the free hostname>`, `SSL=true`, `TRUST_PROXY=true`, `TRUSTED_PROXIES=<proxy CIDRs>`,
  `AUTH_MODE=simple` (or `disabled` if you do not want accounts yet).
- Check current terms for: free Redis limits, whether the container tier still exists, and
  whether outbound internet is allowed. **Never put real keys in git** — set them in the
  provider's dashboard, never in `.env` committed to the repo.

### Step C — prove it, don't assume it
- `curl -fsS https://<app-host>/health` → `{"status":"ok","redis":"ok"}`
- `HOST=https://<app-host> script/preflight.sh` → must exit `0` (TLS chain, HSTS, security
  headers, `Secure`/`HttpOnly`/`SameSite` cookie, HTTP→HTTPS redirect). Note: it creates a
  throwaway signup, so run it on a beta instance, not on real user data.
- In a browser: create → copy link → open → reveal once → second open shows "gone".
- Record the exact command output in `replica/deploy.md` §1 and the handoff memo.

### Step D — upgrade trigger
Buy the VPS and a domain when **any** of these become true:
- real users report the cold-start delay is annoying;
- free Redis limits or restarts cause lost secrets;
- you need backups, a custom domain, monitoring, or support;
- traffic approaches the free tier's request/ bandwidth cap.

On that VPS: point DNS at it, terminate TLS at the proxy, and reapply the Redis host firewall
rule from `DEPLOYMENT.md §4.0`. That is when blocker 2 is properly closed for your own host.

## What I still cannot do for you

Buy a domain, install a certificate on your host, apply a firewall rule on a server I do not
control, finish the trademark/lawyer review, or sign the go/no-go. Those need your account,
your money, and your signature. Everything in the repository is already done and green.

## Where the detailed versions live

- `PRODUCTION_READINESS.md` — the strict, evidence-backed status.
- `docs/GO_LIVE_HANDOFF.md` — operator sequence and approval line.
- `DEPLOYMENT.md §4.0 and §4.2` — Redis firewall rule and the deploy order.
- `RUNBOOK.md` — what to do when something breaks.

Status of this note: written 2026-11-20, at `main` = `d4d725b`. Update it when a blocker closes.
