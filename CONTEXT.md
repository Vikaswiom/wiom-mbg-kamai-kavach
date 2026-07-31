# Kamai Kavach — Working Context (settlement + freeze)

Practical handoff so this project can be picked up on **any machine**. For the number
spec see [`docs/CALCULATIONS.md`](./docs/CALCULATIONS.md); this file is the *operational*
context (files, rules, deploy, gotchas) as of **31 Jul 2026**.

## Repo & deploy
- **Repo (public):** https://github.com/Vikaswiom/wiom-mbg-kamai-kavach
- **Clone:** `git clone https://github.com/Vikaswiom/wiom-mbg-kamai-kavach.git`
- **Hosting:** GitHub Pages off `main`. Push to `main` → Pages redeploys in ~1 min. No build step.
- **Private mirror** `Wiom-using-AI/wiom-mbg-kamai-kavach` exists but its Actions are **billing-blocked**; its cron schedules are commented out. The **public Vikaswiom repo is the live/production one.**

## Live URLs
| What | URL |
|---|---|
| Banner (during-month) | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/ |
| **Settlement (month-end)** | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/settle.html?cspId=`<id>` |
| **Pro-rata settlement (mid-month joiners)** | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/settle-prorata.html?cspId=`<id>`&joined=`YYYY-MM-DD` |
| ₹750/install version | …/v750/  and  …/v750/settle.html?cspId=`<id>` |
| ₹1000/install version | …/v1000/  and  …/v1000/settle.html?cspId=`<id>` |
| Live data | …/data.json |
| **Frozen July payout data** | …/data-july.json |

`cspId` is the only variable, e.g. `settle.html?cspId=a0b8r0`. Preview cases without data:
`settle.html?case=above|topup|deep|noleads|below` or `?demo=1`.

## Files
| File | Role |
|---|---|
| `index.html` | During-month banner (states: keepgoing/almost/secured/noleads). Reads live `data.json`. |
| `settle.html` | **Month-end settlement** — 5 outcome cases. Reads **`data-july.json`** (frozen). |
| `settle-prorata.html` | **Mid-month joiner** first settle — same cases but a **day-weighted base**: `ceil(₹10,000 × active_days/days_in_month, to ₹100)`. 19 Jul → 13/31 → ₹4,200; 25 Jul → 7/31 → ₹2,300. Adds the "पूरे ₹10,000 क्यों नहीं?" दिनों-का-हिसाब card + Aug–Sep full-guarantee promise. Join day from `?joined=YYYY-MM-DD` / `?day=N` / a `joined` field in data / default **19**. |

### PENDING — pro-rata join dates
`data.json` has **no per-CSP join date yet**, so `settle-prorata.html?cspId=X` alone assumes **19 Jul** for everyone. **Vikas will supply the exact joining date per CSP.** Once provided, two ways to make it correct per CSP (pick one):
1. **Per-CSP links** — build `settle-prorata.html?cspId=X&joined=YYYY-MM-DD` from the supplied list (works today, no pipeline change). Can also emit a CSV of cspId → join date → active_days → pro-rated base → outcome.
2. **Add `joined` to the data** — put each CSP's join date into `data.json`/`data-july.json` (via `metrics.sql` if the enrollment date is queryable, else a static lookup merged in `refresh.py`); then `?cspId=X` alone is correct. `settle-prorata.html` already reads a `joined` field if present.
| `data.json` | Live per-CSP raw inputs `{installs, denom, pending, committed, tickets}`, refreshed by `refresh.py`. |
| `data-july.json` | **Frozen July snapshot** for the 1-Aug payout (see Freeze below). |
| `refresh.py` | Pulls `sql/metrics.sql` from Metabase → writes `data.json` (+ `data-july.json` while it's July). `--push` commits. |
| `sql/metrics.sql` | The Snowflake query (Metabase db 113). |
| `v750/`, `v1000/` | Full banner+settle copies with PAY=750 / 1000 instead of 300. Read the root's absolute data files. |
| `analytics-dashboard/` | Separate internal dashboard (`data.js`, own `refresh.py`, own workflow). Not the CSP-facing screen. |

## Rules / config (in the JS of each page)
```
PAY   = 300      # ₹ per install
GATE  = 0.60     # STRICT: secured = installs/denom > 0.60  (NOT >=)
FLOOR = 10000    # ₹ guarantee floor
DEEP  = 5000     # top-up above this = "बड़ी कमी" (deep shortfall) case
```
- **Gate is strict `> 60%`** (ruling 31-Jul-2026). A CSP at **exactly 60%** (e.g. 3/5, 6/10) does **NOT** get the guarantee — they keep only their earned install money. Screen says "60% से अधिक चाहिए".
- FLOOR and GATE are **unchanged** in the v750/v1000 versions; only PAY differs.

## The 5 settlement cases (settle.html)
| # | Case (kase) | Title |
|---|---|---|
| 11 | `above` | बेस लागू नहीं — कमाई उससे ऊपर (installpay ≥ 10k) |
| 12 | `topup` | बेस लागू हुआ — व्योम ने बाकी दिया (secured, small top-up) |
| 13 | `deep` | बेस लागू हुआ — व्योम ने बाकी दिया (secured, top-up > ₹5000) |
| 14 | `noleads` | बेस लागू हुआ — पूरे ₹10,000 व्योम ने दिए (denom = 0) |
| 15 | `below60` | बेस इस महीने लागू नहीं (≤ 60%, earned money only) |

## July payout FREEZE (why data-july.json exists)
On 1 Aug the poller/query rolls to August, so live `data.json` would show August (~zero) numbers.
To keep the settle links showing **July's final settlement**:
- `refresh.py build()` also writes `data-july.json` **while the clock (IST) is still July**; on 1 Aug it stops → the **last July write stays frozen**.
- `git_push()` commits `data.json` + `data-july.json` together (in August the identical rewrite shows no diff, so July stays frozen).
- **`settle.html` + v750/v1000 read `data-july.json`, not `data.json`.**
- Timing-proof: the IST month boundary in `refresh.py` matches `metrics.sql`'s own, so `data-july.json` only ever holds July data. No midnight action needed.

*After July payout, to make settle show the current month again, point its `DATA_URL` + local fetch back to `data.json` (and rename the freeze month in `build()`).*

## Data pipeline / automation
- **GitHub Action** `.github/workflows/refresh-data.yml` runs `refresh.py --push` on a cron (Metabase secret `METABASE_API_KEY`). Green & healthy.
- **Metabase:** `https://metabase.wiom.in/api/dataset`, db `113` (Snowflake), header `x-api-key`.
- **Run refresh locally:**
  ```bash
  METABASE_API_KEY="<key>" python3 refresh.py        # writes data.json (+ data-july.json in July)
  # on this Mac the key is in Keychain:
  # security find-generic-password -s wiom-metabase-api-key -w
  ```
  Push happens via the normal `git push`; Pages redeploys. (`refresh.py --push` hard-syncs to origin/main first — run it only from a dedicated clone/CI, never mid-edit.)

## July 2026 payout snapshot (for reference)
- ~**694–696 CSPs**; **~300 qualify** (43%) for the guarantee (>60% secured or zero-lead floor); 394 below 60%.
- Guarantee top-up ≈ **₹26.6 L** + earned ≈ ₹5.87 L → **≈ ₹32.45 L** total wallet payout.
- **0** CSPs cleared the floor on installs alone (at ₹300 that needs 34 installs) → the base funds nearly the whole floor for most qualifiers.
- **`a0a0b1` is the TEST CSP — EXCLUDE it from any real money run.**

## Gotchas
- **Devanagari nukta** chars (ज़, ड़, ख़, फ़) are composed vs precomposed — plain `grep`/exact-string edits miss them. Use a **Python `str.replace`** with a nukta-free anchor for Hindi copy changes, and verify with `python3 -c "... 'phrase' in s"`.
- **GitHub Pages CDN** lags ~1–2 min after push; `raw.githubusercontent.com` also caches ~5 min. Verify against `git show origin/main:<file>` for the authoritative content.
- Pages allows ~10 builds/hour — `refresh.py` skips the push when data is unchanged.
- When scripting `git push` in a pipe, read **git's** exit code, not the pipe tail's.
