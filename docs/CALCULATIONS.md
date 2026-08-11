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

> ## ⚠️ v3.0 (11-Aug-2026) — read this first
> The MG metric is **installs ÷ tech-assigned leads**:
> **numerator** = installs done, **denominator** = leads that reached *tech assigned*
> (`EXECUTOR_ID IS NOT NULL`), both from IEC. Source of truth:
> [`../sql/mg-metric.sql`](../sql/mg-metric.sql). So `pct`, `next_pct`, `needed` and the `screen`
> route all read `installs / denom`, and `installs` is also the pay base (`installpay` / `topup`).
> This **supersedes v2.0's on-time/M1 metric** (10-Aug) — late vs on-time no longer affects the
> percentage. The ledger view survives in the snapshot as `ontime_m1` / `late_m1` / `leads_m1`,
> **reference only**. Two implementation notes: `pct` rounds **half-up**, and `needed` uses the
> exact-integer form `ceil((3·denom − 5·installs)/2)` (the float form misreports — see CONTEXT.md).
> The IEC bucket rules below still govern `pending` / `committed` and remain the whole story for
> **frozen July**.

---

## 1. Raw inputs (what the backend returns)

```jsonc
{
  "userId":   "123456",          // CSP_USER.ID (the identity). mbg_id = zero-padded to 6.
  "installs": 7,                 // installed connections this month
  "denom":    14,                // customer-confirmed connections that reached an END STATE this month (= mbg_leads)
  "pending":  5,                 // all OPEN leads (the live pipeline)
  "committed": 2,                // OPEN leads whose CURRENT attempt has a customer-confirmed slot (⊆ pending; used by the almost screen's `needed`)
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
- `reached_slot  = MAX(CONFIRMED_SLOT_AT IS NOT NULL)`  ← "customer confirmed a slot" (sticky across attempts)
- `rep_ecid / offered = MAX_BY(EXECUTION_CANDIDATE_ID / CREATED_AT, UPDATED_AT)` — the
  representative (latest) attempt and its **CSP-offer date**
- `tech_assigned = MAX(TO_STATE='TECHNICIAN_ASSIGNED')` from
  `INSTALL_STATE_TRANSITION_LOG` joined on `rep_ecid` (IEC alone can't tell — a closed
  lead's `CURRENT_STATE` is already terminal, so this join is mandatory)
- **`gate_ok` (S4 hybrid denominator gate, 24-Jul):**
  `IFF(offered_IST <= 2026-07-16, reached_slot, tech_assigned)` — after ~22-Jul the
  customer's slot is auto-confirmed, so `reached_slot` stopped proving CSP engagement;
  connections offered ≥ 17-Jul need a technician assignment instead. The 16-Jul cutoff
  (~7 days before the product change) graces the in-flight tail.
- `own_slot_latest = MAX_BY(CONFIRMED_SLOT_AT, UPDATED_AT) IS NOT NULL`  ← the **current**
  attempt has a confirmed slot. NOT sticky: a connection retried after a failed
  slot-confirmed attempt correctly drops back to 0. Feeds `committed`.
- `last_date     = TO_DATE(DATEADD(minute, 330, MAX(UPDATED_AT)))`  (IST)
- **bucket** (first match wins): `installed` · `csp_denied` (DECLINED) · `csp_no_show`
  · `csp_abandoned` · `csp_timeout` (P41) · `cust_cancel_after_slot` ·
  `cust_cancel_before_slot` · `install_failed` · **`csp_retryx`**
  (`CANCELLED_BY_UPSTREAM AND REASON_CODE='RETRY_EXHAUSTION'` — re-assigned until the
  retry cap blew; ~72% of those attempts died as CSP no-show P74 / CSP timeout P41, so
  it counts **against** the CSP) · `system_other` · `cancelled_onsite` · else `open`.
  `csp_retryx` is matched **before** the `system_other` catch-all and is **not** in the
  exclusion set — slot-confirmed retry-exhaustion leads count in `denom`/`mbg_leads`.
  **`install_expired`** (`INSTALLATION_EXPIRED`, added 24-Jul): terminal end-state, not a
  phantom `open` lead — expiry with `last_date` in July counts in the denom (CSP-side
  miss), expiry before July is excluded by the terminal-in-July rule.

Then per CSP (`last_date >= MS`):

| Raw input | Count |
|---|---|
| `installs` | `bucket='installed' AND gate_ok=1` |
| `denom` (`mbg_leads`) | `gate_ok=1 AND bucket NOT IN ('open','system_other')` |
| `pending` | `bucket='open'` (whole live pipeline, incl. not-yet-confirmed) |
| `committed` | `bucket='open' AND own_slot_latest=1` (open leads that **will** mature) |

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
secured    if  denom > 0  and  installs / denom >= 0.60
almost     if  (installs + pending) >= 0.60 * total    // 60% still reachable via open pipeline
keepgoing  otherwise
```

| Screen | Meaning | Card colour |
|---|---|---|
| `noleads`   | no leads yet this month | idle (grey) |
| `secured`   | at or past 60% | green |
| `almost`    | not there yet, but reachable | amber |
| `keepgoing` | behind, at risk of closing < 60% | red |

---

## 3. Derived values (exact formulas)

| Value | Formula | Notes |
|---|---|---|
| `pct` | `round(100 * installs / denom)`, `0` if `denom==0` | `round` = **half-to-even** (Python). `1/8 → 12`, not 13. |
| `next_pct` | `round(100 * (installs+1) / (denom+1))` | rate if one more confirmed lead installs (an install adds to **both** installs and denom) |
| `needed` | **almost screen:** `max(1, ceil(0.60*(denom+committed)) - installs)` · **all other screens:** `max(1, ceil(0.60*total) - installs)` if `total>0` else `0` | ⚠️ the almost screen projects **only slot-confirmed open leads** (`committed`) into the denominator — those *will* mature; pre-slot leads may never confirm. Keep-going/secured/noleads keep the total-based formula. (`ceil` since the gate is now **≥ 60%** — hitting exactly 60% qualifies.) |
| `installpay` | `300 * installs`, comma-grouped (`"2,100"`) | Western grouping (Python `"{:,}"`) |
| `topup` | `max(0, 10000 - 300*installs)` | remaining ₹ to the guarantee floor |
| `days_left` | days remaining in the current **IST** calendar month | computed client-side in IST — see §5 |
| `month` | `"महीना " + max(1, IST_month - 6)` | **program** month, Jul=1 (NOT the calendar-month name) |
| `id` | `String(userId).padStart(6,'0')` | `mbg_id` |

### `needed`, worked

**Keep-going (total-based):** `installs=2, denom=11, pending=9` → `total=20`:
`needed = max(1, ceil(0.60*20) - 2) = max(1, 12-2) = 10`.

**Almost (committed-based) — Sai Cable (a0a6y4):** 6 installs / 10 matured (60%),
8 pending of which **2 committed** (open leads #9798, #e5f6 with confirmed slots):
- old: `ceil(0.60×(10+8))−6` = **5** ❌ — counted all 8 pending, including pre-slot
  leads the customer may never confirm
- new: `ceil(0.60×(10+2))−6` = **2** ✅ — only the leads that will actually mature

Check: after 2 more installs `(6+2)/(10+2) = 8/12 = 66.7% ≥ 60%` ✓ — `ceil(0.60×12) = 8`
installs is the poller's guaranteed-pass bar once both committed leads mature into the
denominator. (Note 6/10 = exactly 60% already qualifies under the ≥ 60% gate.)

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
- (ticket rows are informational only — no tap event / no navigation)
- `MBG_Click_<screen>` — back arrow ("Exit")

---

## 7. Worked examples (the sample CSPs in `index.html`)

| cspId | installs / denom / pending / committed | screen | pct | needed | next_pct | installpay | topup |
|---|---|---|---|---|---|---|---|
| 100001 | 7 / 14 / 5 / 5 | almost | 50% | 5 | 53% | ₹2,100 | ₹7,900 |
| 100005 | 7 / 14 / 5 / 2 | almost | 50% | 3 | 53% | ₹2,100 | ₹7,900 |
| 100002 | 9 / 12 / 3 / — | secured | 75% | 1 | 77% | ₹2,700 | ₹7,300 |
| 100003 | 2 / 11 / 9 / — | keepgoing | 18% | 11 | 25% | ₹600 | ₹9,400 |
| 100004 | 0 / 0 / 0 / — | noleads | — | 0 | — | ₹0 | ₹10,000 |

(`committed` only affects `needed` on the **almost** screen — compare 100001 vs 100005:
same pipeline, fewer slot-confirmed leads → smaller, truthful `needed`. `—` = unused.)

---

## 8. Going live — backend contract

Replace `getCspData()` with your authenticated endpoint. It must return the **raw**
inputs from §1 for the logged-in CSP:

```
GET /api/mbg/me            (session cookie identifies the CSP)
200 → { userId, installs, denom, pending, committed, tickets:[{no,area,cid}] }
```

Nothing else changes — routing, copy, and all numbers stay in `computeMBG()` /
`COPY[screen]`. Also: wire `track()` to your event pipeline. (Ticket rows are
informational only — no tap/navigation.)
