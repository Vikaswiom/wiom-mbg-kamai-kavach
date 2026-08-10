# Kamai Kavach — Working Context (settlement + freeze)

Practical handoff so this project can be picked up on **any machine**. For the number
spec see [`docs/CALCULATIONS.md`](./docs/CALCULATIONS.md) and the payout ruleset
[`docs/MG-payout-logic.md`](./docs/MG-payout-logic.md); this file is the *operational*
context (files, rules, deploy, gotchas) as of **3 Aug 2026** — **July is closed & frozen
(`data-july.json`), August is live (`data-aug.json`).**

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
| Live data (current month = Aug) | …/data.json |
| **Frozen July payout data** | …/data-july.json |
| Live August snapshot | …/data-aug.json  (settle via `?month=aug`) |
| **Banner engagement dashboard** (team-shareable, auto-refresh) | https://vikaswiom.github.io/wiom-mbg-kamai-kavach/banner-dashboard.html |

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
| `index.html` | During-month banner. **4 standing modes** (progress-v3 "Standing के चार मोड़"): `almost` (1 और—60% पार) · `keepgoing` (रफ़्तार धीमी) · `secured` (60% पूरा) · `dropped` (60% से नीचे आए — needs a `new_leads` poller signal; `?case=almost\|keepgoing\|secured\|dropped\|noleads` previews all). Reads **live `data.json` = current month**. **Overlay-aware:** loads `csp-meta.json`; from the month AFTER a CSP's rate switch, installs pay their new rate (₹750/₹1000). Floor ₹10,000 (no Aug/Sep joiners). **Bottom row** "🗓️ पिछले महीने का हिसाब · <month>" shows last month's total (same settle logic) + links to `settle.html?cspId=X&month=<prev>` (Aug→July, Sep→Aug). |
| `settle.html` | **Month-end settlement** — 5 outcome cases. Reads **`data-july.json`** (frozen). |
| `settle-prorata.html` | **Same overlay-driven logic as settle.html** (loads `csp-meta.json`, does pro-rata + two-tier), just with the joiner-forward header (`<month> का पहला हिसाब · <day> से जुड़े`) and pro-rata demo. `?cspId=X` auto-pulls the enrolment date & exact amount; full-month CSPs show ₹10,000 with no pro-rata card. `?joined=YYYY-MM-DD` / `?day=N` still work as manual overrides. Day-weighted base: `round(₹10,000 × active_days/days_in_month)` to the rupee (19 Jul → ₹4,194; 25 Jul → ₹2,258). |

### DONE — per-CSP overlay (`csp-meta.json`) drives pro-rata + two-tier
Both former pending items are now **live in `settle.html`** via a static overlay `csp-meta.json`
(built from `MG pilot - Sheet10.csv`), merged client-side by cspId. **Use `settle.html?cspId=X`
for everyone** — it auto-applies each CSP's numbers:
- **Pro-rata floor** — if the CSP has a `joined` date in the displayed month, floor =
  `round(₹10,000 × active_days/days_in_month)` (to the rupee, per `docs/MG-payout-logic.md` §6), and the दिनों-का-हिसाब card shows.
  (118 CSPs enrolled mid-July.)
- **Two-tier install pay** — if the CSP has `rate_after`+`switch`, earned =
  `300 × inst_before + rate_after × inst_after` (19 CSPs: 12 → ₹750 on 27 Jul, 7 → ₹1000 on
  28/30 Jul). The earned breakdown shows e.g. `10×₹300 + 6×₹750`. Other months: before the
  switch month → all ₹300; after → all at `rate_after`.

`csp-meta.json` shape: `{"meta":{ "<cspId>": {joined?, rate_before?, rate_after?, switch?, inst_before?, inst_after?} }}`.
It's **static** (refresh.py doesn't touch it; survives the data refresh). Built by re-running the
CSV→meta script (parses enrolment/change dates; queries Metabase for the 19 splits using the SAME
install definition as metrics.sql so counts reconcile).

**✅ Two-tier splits FINALIZED against frozen July (3 Aug):** all 19 `inst_before`/`inst_after`
reconcile with `data-july.json`'s final `installs` (before+after == installs). Individual late-install
fixes landed as commits (a0b9r3 2+3→2+4, a0b7i2 zeroed — installs predated enrolment, a0b8o1 added).
The one non-match, a0b9j1, has 0 installs and is absent from the data — consistent. Enrolment dates
are static. (`v750/`, `v1000/` are superseded flat-rate what-ifs — the real per-CSP rate lives in
`settle.html`.)

**Retro re-run** (if a month's snapshot ever needs a rebuild on final data): `python refresh.py
--month july` rewrites ONLY `data-july.json` using July's window (the `{MS}`/`{ME}` DATE literals in
`metrics.sql` are substituted per `MONTH_WINDOW` in refresh.py); `data.json` (the live current-month
feed) is untouched.
| `data.json` | Live per-CSP raw inputs `{installs, denom, pending, committed, leads, ontime, late, tickets}`, refreshed by `refresh.py`. |
| `data-july.json` | **Frozen July snapshot** for the 1-Aug payout (see Freeze below). |
| `refresh.py` | Pulls `sql/metrics.sql` from Metabase → writes `data.json` (+ `data-july.json` while it's July). `--push` commits. |
| `sql/metrics.sql` | The Snowflake query (Metabase db 113). **Denom gate = `reached_slot=1`** (customer-confirmed-slot, payout-logic §3, Aug-2026) — the S4 hybrid slot/tech gate is retired. Aug denom ~2× vs S4 (auto-slot-confirm flow). **July was disbursed under S4 and is frozen — `refresh.py` BLOCKS `--month july`.** Banner "connections to 60%" uses §7b `ceil((0.6·denom−installs)/0.4)`. |
| `csp-meta.json` | **Per-CSP overlay** (static): `joined` (pro-rata) + two-tier rate split. Merged into settle.html by cspId. See DONE section above. |
| `v750/`, `v1000/` | Superseded flat-rate what-ifs (real per-CSP rate now lives in settle.html via csp-meta.json). |
| `analytics-dashboard/` | Separate internal dashboard (`data.js`, own `refresh.py`, own workflow). Not the CSP-facing screen. |
| `banner-dashboard.html` + `banner-data.json` | **Banner-engagement dashboard** (team-shareable). Reads `banner-data.json` (306/477 opened, opens, by payout outcome, daily trend), auto-re-checks every 5 min. `banner/fetch_banner.py` queries CleverTap `banner_opened` for the 477 (via `banner/banner-groups.json`); **`.github/workflows/refresh-banner.yml`** refreshes it hourly (`:27 UTC`). CleverTap `EVENTS_DATA.TIMESTAMP` is IST (no +330). |

## Rules / config (in the JS of each page)
```
PAY   = 300      # ₹ per install  (ALL installs — on-time AND late)
GATE  = 0.60     # INCLUSIVE: secured = ontime/leads >= 0.60   (v2.0, Aug-2026)
FLOOR = 10000    # ₹ guarantee floor
DEEP  = 5000     # top-up above this = "बड़ी कमी" (deep shortfall) case
```

### ⚠️ v2.0 (Aug-2026 onward) — the rate is the ON-TIME install rate
`docs/MG-payout-logic.md` §3.0 (source spec: `docs/BANNER-ontime-changes-v2.md`). Both sides of the
percentage now come from the app's own quality ledger `CSP_QUALITY_SERVICE…INSTALL_MATURATION_LEDGER`,
so MG scores a CSP with the same formula as the product's M1 / Installation Compliance card:

| Field in `data.json` | Meaning | Drives |
|---|---|---|
| `leads`  | `mbg_leads` — terminal outcomes where the **technician went onsite**: `ON_TIME_ACTIVE`, `LATE_ACTIVE`, `REPORTED_FAILED`, `CANCELLED_ONSITE`. Declines, customer cancels and **all** upstream cancels (P41 *and* P74) are OUT. | the % denominator, `needed`, the ≤2-lead floor |
| `ontime` | `mbg_ontime` — `ON_TIME_ACTIVE` (installed on/before the slot day) | the % numerator, `pct`/`next_pct`, the 60% gate, the "Y लगे" number |
| `late`   | `mbg_late` — `LATE_ACTIVE`. **Earns its rate, doesn't move the %** (copy says so). | the "N देर से लगे" note |
| `installs` | ALL installs (on-time + late), IEC-derived — **unchanged** | `installpay` / `topup` **only** |
| `denom` | the v1 denominator — **kept only for back-compat** | frozen July snapshots |

- **Window = calendar month on `TERMINAL_AT` (IST).** The app's M1 card is **60-day rolling**, so a
  CSP's app % will NOT equal the banner %. Expected — don't "fix" it. Verified: `a0b9x8` on 10-Aug =
  app 24/28 (86%, rolling) vs banner 10/14 (71%, August).
- **Frozen July is safe:** `data-july.json` has no `leads`/`ontime`, and every screen falls back to
  `denom`/`installs` when they're absent — July renders exactly as it was disbursed. Same for
  `v750/`, `v1000/` (July-only, superseded, left on v1).
- **Impacted-booking phones** (§3.0): `sql/metrics.sql` has an **empty `impacted` CTE** — paste the
  connection ids in to activate the drop-unless-installed rule. No list supplied yet → currently a no-op.
- **Gate is inclusive `>= 60%`** (v2.0: on the **on-time** rate `ontime/leads`) (ruling 1-Aug-2026, supersedes the 31-Jul strict ruling). A CSP at **exactly 60%** (e.g. 3/5, 6/10) **DOES** get the guarantee. Screen says "60% या अधिक चाहिए".
- **≤ 2 leads → floor-protected** (`docs/MG-payout-logic.md` §7, replaced the old 0-leads-only rule): `denom <= 2` is floor-eligible regardless of rate — top-up = `max(0, floor − install money)`. `denom === 0` keeps the `noleads` copy; `denom` 1–2 shows the new `fewleads` case.
- FLOOR and GATE are **unchanged** in the v750/v1000 versions; only PAY differs.

## The 5 settlement cases (settle.html)
| # | Case (kase) | Title |
|---|---|---|
| 11 | `above` | बेस लागू नहीं — कमाई उससे ऊपर (installpay ≥ 10k) |
| 12 | `topup` | बेस लागू हुआ — व्योम ने बाकी दिया (secured, small top-up) |
| 13 | `deep` | बेस लागू हुआ — व्योम ने बाकी दिया (secured, top-up > ₹5000) |
| 14 | `noleads` | बेस लागू हुआ — पूरे ₹10,000 व्योम ने दिए (denom = 0) |
| 14b | `fewleads` | बेस लागू हुआ — व्योम ने बाकी दिया (denom 1–2, floor-protected) |
| 15 | `below60` | बेस इस महीने लागू नहीं (< 60% with ≥ 3 leads, earned money only) |

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
