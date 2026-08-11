# MG Install Payout — Calculation Logic

**Version:** 3.0 · **Date:** 11-Aug-2026 · **Owner:** Shariq · **For:** Vikas / Design + Eng (payment build)
*(v1.0 = 31-Jul-2026. **v2.0 applies from the AUGUST month onward**; July was disbursed under v1.0 and is frozen.)*

> **v3.0 headline (11-Aug-2026) — the rate is `installs ÷ tech-assigned leads`.**
> **Numerator** = installs done. **Denominator** = leads that reached *tech assigned*
> (`EXECUTOR_ID IS NOT NULL`). Both from the execution service (IEC). Pay is unchanged
> (rate × installs). Authoritative query: [`../sql/mg-metric.sql`](../sql/mg-metric.sql).
> **This replaces v2.0's ON-TIME metric** (§3.0 below, 08-Aug) — a late install now counts in
> the numerator like any other, so on-time no longer changes anyone's percentage.
> Verified: installs are a strict subset of tech-assigned (0 installs without an executor).

This document is **self-contained**: anyone can compute any enrolled CSP's MG payout from the rules below.
It covers the three changes locked on 31-Jul-2026:
1. **Pro-rata guarantee** by enrollment date
2. **Floor for ≤2 leads** (not just 0 leads)
3. **Variable per-install rate** — ₹300 default, ₹750 / ₹1000 for selected CSPs on **all future installs**

---

## 0. One-line summary

> **Total payout = Installation money + Top-up**, where
> **Installation money** = Σ (per-install rate) over the CSP's installs, and
> **Top-up** = `max(0, pro-rata guarantee − installation money)` **only if** the CSP is *floor-eligible*
> (≤ 2 leads **or** **on-time** install rate ≥ 60 % — v2.0, §3.0). Otherwise top-up = 0.

Everything below is just the precise definition of each term.

---

## 1. Universe — who is paid

Enrolled **Install-MG** CSPs. **Currently 477** (442 Flow-1 + 35 Flow-2).

- **Flow 1** = eligible + audit already done → **enrolled = the day they opted in**.
- **Flow 2** = eligible + audit pending → **enrolled = the day their audit was completed** (opt-in alone is not enough).

> *Note on 476 vs 477:* the count moves by ±1 as CSPs opt in. 476 was the 28-Jul snapshot; one more Flow-1 CSP opted in after, so it is 477 as of 31-Jul. Always recompute the enrolled set at payout time.

---

## 2. Enrollment date (per CSP)

| Flow | Enrollment date |
|---|---|
| Flow 1 | `MIN(first_opted_at)` from `mg_optins` where `program='MG'` |
| Flow 2 | `MAX(scan_complete_at)` from `campaign_partners` for the MG campaign |

Convert to **IST date** (`YYYY-MM-DD`). All 477 current enrollment dates are in **July 2026**.

---

## 3.0 ~~v2.0 (08-Aug) — the ON-TIME metric~~ · **SUPERSEDED by v3.0, kept for history**

From the August payout, both sides of the rate come from the app's own quality ledger
`PROD_DB.CSP_QUALITY_SERVICE_CSP_QUALITY_SERVICE.INSTALL_MATURATION_LEDGER`, so MG scores a CSP
with exactly the formula the product's M1 (Installation Compliance) card uses.

**Denominator (`mbg_leads`)** — a lead counts **only if the technician actually went onsite**,
i.e. **only** these four terminal outcomes:

| `TERMINAL_OUTCOME` | Meaning | In denom | In numerator |
|---|---|---|---|
| `ON_TIME_ACTIVE` | installed on/before the slot day | ✅ | ✅ |
| `LATE_ACTIVE` | installed after the slot day | ✅ | ❌ (still **paid**) |
| `REPORTED_FAILED` | technician onsite, install failed | ✅ | ❌ |
| `CANCELLED_ONSITE` | cancelled at the door | ✅ | ❌ |

**Everything else is excluded:** declines (`csp_denied`), customer cancellations
(`CUSTOMER_CANCELLED`), and **ALL** upstream cancels — `UPSTREAM_CANCEL_PRE_CONFIRM` (P41, before
tech) **and** `UPSTREAM_CANCEL_POST_CONFIRM` (P74 / no-show, after tech) — plus never-slot-confirmed
and still-open leads. There is **no before/after-tech split** any more (that was a v2.0 draft rule).

**Numerator = ON-TIME installs only** — `TERMINAL_OUTCOME = 'ON_TIME_ACTIVE'`, i.e.
`INSTALLATION_COMPLETED_AT` (IST date) `<= CONFIRMED_SLOT_DATE`. A **late** install adds to the
denominator without moving the numerator, so it **pushes the % DOWN** while still earning its rate.

**Impacted-booking phones:** drop from `mbg_leads` unless that connection was installed.
*(No impacted list has been supplied yet — `sql/metrics.sql` carries an empty `impacted` CTE, so
this rule is currently a no-op. Paste connection ids there to activate it.)*

**⚠️ Window = the calendar MONTH (month-to-date) on `TERMINAL_AT` (IST) — NOT the app's 60-day
rolling window.** The product app's M1 card is 60-day rolling, so **the % a CSP sees in the app will
not match the banner** — same formula, different clock. Verified example: **DH Cable (`a0b9x8`),
10-Aug — app 24/28 = 86 % (rolling) vs banner 10/14 = 71 % (August).** This is expected; don't
"fix" it. (Switching MG to rolling would be a separate product decision.)

**Install money** counts `ON_TIME_ACTIVE + LATE_ACTIVE` **from the same ledger** — so one table
drives leads, the %, and the money, and the per-CSP mismatch against the old IEC install count
(which differed for ~40% of CSPs, in both directions) is gone. Ledger rows are deduped to **one per
CONNECTION**, latest terminal event winning. Authoritative query: [`../sql/ontime-m1.sql`](../sql/ontime-m1.sql)
(received 10-Aug-2026); `sql/metrics.sql` reproduces it per-CSP and is what the pipeline runs.

**Unchanged by v2.0:** per-install *rate* (§5 — every install pays, late included), pro-rata floor (§6),
≤2-lead floor protection (§7, now counted on `mbg_leads`), the ≥60 % gate itself (§7, inclusive),
and the payout formula (§8).

---

## 3. "CSP ko kitne leads mile" (the Denominator) — leads that reached AWAITING_TECHNICIAN_ASSIGNMENT (customer confirmed a slot)

**FINAL rule (Aug-2026):** a lead counts once **the customer has confirmed a slot** — i.e. it reached **`AWAITING_TECHNICIAN_ASSIGNMENT`** (equivalently `CONFIRMED_SLOT_AT IS NOT NULL`; the poller already computes this as `reached_slot=1`). In the new booking flow the **customer picks the slot at the time of booking**, so **~90% of leads reach this the instant they're offered** — they cascade `ASSIGNED → AWAITING_CUSTOMER_SCHEDULE → SLOT_CONFIRMED_BY_CUSTOMER → AWAITING_TECHNICIAN_ASSIGNMENT` in the same second. From there the CSP's job is to **assign a technician and install**.

Grain = **one row per (connection × CSP)**.

A lead **counts in the denominator** if **ALL** of these are true:

1. **The customer confirmed a slot** — the lead reached **`AWAITING_TECHNICIAN_ASSIGNMENT`** (or any later stage); `CONFIRMED_SLOT_AT IS NOT NULL`. *(This is the bar — **NOT** bare "offered", and **NOT** "technician assigned".)*
2. **Terminal (closed):** the lead reached an end-state — *not still open / in-progress*.
3. **Closed on/after the CSP's enrollment date** and within the payout month (`enrollment_date ≤ terminal_date ≤ month_end`).
4. Its end-state is **not a system/upstream cancel** (not the CSP's fault).

### 3a. The bar = customer confirmed a slot (reached AWAITING_TECHNICIAN_ASSIGNMENT)
- **Too loose ("just offered")** would charge the CSP for leads the customer never committed to; **too strict ("technician assigned")** let CSPs dodge by never assigning a tech. **"Customer confirmed a slot"** is the middle ground: the customer is committed and it's now squarely on the CSP to install.
- **Includes:** the ~90% of leads that arrive slot-confirmed at booking, plus any that confirm later.
- **Excludes: the ~10% "no-slot" leads** — customer never confirmed a slot (CSP declined / timed-out **before** any slot). The CSP is **not charged** for a lead the customer never committed to.
- History: this is effectively the pre-S4 `reached_slot=1` rule, brought back because the new flow makes slot-confirmation automatic at booking.

### 3b. Which leads COUNT vs are EXCLUDED
*Among leads that reached slot-confirmed (`AWAITING_TECHNICIAN_ASSIGNMENT`), the terminal outcome decides:*

| End-state | In denom? |
|---|---|
| Installed | ✅ (also the numerator) |
| CSP declined (after slot confirmed) | ✅ counts (CSP miss) |
| CSP no-show (P74) / abandoned | ✅ counts (CSP miss) |
| CSP timed out (P41) | ✅ counts (CSP miss) |
| **Retry-exhaustion** (`CANCELLED_BY_UPSTREAM` + `RETRY_EXHAUSTION`) | ✅ counts |
| Install attempt failed / cancelled on-site / install expired | ✅ counts (CSP miss) |
| Customer cancelled **after** confirming a slot | ✅ counts |
| **Never reached slot-confirmed** (no customer slot; declined/timed-out before any slot) | ❌ **excluded** — customer never committed (`reached_slot=0`) |
| Customer cancelled **before** confirming a slot | ❌ excluded (`reached_slot=0`) |
| **System / upstream cancel** (any other `CANCELLED_BY_UPSTREAM`) | ❌ excluded (not the CSP's fault) |
| Still open / in-progress | ❌ not counted (pending, not yet resolved) |

---

## 4. Installs (the Numerator) — counted **since enrollment**
> ⚠️ **v1.0 (July only).** From August the numerator is **on-time installs** off the M1 ledger — see §3.0.
> This definition still drives the **pay** side (all installs, on-time + late) in every month.

An **install** = the connection reached installed state:
`OTP_VERIFIED = TRUE` **OR** `INSTALLATION_COMPLETED_AT` is set **OR** `COMPLETED_STEP ≥ 7`,
with its terminal date on/after enrollment (same window rule as §3).

**Install rate = Installs ÷ Denominator.**

---

## 5. Per-install rate — ₹300 / ₹750 / ₹1000

- **Default = ₹300 per install.**
- **Selected CSPs** (from *Project Dominance - CSPs*, column `Cluster Plan` = 750 or 1000, with a filled `Dates for MG`) are paid **₹750 or ₹1000 per install** for **every install completed on/after their effective date — this is permanent, for all future installs (not just July).**
- For a selected CSP, installs completed **before** the effective date are still ₹300; installs **on/after** it are at the new rate.

**Installation money = Σ over the CSP's installs of the applicable per-install rate.**
```
per_install_rate(install) =
    higher_rate   if CSP is selected AND install_completion_date >= effective_date
    300           otherwise
```

### 5a. Selected CSPs (as of 31-Jul-2026)

**₹750 — effective 27-Jul-2026** (12 Install-MG CSPs):
OSHO Industries (281749854653887), S R NETWORK (281749855031856), Anitel (274877929231),
Vineet Cable TV Network (281749854621989), Pragati Communication (281749854661873),
Deepak Arora (281749854710805), J.D INTERNET SERVICES (281749854653867), XD Network (281749854683887),
AIRMAX HYPERNET TECHNOLOGIES (281749854681139), Poorvi Internet Services (281749854635402),
SPEEDNET BROADBAND (281749854760096), Sainet Communication-Chandra Park (281749854688608).

**₹1000 — effective 28-Jul-2026** (5): Ansari Cable Network (274877926490),
Parcha Fiber Broadband & Cable Network (274877945992), Netfizz Network Pvt Ltd (274877953156),
Choudhary Broadband - Ganesh Nagar (274877928483), Speedplus Chilla (281749854680365).

**₹1000 — effective 30-Jul-2026** (2): Super Broadband (281749854645087), Sumit broadband (281749854637047).

*(6 more selected CSPs — Capital Cable, SR Network 281749854625097, Lifeline Internet, K P INTERNET 1 Services, Aditya Digital, Deepali Communication — are Sehat-MG / not in the Install-MG cohort, so they are not in this Install-MG payout, but they DO get ₹750/₹1000 on their installs under the same rule.)*

> **The selected list is driven by the `Project Dominance - CSPs` sheet — always read `CSP ID`, `Cluster Plan` (rate), and `Dates for MG` (effective date) live from there; do not hardcode.**

---

## 6. Pro-rata MG guarantee (the floor amount)

Base guarantee = **₹10,000 / month**, **pro-rated by enrollment date** — a CSP only earns the guarantee for the days they were enrolled that month.

```
eligible_days   = days_in_month − day_of(enrollment_date) + 1     # inclusive of the enrollment day
pro_rata_guarantee = round( 10000 × eligible_days / days_in_month )
```

For **July (31 days)**:
| Enrolled on | Eligible days | Guarantee |
|---|---|---|
| 1-Jul | 31 | **₹10,000** (full) |
| 10-Jul | 22 | **₹7,097** |
| 20-Jul | 12 | ₹3,871 |
| 25-Jul | 7 | ₹2,258 |
| 31-Jul | 1 | ₹323 |

> A CSP enrolled **before** the month starts (future months) gets the **full ₹10,000** for that month.

---

## 7. Floor eligibility — who actually gets the guarantee

A CSP is guaranteed the (pro-rata) floor if **either**:
- **≤ 2 leads** — `denominator ("CSP ko kitne leads mile") ≤ 2` → few leads, not their fault, so protected. *(This replaced the old "0 leads" rule.)*
- **Secured** — `install rate ≥ 60 %` (needs ≥ 3 leads to qualify here) → performed, so protected.

Otherwise (**≥ 3 leads AND rate < 60 %**) = **piece-rate only**, no guarantee.

---

## 7b. "How many more connections to reach 60%" — the CSP banner (FIX: denominator grows!)

**Bug being fixed:** the app currently computes "X more connections needed" against a **fixed denominator**, which is wrong. Every new install is **also a new lead**, so the denominator grows with each one.

- **Wrong (current app):** `needed = ceil(0.60 × denom) − installs`. For 9 installed / 17 leads → `ceil(10.2) − 9 = 2`. **This is misleading** — if he installs 2 more it becomes **11 / 19 = 58 %**, still under 60 %.
- **Correct formula** — solve `(installs + n) / (denom + n) ≥ 0.60` for the minimum `n` (assuming each new lead installs):

```
n = CEIL( (0.60 × denom − installs) / (1 − 0.60) )
  = CEIL( (0.60 × denom − installs) / 0.40 )
```

**Worked example (9 installed / 17 leads):** `(0.60 × 17 − 9) / 0.40 = (10.2 − 9) / 0.40 = 3`.
→ **He needs 3 more (12 / 20 = 60 %)**, not 2. (And that assumes he installs *every* new lead; if any of the next leads miss, he needs more — 5 straight installs → 14 / 22 = 64 % gives comfortable headroom.)

**v2.0:** the same formula, on the on-time numbers — `n = ceil((0.6·leads − ontime)/0.4)`, where
`leads`/`ontime` are §3.0's. Phrase it *"install your next N connections **on time**"*: a late install
grows the denominator only, so it moves the target **further away**.

**Banner rule of thumb:** always compute with the **growing denominator** (`n = ceil((0.6·denom − installs)/0.4)`), and phrase it as *"install your next N connections"* — never a fixed "N more," because a mix of installs + misses only pushes the target further away.

---

## 8. Final payout formula

```
installation_money = Σ per_install_rate(install)          # §5
pro_rata_guarantee = §6
floor_eligible     = (denom <= 2) OR (rate >= 0.60)        # §7

top_up = max(0, pro_rata_guarantee − installation_money)  if floor_eligible
         0                                                 otherwise

TOTAL PAYOUT = installation_money + top_up
             = max(installation_money, pro_rata_guarantee) if floor_eligible
             = installation_money                          otherwise
```

---

## 9. Worked examples

| CSP | Enrolled | Denom | Installs (rate split) | Guarantee | Install money | Bucket | Top-up | **Total** |
|---|---|---|---|---|---|---|---|---|
| A K Cable | 1-Jul | 15 | 13 @ ₹300 | ₹10,000 | ₹3,900 | Secured 87% | ₹6,100 | **₹10,000** |
| AAA Network | 1-Jul | 1 | 0 | ₹10,000 | ₹0 | ≤2 leads | ₹10,000 | **₹10,000** |
| Meghna Enterprises | 1-Jul | 27 | 15 @ ₹300 | ₹10,000 | ₹4,500 | Piece-rate 56% | ₹0 | **₹4,500** |
| OSHO Industries | 1-Jul | 20 | 16 (10@₹300 + 6@₹750) | ₹10,000 | ₹7,500 | Secured 80% | ₹2,500 | **₹10,000** |
| Poorvi Internet | 1-Jul | 16 | 9 (5@₹300 + 4@₹750) | ₹10,000 | ₹4,500 | Piece-rate 56% | ₹0 | **₹4,500** |
| XD Network | 25-Jul | 0 | 0 | ₹2,258 | ₹0 | ≤2 leads | ₹2,258 | **₹2,258** |

---

## 10. Data sources

| Item | Source |
|---|---|
| **v2.0 leads + on-time installs (Aug onward)** | `PROD_DB.CSP_QUALITY_SERVICE_CSP_QUALITY_SERVICE.INSTALL_MATURATION_LEDGER` — `TERMINAL_OUTCOME` (4 onsite outcomes = denom; `ON_TIME_ACTIVE` = numerator), windowed on `TERMINAL_AT` (IST) within the calendar month. One row per terminal attempt. |
| Leads / installs / states | `PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES` — one row per (connection × CSP). Per connection: `MAX_BY(CURRENT_STATE, UPDATED_AT)`; installed = OTP / INSTALLATION_COMPLETED_AT / COMPLETED_STEP≥7. |
| **Denominator gate = customer confirmed a slot** | `reached_slot = MAX(CONFIRMED_SLOT_AT IS NOT NULL)` per (connection × CSP) = the lead reached `AWAITING_TECHNICIAN_ASSIGNMENT`. **Only `reached_slot=1` leads count.** (Technician-assigned, `INSTALL_STATE_TRANSITION_LOG.TO_STATE='TECHNICIAN_ASSIGNED'`, is a later funnel milestone — shown but NOT the denom bar.) |
| Terminal / install date | `TO_DATE(DATEADD(minute,330, MAX(UPDATED_AT)))` (IST); install completion = `INSTALLATION_COMPLETED_AT` |
| partner_id ↔ csp_id | `PROD_DB.CSP_GATEWAY_SERVICE_CSP_GATEWAY_SERVICE.CSP_ACCOUNT` |
| Enrollment date | Supabase `mg_optins.first_opted_at` (Flow 1) · `campaign_partners.scan_complete_at` (Flow 2) |
| Per-install rate (750/1000) | Google Sheet **Project Dominance - CSPs** → `CSP ID`, `Cluster Plan`, `Dates for MG` |

Constants: `MONTH_FLOOR = 10000`, `BASE_RATE = 300`, `RATE_GATE = 0.60` (v2.0: the ≥60% **on-time** install-rate bar for "Secured"). **Denominator gate = `reached_slot=1` (customer confirmed a slot / reached `AWAITING_TECHNICIAN_ASSIGNMENT`).** *(The S4 hybrid slot/tech gate is retired.)*

---

## 11. July-settlement totals (AS DISBURSED — old S4 tech-assigned gate)

> ⚠️ **These July numbers were computed & paid under the OLD S4 hybrid gate** (confirmed-slot for offers ≤16-Jul, technician-assigned for ≥17-Jul). They are frozen — the disbursement is final. The **new denominator (§3) — customer confirmed a slot / reached `AWAITING_TECHNICIAN_ASSIGNMENT` — applies from August onward.**

Leads terminal ≤ 31-Jul 23:59 IST · 477 CSPs · rate gate = ≥60%:

| Metric | Value |
|---|---|
| Installs (since enrollment) | 1,594 |
| Installation money | ₹4,90,250 |
| Top-up money | ₹27,93,982 |
| **Total payout** | **₹32,84,232** |
| Floor-eligible | 334 (≤2 leads 181 + Secured 153) |
| Piece-rate only | 143 |
| Higher-rate installs (750/1000) | 24 → +₹12,050 vs flat ₹300 |

Live per-CSP numbers: **MG pilot sheet → tab "MG Payout (prorata)"**.
