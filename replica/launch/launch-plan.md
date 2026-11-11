# Launch plan — OneShotLink

Sequenced so nothing claims a state the product is not in. Two milestones matter more than
any marketing beat: **the preflight gate passing on a real host** (T-70/T-71) and **the
restore drill repeated on that host** (T-72). Until both hold, the launch is a private beta
of a self-hosted repo, and the managed tier is not for sale (`pricing.md` §6).

## 0. Pre-launch checklist (blocking)

| # | Item | State today | Owner |
| --- | --- | --- | --- |
| 1 | CI green on `main`, 104 specs, container smoke test | **Done** — 4/4 jobs green on `99b613c` | repo |
| 2 | Brand sweep clean (`sweep.py --config replica/brand.json`) | **Done** — exit 0 | repo |
| 3 | Preflight gate passes with a real domain + certificate | **Blocked** — operator action: `HOST=https://<domain> PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh` | operator |
| 4 | Host firewall drops host → backend:6379 | **Blocked** — the nft/ufw rule in `DEPLOYMENT.md` §4.0 is written, not applied | operator |
| 5 | Restore drill repeated on the target host | **Blocked** — done once locally, RTO ≈ 12.4 s | operator |
| 6 | Privacy policy, terms, support URL live | **Written, not deployed** — `site/privacy.html`, `site/terms.html`; the operating entity/jurisdiction still has to be filled in by whoever runs the host | `replica-deploy` |
| 7 | Trademark screening for the name (US/EU/CA/WIPO, stores, handles) | **Not run** — listed in `replica/brand.md` §2 | human + lawyer |
| 8 | LD+JSON / OG image / favicon from the logo brief | Not made (brief only) | design |
| 9 | Landing page built | **Done, not deployed** — static site in `site/` (index, privacy, terms, styles, favicon); measured at 1280px and 375px, contrast verified, no third-party requests. Deliberately not a Vue route: the instance is the product | repo |

Rows 3–5 are the same three items the app has been waiting on since M3. They are the
launch, more than anything below is.

## 1. A list before a launch

- **Beta list, not a waitlist.** A waitlist implies scarcity we do not have; the product is
  installable today. One page: "self-hosted, pre-alpha, here is the compose command, tell us
  what broke" plus an optional email field for release notes. Host it on the same instance
  the landing page lives on.
- **Do not buy a list, and do not build the page before the privacy policy exists** — the
  form collects an email address, which is the first personal data the project touches.
- Repository signal that actually converts for this audience: a README quickstart that
  works on a clean Ubuntu box (three commands, copy-pasteable), a `SECURITY.md` that states
  the threat model, and a CHANGELOG that says what is verified vs planned.

## 2. Instrumentation — decide, then install

| Need | Choice | State |
| --- | --- | --- |
| Uptime / errors | `GET /metrics` behind `METRICS_ENABLED` (Prometheus) + a status page | Endpoint exists (T-73); status page not built |
| Product analytics | Self-hosted Plausible or Umami on the same host, **no third-party pixel** — an ad-tech script on a privacy product is self-defeating | Not installed. This is a decision + a deploy task, not a plugin |
| Error tracking | Sentry-compatible endpoint pointed at a self-hosted instance, or nothing; never send secret material (the app redacts) | Not installed |
| Install signal | Docker Hub / GHCR pull counts, a `doctor` line in the README | Not measured |

Rule: the instrumentation must be installable and verifiable by the user too, or the
"prove it yourself" angle dies at the first `<script>` tag.

## 3. Where the unhappiness already lives

From the research (`replica/fixes.md` §1, `replica/reviews.csv`), these are the real threads
where the exact objection was raised. Read them, answer with substance, never paste a
testimonial from them:

- <https://news.ycombinator.com/item?id=23020848> — "no reason to believe is trustworthy"
  (the thread also carries the KDF allegations, §1.2).
- <https://news.ycombinator.com/item?id=26435940>
- <https://news.ycombinator.com/item?id=27484585>
- <https://news.ycombinator.com/item?id=31893500> — mail scanners burning links.
- <https://security.stackexchange.com/questions/271105> — "not sure how reliable this site
  is" (answer the question, do not advertise).

**Reddit was not reachable during research** (HTTP 403 on the public JSON endpoints), so
r/selfhosted, r/privacy and r/sysadmin are *unverified* venues: subscribe by hand and read
the rules before posting. Do not claim research you did not do.

## 4. The launch post (HN / Product Hunt), leading with the fix

Title: **Show HN: OneShotLink — a one-time secret service you can self-host**

Body, in the brand voice, ~150 words:

> Sending a password to someone outside your org usually means handing it to a server you
> do not control, and hoping the operator is honest. So this runs on yours: two env vars,
> one compose command, your Redis.
>
> It is a one-time secret service: paste a secret, pick an expiry, send a link. The
> recipient confirms, the record is deleted by an atomic compare-and-delete, and a second
> attempt gets the same `404` as a secret that never existed.
>
> Crypto, stated plainly: AES-256-GCM at rest under a key derived from the instance secret.
> The server holds that key, so it can read a revealed secret, and the passphrase is an
> access check rather than a second key. It is not zero-knowledge and the README does not
> say it is.
>
> 104 specs, CI on every push, a preflight script that refuses to call a deployment ready
> if TLS, HSTS, cookies or Redis isolation fail.

Rules for the post and the comments:

- **Do not lead with the original's name** and do not name it in the title, keywords or
  ads (store and copycat rules, and it invites a takedown). If someone names it in the
  comments, answer factually about *our* behaviour and move on.
- **Disclose provenance honestly if asked.** It is a from-scratch reimplementation of a
  category, not a fork; say that.
- Answer the KDF objection before it is raised: link the crypto file, say what the key
  derivation is (`HKDF` over the instance secret, per-record random salt, AES-256-GCM with
  the tag verified on decrypt) and invite the audit.
- **Never claim "production ready".** If asked, say what is verified and what is an
  operator action, and link `PRODUCTION_READINESS.md`.
- Product Hunt: same copy, plus a 1200×630 image from the logo brief and three screenshots
  of the real UI. Do not launch PH and HN on the same day; HN first, PH 3–5 days later.

## 5. The first ten users, by hand

Not a funnel: ten conversations, each tied to one fix from `fixes.md` §4.

| # | Who | Where | Ask |
| --- | --- | --- | --- |
| 1–3 | Self-hosters already running their own services | r/selfhosted (once verified), a HomeLab/self-hosting Discord | Install it on their box; report the first thing that broke |
| 4–5 | People who complained about hosting trust | The HN/SE threads in §3, answering the objection | Would this have changed your mind? What is missing? |
| 6–7 | Small consultancies sending credentials to clients | Direct, via their public contact form | Use it for one real handover this week |
| 8 | Someone who runs mail scanners / bots | Their thread (§1.5) | Try to burn a link with a previewer, tell us what happens |
| 9 | A security reviewer | Local OWASP/meetup or the SE answerer | Read `SECURITY.md`, break it, file issues |
| 10 | A team that asked for SSO | HN comments asking for teams | Confirm whether `AUTH_MODE=full` is worth building (it is the biggest open item) |

For each: what they tried, what broke, what they asked for — recorded in
`replica/fixes.md` as new evidence, not as testimonials. Real beta users with permission can
appear on the landing page later; invented ones never.

## 6. Success signals, honestly defined

- **Install → first secret in under 5 minutes**, measured by two people who have never seen
  the repo (not by us).
- **Zero 5xx in the first month** on the hosted instance, from `/metrics`.
- **At least one external issue filed that is not about documentation.**
- The preflight gate passing on three different hosts, one of them not ours.

Not signals: stars, upvotes, PH ranking. They do not tell you whether a secret was
delivered safely.

## 7. Order of operations

1. Operator: apply the firewall rule, point a domain, run `script/preflight.sh` → green.
2. Write privacy policy + terms + support page (`replica-deploy`).
3. Build the landing route from `landing.md`, re-check contrast, capture real screenshots.
4. Install self-hosted analytics; verify no third-party script is loaded.
5. Register the domains from `brand.md` §2; start trademark screening in parallel.
6. Open the beta list; ship the README quickstart test on a clean box.
7. HN post (§4), then answer every comment for 48 hours.
8. Product Hunt 3–5 days later, same copy, real screenshots.
9. First ten conversations (§5); feed the results back into `fixes.md`.
10. Only then: turn on the managed tier in Stripe test mode, then live.
