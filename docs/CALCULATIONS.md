# MBG / Kamai Kavach — Calculation Spec

Everything the banner (`index.html`) computes, and exactly how. This is the single
source of truth for the numbers; it mirrors the poller (`mbg_stage3_poller.py`,
Appendix A of [`mbg-poller-reference.md`](./mbg-poller-reference.md)).

**Golden rule:** the backend supplies only the **RAW** inputs. Every derived value
(screen, pct, needed, next_pct, installpay, topup, days_left, month, id) is computed in
`computeMBG()` so the logic lives in exactly one place. Do **not** pre-compute these on
the server and pass them in.

Constants: `PAY = 300` (₹ per install) · `GATE = 0.60` (60% target) · `FLOOR = 10000`
(₹ guarantee) · `MS = 2026-07-01` (program month start).

---

## 1. Raw inputs (what the backend returns)

```jsonc
{
  "userId":   "123456",          // CSP_USER.ID (the identity). mbg_id = zero-padded to 6.
  "installs": 7,                 // installed connections this month
  "denom":    14,                // customer-confirmed connections that reached an END STATE this month (= mbg_leads)
  "pending":  5,                 // all OPEN leads (the live pipeline)
  "tickets":  [                  // top-2 OPEN install tickets, already ranked
    { "no": "#8213", "area": "zone_012", "cid": "EXEC-CANDIDATE-0000-8213" },
    { "no": "#4419", "area": "zone_007", "cid": "EXEC-CANDIDATE-0000-4419" }
  ]
}
```

### Where the raw inputs come from (poller, Snowflake)
Source: `PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES`
(`_FIVETRAN_ACTIVE=TRUE`), aggregated **one row per (CONNECTION_ID, CSP_ID)** with
`MAX_BY(field, UPDATED_AT)`. Per connection:

- `has_installed = MAX(OTP_VERIFIED=TRUE OR INSTALLATION_COMPLETED_AT IS NOT NULL OR COMPLETED_STEP>=7)`
- `reached_slot  = MAX(CONFIRMED_SLOT_AT IS NOT NULL)`  ← "customer confirmed a slot"
- `last_date     = TO_DATE(DATEADD(minute, 330, MAX(UPDATED_AT)))`  (IST)
- **bucket** (first match wins): `installed` · `csp_denied` (DECLINED) · `csp_no_show`
  · `csp_abandoned` · `csp_timeout` (P41) · `cust_cancel_after_slot` ·
  `cust_cancel_before_slot` · `install_failed` · `system_other` · `cancelled_onsite` ·
  else `open`.

Then per CSP (`last_date >= MS`):

| Raw input | Count |
|---|---|
| `installs` | `bucket='installed' AND reached_slot=1` |
| `denom` (`mbg_leads`) | `reached_slot=1 AND bucket NOT IN ('open','system_other')` |
| `pending` | `bucket='open'` (whole live pipeline, incl. not-yet-confirmed) |

**OPEN install ticket** = `CURRENT_STATE IN` (ACCEPTED, AWAITING_SLOT_PROPOSAL,
SLOT_SELECTED, AWAITING_CUSTOMER_SLOT_CONFIRMATION, SLOT_CONFIRMED_BY_CUSTOMER,
SLOT_AUTO_CONFIRMED, AWAITING_TECHNICIAN_ASSIGNMENT, TECHNICIAN_ASSIGNED,
ARRIVED_AT_SITE, INSTALLATION_IN_PROGRESS_PRE_FEE, FEE_COLLECTION_PENDING,
INSTALLATION_IN_PROGRESS_POST_FEE, AWAITING_CUSTOMER_OTP). **Top-2 per CSP** by state
rank (ARRIVED_AT_SITE 8 > TECHNICIAN_ASSIGNED 7 > AWAITING_TECH 6 >
SLOT_CONFIRMED/AUTO 5 > AWAITING_CUST_SLOT 4 > SLOT_SELECTED 3 > AWAITING_SLOT_PROPOSAL
2 > else 1), then **oldest** `UPDATED_AT`.
Ticket fields: `no = "#" + RIGHT(EXECUTION_CANDIDATE_ID, 4)` · `area = ZONE_ID` ·
`cid = full EXECUTION_CANDIDATE_ID` (for the deep-link).

> **Identity:** `u.ID` from `DIM_CSP × CSP_USER` (`ROLE IN OWNER/MANAGER/MANAGER_PLUS`,
> `STATUS='ACTIVE'`) — **not** the cspid. For CleverTap segment uploads the CSV must
> contain userIds, never cspids.

---

## 2. Screen routing (`route()`)

`total = denom + pending`. Screens are **mutually exclusive** — a CSP is exactly one.

```
noleads    if  total == 0
secured    if  denom > 0  and  installs / denom > 0.60
almost     if  (installs + pending) > 0.60 * total     // 60% still reachable via open pipeline
keepgoing  otherwise
```

| Screen | Meaning | Card colour |
|---|---|---|
| `noleads`   | no leads yet this month | idle (grey) |
| `secured`   | already past 60% | green |
| `almost`    | not there yet, but reachable | amber |
| `keepgoing` | behind, at risk of closing < 60% | red |

---

## 3. Derived values (exact formulas)

| Value | Formula | Notes |
|---|---|---|
| `pct` | `round(100 * installs / denom)`, `0` if `denom==0` | `round` = **half-to-even** (Python). `1/8 → 12`, not 13. |
| `next_pct` | `round(100 * (installs+1) / (denom+1))` | rate if one more confirmed lead installs (an install adds to **both** installs and denom) |
| `needed` | `max(1, floor(0.60*total) + 1 - installs)` if `total>0` else `0` | ⚠️ uses **total (denom+pending)**, NOT denom |
| `installpay` | `300 * installs`, comma-grouped (`"2,100"`) | Western grouping (Python `"{:,}"`) |
| `topup` | `max(0, 10000 - 300*installs)` | remaining ₹ to the guarantee floor |
| `days_left` | days remaining in the current **IST** calendar month | computed client-side in IST — see §5 |
| `month` | `"महीना " + max(1, IST_month - 6)` | **program** month, Jul=1 (NOT the calendar-month name) |
| `id` | `String(userId).padStart(6,'0')` | `mbg_id` |

### `needed`, worked
For `installs=7, denom=14, pending=5` → `total=19`:
`needed = max(1, floor(0.60*19)+1 - 7) = max(1, 11+1-7) = 5`.
Check: `(7+5)/(14+5) = 12/19 = 63.2% ≥ 60% ✓`, and `(7+4)/(14+4) = 61.1%` (4 not enough at the confirmed rate — the poller's `floor(0.60*total)+1` accounts for open pending too).

---

## 4. Per-screen COPY (the only per-screen text)

Everything else — earnings card, ticket action card, ₹10,000 guarantee card, footer —
is **identical** across all four screens. Only the progress card's colour + these lines
differ (plus the earnings sub-line and the `%`/`—` for noleads).

| Screen | earn-sub | big % | headline (`wyh-need`) | sub-line (`wyh-line`) |
|---|---|---|---|---|
| **keepgoing** | `↑ हर नए कनेक्शन पर ₹300 · कोई ऊपरी सीमा नहीं` | `{pct}%` | `{needed} कनेक्शन और चाहिए` | `{denom} मिले · {installs} लगे = {pct}% · ऐसे ही चला तो महीना 60% से नीचे बंद होगा` |
| **almost** | `↑ हर नए कनेक्शन पर ₹300 · कोई ऊपरी सीमा नहीं` | `{pct}%` | `{needed} कनेक्शन और — 60% पार` | `{denom} मिले · {installs} लगे = {pct}% · अगला लगते ही {next_pct}%` |
| **secured** | `↑ हर नए कनेक्शन पर ₹300 · कोई ऊपरी सीमा नहीं` | `{pct}%` | `✓ 60% पार` | `{denom} मिले · {installs} लगे = {pct}% · नए कनेक्शन आने पर % बदल सकता है` |
| **noleads** | `0 कनेक्शन — पहला जल्द आएगा` | `—` (no %) | `गिनती पहले कनेक्शन से शुरू होगी` (green `#1d6b43`) | `व्योम कनेक्शन भेज रहा है — जो आए, उसी दिन लगाएं` |

Subheader (all screens): `{month} का हिसाब` · `इस महीने {days_left} दिन बाकी`.
Earnings amount (all screens): `₹{installpay}`.

---

## 5. IST calendar handling

`days_left` and `month` are **universal** (same for every CSP that day). They're computed
client-side in IST so they're always correct regardless of device timezone:

```js
var ist = new Date(Date.now() + 330*60000);            // shift UTC epoch → IST wall-clock
var im1 = ist.getUTCMonth() + 1;                        // 1-based IST month
var dim = new Date(Date.UTC(ist.getUTCFullYear(), im1, 0)).getUTCDate();  // days in IST month
var days_left = Math.max(0, dim - ist.getUTCDate());
var month     = 'महीना ' + Math.max(1, im1 - 6);       // program month (Jul=1)
```

Edge case that matters: a device at 20:00 UTC on 30 Jun is already 01:30 IST on 1 Jul —
the `+330` shift correctly rolls to July.

---

## 6. Events

Fired via `track(name)` (currently console-logged; wire to your analytics). The screen
suffix is the computed screen (`keepgoing`/`almost`/`secured`/`noleads`):

- `MBG_View_<screen>` — on load
- `MBG_Scroll_<screen>` — first scroll
- `MBG_SawTickets_<screen>` / `MBG_SawGuarantee_<screen>` — card ≥55% visible
- `MBG_TapGuarantee_<screen>` — guarantee card tapped (non-clickable; tap only tracked)
- `MBG_Ticket_<screen>` — a ticket row tapped (deep-link via `data-cid`, TBD)
- `MBG_Click_<screen>` — back arrow ("Exit")

---

## 7. Worked examples (the sample CSPs in `index.html`)

| cspId | installs / denom / pending | screen | pct | needed | next_pct | installpay | topup |
|---|---|---|---|---|---|---|---|
| 100001 | 7 / 14 / 5 | almost | 50% | 5 | 53% | ₹2,100 | ₹7,900 |
| 100002 | 9 / 12 / 3 | secured | 75% | 1 | 77% | ₹2,700 | ₹7,300 |
| 100003 | 2 / 11 / 9 | keepgoing | 18% | 11 | 25% | ₹600 | ₹9,400 |
| 100004 | 0 / 0 / 0 | noleads | — | 0 | — | ₹0 | ₹10,000 |

---

## 8. Going live — backend contract

Replace `getCspData()` with your authenticated endpoint. It must return the **raw**
inputs from §1 for the logged-in CSP:

```
GET /api/mbg/me            (session cookie identifies the CSP)
200 → { userId, installs, denom, pending, tickets:[{no,area,cid}] }
```

Nothing else changes — routing, copy, and all numbers stay in `computeMBG()` /
`COPY[screen]`. Also: wire `track()` to your event pipeline, and give ticket rows real
navigation using `data-cid`.
