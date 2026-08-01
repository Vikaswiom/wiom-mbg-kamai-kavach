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
| **Settlement (month-end) — the ONE dynamic screen** | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/settle.html?cspId=`<id>` |
| Pro-rata settlement (same logic, joiner-forward header) | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/settle-prorata.html?cspId=`<id>` |
| ₹750/install version | …/v750/  and  …/v750/settle.html?cspId=`<id>` |
| ₹1000/install version | …/v1000/  and  …/v1000/settle.html?cspId=`<id>` |
| Live data | …/data.json |
| **Frozen July payout data** | …/data-july.json |

`cspId` is the only variable, e.g. `settle.html?cspId=a0b8r0`. Preview cases without data:
`settle.html?case=above|topup|deep|noleads|below` or `?demo=1`.

### Month switching (Jul → Aug → Sep) — `?month=`
Every settle screen (settle, settle-prorata, v750/settle, v1000/settle) is **month-aware**:
`&month=july` (default) · `&month=aug` · `&month=sep`. It picks the month's frozen data file
(`data-july.json` / `data-aug.json` / `data-sep.json`), the month name in all copy, and the
days-in-month for pro-rata. So **August payout = the same URLs + `&month=aug`**, e.g.
`settle.html?cspId=X&month=aug`, `settle-prorata.html?cspId=X&joined=YYYY-MM-DD&month=aug`.
Each month's file is maintained live during that month then **auto-freezes** when the month ends
(see refresh.py per-month snapshot). `data-aug.json` first appears on **1 Aug**; before then the
`month=aug` URLs show "हिसाब अभी तैयार नहीं" for real cspIds (demo/`?case=` still work).

## Files
| File | Role |
|---|---|
| `index.html` | During-month banner (states: keepgoing/almost/secured/noleads). Reads live `data.json`. |
| `settle.html` | **Month-end settlement** — 5 outcome cases. Reads **`data-july.json`** (frozen). |
| `settle-prorata.html` | **Same overlay-driven logic as settle.html** (loads `csp-meta.json`, does pro-rata + two-tier), just with the joiner-forward header (`<month> का पहला हिसाब · <day> से जुड़े`) and pro-rata demo. `?cspId=X` auto-pulls the enrolment date & exact amount; full-month CSPs show ₹10,000 with no pro-rata card. `?joined=YYYY-MM-DD` / `?day=N` still work as manual overrides. Day-weighted base: `ceil(₹10,000 × active_days/days_in_month, to ₹100)` (19 Jul → ₹4,200; 25 Jul → ₹2,300). |

### DONE — per-CSP overlay (`csp-meta.json`) drives pro-rata + two-tier
Both former pending items are now **live in `settle.html`** via a static overlay `csp-meta.json`
(built from `MG pilot - Sheet10.csv`), merged client-side by cspId. **Use `settle.html?cspId=X`
for everyone** — it auto-applies each CSP's numbers:
- **Pro-rata floor** — if the CSP has a `joined` date in the displayed month, floor =
  `ceil(₹10,000 × active_days/days_in_month, to ₹100)`, and the दिनों-का-हिसाब card shows.
  (118 CSPs enrolled mid-July.)
- **Two-tier install pay** — if the CSP has `rate_after`+`switch`, earned =
  `300 × inst_before + rate_after × inst_after` (19 CSPs: 12 → ₹750 on 27 Jul, 7 → ₹1000 on
  28/30 Jul). The earned breakdown shows e.g. `10×₹300 + 6×₹750`. Other months: before the
  switch month → all ₹300; after → all at `rate_after`.

`csp-meta.json` shape: `{"meta":{ "<cspId>": {joined?, rate_before?, rate_after?, switch?, inst_before?, inst_after?} }}`.
It's **static** (refresh.py doesn't touch it; survives the data refresh). Built by re-running the
CSV→meta script (parses enrolment/change dates; queries Metabase for the 19 splits using the SAME
install definition as metrics.sql so counts reconcile).

**⚠️ Refinalize the 19 two-tier splits at freeze:** `inst_before`/`inst_after` were computed on
live data (installs still accruing today). Re-run the builder on the **frozen** `data-july.json`
(after 31 Jul 23:59) so the split reconciles exactly with the final install count. Enrolment dates
are static and need no refresh. (`v750/`, `v1000/` are now superseded flat-rate what-ifs — the real
per-CSP rate lives in `settle.html`.)
| `data.json` | Live per-CSP raw inputs `{installs, denom, pending, committed, tickets}`, refreshed by `refresh.py`. |
| `data-july.json` | **Frozen July snapshot** for the 1-Aug payout (see Freeze below). |
| `refresh.py` | Pulls `sql/metrics.sql` from Metabase → writes `data.json` (+ `data-july.json` while it's July). `--push` commits. |
| `sql/metrics.sql` | The Snowflake query (Metabase db 113). |
| `csp-meta.json` | **Per-CSP overlay** (static): `joined` (pro-rata) + two-tier rate split. Merged into settle.html by cspId. See DONE section above. |
| `v750/`, `v1000/` | Superseded flat-rate what-ifs (real per-CSP rate now lives in settle.html via csp-meta.json). |
| `analytics-dashboard/` | Separate internal dashboard (`data.js`, own `refresh.py`, own workflow). Not the CSP-facing screen. |

## Rules / config (in the JS of each page)
```
PAY   = 300      # ₹ per install
GATE  = 0.60     # INCLUSIVE: secured = installs/denom >= 0.60
FLOOR = 10000    # ₹ guarantee floor
DEEP  = 5000     # top-up above this = "बड़ी कमी" (deep shortfall) case
```
- **Gate is inclusive `>= 60%`** (ruling 1-Aug-2026, supersedes the 31-Jul strict ruling). A CSP at **exactly 60%** (e.g. 3/5, 6/10) **DOES** get the guarantee. Screen says "60% या अधिक चाहिए".
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
- `refresh.py build()` writes a **per-month snapshot** `data-<month>.json` for the CURRENT IST month (July→`data-july.json`, Aug→`data-aug.json`, Sep→`data-sep.json`). When the month rolls over it stops writing the old file → that month's **last write stays frozen**.
- `git_push()` commits `data.json` + every `data-*.json` (frozen months rewrite identically → no diff → not re-committed; only the current month changes).
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
