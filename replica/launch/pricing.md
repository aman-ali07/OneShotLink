# Pricing — OneShotLink

Read 2026-11-11. Prices move; every row carries the URL and the date it was read, and
nothing here is from memory. **Nothing is on sale yet**: the managed tier is blocked on the
host gates (T-70/T-71 operator actions, see `PRODUCTION_READINESS.md`), and there is no
payment code in the app — the Stripe objects below are for a human to create.

## 1. What the category charges

| Product | Free tier | Entry paid tier | Higher tier | Source (read 2026-11-11) |
| --- | --- | --- | --- | --- |
| The original | Basic: $0/month | Identity Plus: **$35/month**, $356/year | Team Plus: **$125/month**, $1,200/year | <https://onetimesecret.com/en/pricing> |
| Bitwarden (Send is bundled, not sold separately) | Free: $0 | Premium: **$1.65/month**, $19.80/year | Families $3.99/mo; Teams $4/user/mo billed annually; Enterprise $6/user/mo | <https://bitwarden.com/pricing/> |
| Yopass | Open source, self-host | — no paid tier, no pricing page | — | <https://yopass.se/> (no price elements on the page) |
| PrivateBin | Open source, self-host | — no paid tier, no pricing page | — | <https://privatebin.info/> (no price elements on the page) |

What that says: the self-hosted OSS end of the category is **$0**, and the only paid money
in it is for *hosting plus branding/SSO*. The original's paid tiers buy custom domains,
branding and team governance — **none of which this app implements**, so copying their
price ladder would be selling features we do not have.

## 2. What reviewers said about price and billing

**Nothing.** In the 20-record sample (`replica/reviews.csv`, 3 sources) there is no
complaint about price, renewals or billing. The one price-adjacent comment praises a
competitor's "sensible pricing structure" — it is not about the original and it is not a
signal for us.

That is a gap in the evidence, not a green light: 20 records cannot tell you what people
will pay. Treat the numbers below as a starting hypothesis to test with the first ten
users, not as a validated model.

## 3. The model

Three things at most; named by who they are for. **Flat per instance, never per seat** —
per-seat jumps are the billing complaint that shows up in every category once a team
grows, and we have no per-seat cost to justify one.

| Tier | Who it is for | Price | What they get | Sellable today? |
| --- | --- | --- | --- | --- |
| **Community** | Anyone who will run a container | **$0** | The whole product: unlimited secrets, unlimited accounts, your own Redis, no licence fee, no seat cap, no telemetry, no upsell nag. Source-visible crypto. | Yes, as a repo — nothing to charge for |
| **Managed** | Teams who need it to just run | **$8/month**, or **$80/year** (two months free) | One instance we operate: TLS, Redis auth, daily backups, metrics, upgrades. Same app, no feature gating. | **No** — blocked on T-70/T-71 and the preflight gate passing on a real host |
| **Deployment review** (add-on, not a tier) | Self-hosters who want a second pair of eyes | **$300 one-off** | We read *their* deployment against `DEPLOYMENT.md` §4, run `script/preflight.sh` with them and write up what failed. No SLA attached. | Yes, once the preflight gate is proven on a non-synthetic host |

Why the managed tier is $8 and not $35: the original's $35 is priced for branding, custom
domains and identity — a product we do not have. $8 covers a small VPS plus a slice of
support and stops us from pricing a plain instance at a branding price. If it turns out
that support load makes it unprofitable, raise the price rather than invent gates.

Do **not** add: a per-seat tier, a "pro" tier that unlocks the passphrase or TTL options
(nothing in this app should be feature-gated — a security option behind a paywall is a
bad look for a tool whose whole argument is trust), or any "enterprise" tier before
`AUTH_MODE=full` exists.

## 4. Landing table (feeds `landing.md` §5)

| | Community | Managed | Deployment review |
| --- | --- | --- | --- |
| Price | $0 | $8/mo or $80/yr | $300 once |
| Where it runs | Your container, your Redis | Our instance | Your infrastructure |
| Secrets | Unlimited | Unlimited | — |
| Accounts | Unlimited, optional | Unlimited, optional | — |
| TLS, backups, upgrades | You | Us | We review yours |
| Branding, custom domains, SSO | Not implemented | Not implemented | Not implemented |

The last row stays in the public table. Hiding "not implemented" is how the original's
users ended up writing "for all I know they might be storing all my secrets in a public
txt file".

## 5. Billing rules we commit to before charging anyone

The sample had no billing complaints, so these are our own rules — cheap now, expensive
to retrofit:

1. **One-click cancel** in the dashboard, no email required, effective at the end of the
   paid period, with the exact end date shown.
2. **Renewal email 7 days before** every charge, to the account address, with the amount.
3. **Flat, per instance.** No seat counting, no overage, no usage metering.
4. **Annual is a discount, not a trap:** $80/year up front, shown as "$6.67/month billed
   annually" next to the $8/month option, never "only $6.67!" on its own.
5. **14-day refund** on request, no form, no questions.
6. **No card for Community.** Ever.
7. **Stripe Tax** on from the start so VAT/GST is not a manual chore.

## 6. Stripe objects for a human to create (test mode first)

| Product | Price | Amount | Interval | Notes |
| --- | --- | --- | --- | --- |
| OneShotLink Managed | `oneshotlink_managed_monthly` | $8.00 USD | monthly | Default option |
| OneShotLink Managed | `oneshotlink_managed_annual` | $80.00 USD | yearly | Two months free |
| OneShotLink Deployment Review | `oneshotlink_review_once` | $300.00 USD | one-off | No subscription; invoice manually until volume justifies checkout |

Not to be created until: preflight passes on a real host with a real certificate, the
restore drill is repeated on the target host, and `DEPLOYMENT.md` §4.1 has been run against
the live domain. Selling before that would be the "production ready" claim the brand rules
forbid.

## 7. What would change these numbers

- Support load on Managed above ~30 min/month per instance → raise to $15 or drop the tier.
- More than a third of signups asking for branding/custom domains → build it, then price it
  per the original's $35 as the ceiling.
- Repeated "can you host it for my team" with SSO in the ask → that is `AUTH_MODE=full`,
  the biggest open build, and it is a product decision (D-012 / M5), not a pricing one.
