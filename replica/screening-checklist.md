# Name screening — what is left for a human

One page, for the operator or a trademark attorney. It follows B4 in
[deploy.md](deploy.md); the results of record live in [brand.md](brand.md) §2. Anything
already verified is listed here so nobody redoes it, and anything unrun names the blocker.

Screening is not clearance. This checklist narrows the field; it does not authorise spending
money on the name.

## Already verified (2026-11-12, from this repo's machine)

| Office / property | Query | Result | Control proving the search works |
| --- | --- | --- | --- |
| USPTO wordmark | `oneshotlink` | **No results found** | `verizon` → 177 results |
| EUIPO eSearch (EU trade marks) | `oneshotlink` | **Trade marks (0)**, "no results were found" | `verizon` → 27 trade marks |
| TMview (multi-office) | `oneshotlink` | **No rows found** | `verizon` → 71 results |
| CIPO (Canada) — owner name field | `oneshotlink` | **Results found: 0** | `verizon` → 50 results |
| US App Store | `OneShotLink` | no app named OneShotLink | Apple's own search returned fuzzy neighbours |
| Google Play (US) | `OneShotLink` | "No results for OneShotLink" | — (zero-result page is unambiguous) |
| `oneshotlink.com/.net/.app/.dev/.link` | RDAP | 404 at each registry | — |
| `oneshotlink.io` | DNS | `NXDOMAIN` | — |
| npm / PyPI / RubyGems | package APIs | 404 | — |
| GitHub `oneshotlink` user + org | API | 404 — free | — |

## To run by hand — paste the term, record the count

Use the bare term `oneshotlink` first, then the adjacent terms. Change nothing else.

1. **USPTO — adjacent marks.** <https://tmsearch.uspto.gov> → type `oneshot`, then
   `one shot link`. Automated requests stopped working after two queries this session, which
   is why these are still open. Record: live/registered counts and any mark in **class 9**
   (downloadable software) or **class 42** (SaaS, hosting, software as a service) that a
   buyer could confuse with this product.
2. **Canada — trade-mark name field.** <https://ised-isde.canada.ca/cipo/trademark-search/srch?lang=eng>
   → set the first criterion to **Trade-mark name** (the session above could only confirm the
   *Owner name* field) → `oneshotlink`. Record the count and any class 9/42 hits.
3. **WIPO Global Brand Database.** <https://branddb.wipo.int> → `oneshotlink`. Blocked here by
   an `altcha` CAPTCHA, so it is unrun. Record: international registrations naming the EU, US
   or Canada.
4. **TMview office coverage (optional).** <https://www.tmdn.org/tmview> → `oneshotlink`, then
   check the "Trade mark office" column on a control search to confirm which offices TMview
   includes. Its zero result cannot be read as covering Canada or WIPO until that is known.
5. **Handles.** X <https://x.com/oneshotlink>, Instagram
   <https://www.instagram.com/oneshotlink/>, TikTok <https://www.tiktok.com/@oneshotlink>,
   YouTube <https://www.youtube.com/@oneshotlink>, Reddit
   <https://www.reddit.com/user/oneshotlink>. All returned `200` or `403` to an automated
   client behind login walls, so none is confirmed free or taken. Record: taken / free.
6. **Open-web existence check.** Search `"OneShotLink"` and `"OneShotLink" secret sharing` in
   a browser. The agent's search provider failed on every attempt in both sessions, so this
   row is unrun. Record: any live product, repo or company using the name.

## Definition of done for B4

Every row above has a dated result in [brand.md](brand.md) §2 — including "no marks found",
which is itself the result — and a lawyer has searched classes 9 and 42 in the jurisdictions
where the instance will actually be operated. Then flip B4 in [deploy.md](deploy.md).
