# What the original's users actually say — and what we do about it

**Sample: 20 records from 3 sources** — Hacker News (17 comments via the official
Algolia API), Security Stack Exchange (2) and Stack Overflow (1). Collected
2026-11-11. No star ratings exist on these sources.

**Read this first.** Twenty records across three sources support a *direction*, not a
ranking. Most themes below have 1–4 reviews and 1–2 sources, so each is marked
**thin**. Nothing here justifies betting the roadmap without more data. Reddit was
not reachable during collection (`HTTP 403` from the public JSON endpoints), the
original has **no official iOS/Android app**, and it is not listed on G2/Capterra, so
those sources contributed nothing rather than being guessed at.

The automatic ranking in `feedback.md` is produced by `reviews.py` with
`themes-secrets.json`. Its keyword matching is noisy (for example `file` matches
"file an issue"), so the counts below were **coded by hand** from the same 20 rows.
Every quote is verbatim and links to its source.

---

## 1. What they hate

### 1.1 Distrust of a third-party host — 4 reviews, 2 sources (thin)

The single most repeated sentiment is not about features: it is that people do not
want to hand credentials to someone else's server.

> "this is a free tool hosted by a third party that IMHO there was no reason to
> believe is trustworthy"
> — <https://news.ycombinator.com/item?id=23020848>

> "There was onetimesecret, but I never really trusted it..."
> — <https://news.ycombinator.com/item?id=26435940>

> "I was often using onetimesecret which is great, but still felt wary of trusting a
> hosted service for these things."
> — <https://news.ycombinator.com/item?id=27484585>

> "But I'm not sure how reliable this site is. For all I know they might be storing
> all my secrets in a public txt file shared on the web"
> — <https://security.stackexchange.com/questions/271105/best-method-to-send-credentials-to-clients>

### 1.2 Claimed crypto weakness — 2 reviews, 1 source (thin)

A 2020 thread made specific, technical allegations about key derivation. Whether or
not they were right at the time, this is the shape of the objection that will be
raised against any clone too.

> "I really wouldn't trust that KDF."
> — <https://news.ycombinator.com/item?id=23020952>

> "I suspect the entropy is really bad. ... At no point is anything touching
> /dev/urandom, which is how cryptography keys should be generated."
> — <https://news.ycombinator.com/item?id=23023242>

### 1.3 Self-host setup fails for real users — 1 review, 1 source (thin)

> "i installed the app as was instructed in the README but i keep getting the : Oops!
> You found a bug. Let us know how it happened! page"
> — <https://stackoverflow.com/questions/66911396/ruby-app-onetimesecret-getting-keep-getting-get-http-1-1-401-getting-oops>

### 1.4 Interface confusion — 1 review, 1 source (thin)

> "created: 1,179 | viewed: 960 | compromised: 0 — Is the number of compromised
> secrets a joke?"
> — <https://news.ycombinator.com/item?id=27715868>

### 1.5 Link previewers and scanners burn one-time links — 2 reviews, 1 source (thin)

An under-discussed hazard for every one-time link: anything that fetches the URL
(chat previews, mail scanners, search crawlers) consumes the secret before the human
opens it.

> "Then, any automated system which sees the link cannot accidentally cause the file
> to be "downloaded" which would cause the link to be invalidated."
> — <https://news.ycombinator.com/item?id=19373453>

> "The original post is just complaining that the malware scanning is visiting the
> links."
> — <https://news.ycombinator.com/item?id=31893500>

### 1.6 Downtime and DDoS — 1 review, 1 source (thin)

> "There's a bit more info on our blog: … 2024-09-12-ddos-day-4"
> — <https://news.ycombinator.com/item?id=41525144> (the project's own incident posts)

---

## 2. What is missing

### 2.1 File and image secrets — 2 reviews, 2 sources (thin)

> "Does not support images or view limits greater than 1, but does support requiring a
> password to view."
> — <https://news.ycombinator.com/item?id=7345661>

> "Alice: I need the file"
> — <https://security.stackexchange.com/questions/184706/can-we-trust-onetimesecret>

*Caveat: the first quote is from 2014. Re-verify the original's current file support
before claiming a gap.*

### 2.2 More than one view / read counts — 1 review, 1 source (thin)

Same quote as 2.1 ("view limits greater than 1").

### 2.3 Client-side (zero-knowledge) encryption — 3 reviews, 2 sources (thin)

The strongest technical ask. People are happy to use it, but want the server to be
unable to read the secret.

> "onetimesecret, burnernote - but I wanted something that did encryption client
> side."
> — <https://news.ycombinator.com/item?id=37864235>

> "crypt.fyi … ensures your data is private and disappears once accessed."
> — <https://news.ycombinator.com/item?id=42668663>

> "Can we trust onetimesecret?"
> — <https://security.stackexchange.com/questions/184706/can-we-trust-onetimesecret>

---

## 3. What is unsolved (the positioning opening)

The recurring job is **"send a credential to someone outside my trust boundary,
without either of us creating an account, and without trusting an operator's
server."** No incumbent fully satisfies all four, and the complaint data says the
weakest link is the last one.

### 3.1 A host you can prove, not just trust — 4 reviews, 2 sources

Section 1.1. The buying question is not "is it encrypted" but "can I run it myself
and verify what it does".

### 3.2 No-account recipient — a strength worth protecting — 3 reviews, 1 source (thin)

The original does this well, and people call it out as the reason they reject
alternatives that require signup:

> "The idea of the other party needing to setup an account is off-putting to me. …
> I handle this currently is to use https://onetimesecret.com"
> — <https://news.ycombinator.com/item?id=26439235>

> "It's probably technically not as easy for a one off situation as
> onetimesecret.com"
> — <https://news.ycombinator.com/item?id=23021352>

---

## 4. Fix plan

Ordered by evidence strength × how cheaply we can close it. Sizes: **S** ≤ 1 day,
**M** ≤ 1 week, **L** bigger. Each maps to a row in `features.csv`.

| # | What to build or change | Size | Evidence | Owner |
| --- | --- | --- | --- | --- |
| 1 | **Lead with self-hosting, and make it provable**: a one-command quickstart, a published crypto spec (AES-256-GCM, HKDF, Argon2id, atomic Lua consume) and a "verify it yourself" page | S | 1.1, 1.2, 1.3 — 6 reviews | replica-launch + docs |
| 2 | **Preview-safe links**: default-on passphrase, or a clear warning that chat/mail previewers consume a link, so a one-time URL survives being pasted into Slack | M | 1.5 — 2 reviews | replica-build |
| 3 | **Honest crypto copy**: state plainly that we encrypt at rest and the passphrase is an access gate, *not* zero-knowledge, and publish the exact threat model | S | 1.2, 2.3 — 5 reviews | docs (SECURITY.md) |
| 4 | **Opt-in zero-knowledge mode** (encrypt in the browser) | L | 2.3 — 3 reviews | v2 decision (D-012) |
| 5 | **File secrets** with the same one-time invariant | L | 2.1 — 2 reviews | T-63 |
| 6 | **Read counts > 1** (N views, then gone) | M | 2.2 — 1 review | backlog |
| 7 | **Availability evidence**: documented RTO/RPO and backups (already done) exposed as a status page | S | 1.6 — 1 review | replica-deploy |

**Deliberately not doing yet:** 1.4 (interface wording) — one review, and the fix is
copy, not code; 1.6 needs an operator host, not a feature.

---

## 5. The angle

Three options, each grounded in a theme above.

**A. Self-host first (recommended)**
> For teams who won't hand credentials to someone else's server, **OneShotLink** is a
> one-command, self-hosted one-time-secret service whose crypto you can read, whose
> reveal is atomic, and whose recipient never needs an account.
> Evidence: trust-in-a-host, 4 reviews across 2 sources.

**B. Preview-proof links**
> For people who paste secrets into Slack and email, **OneShotLink** keeps the link
> alive through link previewers and mail scanners, so the secret is still there when
> the human opens it.
> Evidence: link-scanner theme, 2 reviews, 1 source — **thin**.

**C. No-account, no-trust sharing**
> For anyone sending a password to a client, **OneShotLink** needs no account on
> either end and no trust in an operator — run it yourself and it never leaves your
> infrastructure.
> Evidence: no-account strength + trust, 4 reviews.

**Recommendation: A**, with C folded into the hero line. It is the only angle backed
by more than one source, it matches what we already built (self-hostable, atomic
reveal, no-account guest flow), and it turns our weakest marketing truth — we are not
zero-knowledge (D-012) — into a credibility argument: state the threat model exactly
instead of implying more than we do. Option B is a genuine differentiator but is
currently backed by two reviews from one source; revisit after collecting more.

> Rule reminder: reviewer quotes are research, not testimonials. Do not put them on
> the landing page.
