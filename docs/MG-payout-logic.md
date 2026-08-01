# MG Install Payout — Calculation Logic

**Version:** 1.0 · **Date:** 31-Jul-2026 · **Owner:** Shariq · **For:** Vikas / Design + Eng (payment build)

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
> (≤ 2 leads **or** install-rate > 60 %). Otherwise top-up = 0.

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

## 3. "CSP ko kitne leads mile" (the Denominator) — counted **since enrollment**

Grain = **one row per (connection × CSP)** — every install task offered to the CSP.

A lead **counts in the denominator** if **ALL** of these are true:

1. **Terminal (closed):** the lead reached an end-state (installed or finally cancelled) — *not still open / in-progress*.
2. **Closed on/after the CSP's enrollment date** and within the payout month (`enrollment_date ≤ terminal_date ≤ month_end`). *Leads that closed before the CSP enrolled do NOT count.*
3. **Passes the S4 engagement gate** (see §3a).
4. Its end-state is **not** `system/upstream cancel` (see §3b).

### 3a. S4 engagement gate (keyed on the CSP-offer / task-creation date)
- Task **offered ≤ 16-Jul** → counts only if the **customer confirmed a slot**.
- Task **offered ≥ 17-Jul** → counts only if a **technician was assigned**.
- *(Reason: after ~22-Jul customer slot-confirmation became automatic, so "confirmed slot" no longer proves the CSP engaged — "technician assigned" is the new proof. Cutoff set to 16-Jul, ~7 days before the change, to grace the in-flight tail.)*

### 3b. Which cancelled tasks COUNT vs are EXCLUDED

| End-state | In denom? |
|---|---|
| Installed | ✅ (also the numerator) |
| CSP declined the lead | ✅ counts (CSP miss) |
| CSP no-show (P74) / abandoned | ✅ counts (CSP miss) |
| CSP timed out (P41) | ✅ counts (CSP miss) |
| **Retry-exhaustion** (`CANCELLED_BY_UPSTREAM` + `RETRY_EXHAUSTION`) | ✅ **counts** (CSP miss — re-assigned repeatedly until the retry cap; ~72 % died from CSP no-show/timeout) |
| Install attempt failed / cancelled on-site / install expired | ✅ counts (CSP miss) |
| Customer cancelled **after** confirming a slot | ✅ counts |
| Customer cancelled **before** confirming a slot | ❌ excluded (fails the gate) |
| **System / upstream cancel** (any other `CANCELLED_BY_UPSTREAM`) | ❌ excluded (not the CSP's fault) |
| Still open / in-progress | ❌ not counted (pending) |

---

## 4. Installs (the Numerator) — counted **since enrollment**

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
- **Secured** — `install rate > 60 %` (needs ≥ 3 leads to qualify here) → performed, so protected.

Otherwise (**≥ 3 leads AND rate ≤ 60 %**) = **piece-rate only**, no guarantee.

---

## 8. Final payout formula

```
installation_money = Σ per_install_rate(install)          # §5
pro_rata_guarantee = §6
floor_eligible     = (denom <= 2) OR (rate > 0.60)         # §7

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
| Leads / installs / states | `PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES` (per connection: `MAX_BY(CURRENT_STATE, UPDATED_AT)`; installed = OTP/ INSTALLATION_COMPLETED_AT / COMPLETED_STEP≥7; slot = CONFIRMED_SLOT_AT) |
| Technician-assigned (S4 gate) | `…INSTALL_STATE_TRANSITION_LOG`, `TO_STATE='TECHNICIAN_ASSIGNED'` on the connection's representative candidate |
| Terminal / install date | `TO_DATE(DATEADD(minute,330, MAX(UPDATED_AT)))` (IST); install completion = `INSTALLATION_COMPLETED_AT` |
| partner_id ↔ csp_id | `PROD_DB.CSP_GATEWAY_SERVICE_CSP_GATEWAY_SERVICE.CSP_ACCOUNT` |
| Enrollment date | Supabase `mg_optins.first_opted_at` (Flow 1) · `campaign_partners.scan_complete_at` (Flow 2) |
| Per-install rate (750/1000) | Google Sheet **Project Dominance - CSPs** → `CSP ID`, `Cluster Plan`, `Dates for MG` |

Constants: `MONTH_FLOOR = 10000`, `BASE_RATE = 300`, `GATE = 0.60`, `S4_CUTOFF = 16-Jul-2026`.

---

## 11. Current totals (31-Jul-2026, 477 CSPs)

| Metric | Value |
|---|---|
| Installs (since enrollment) | 1,579 |
| Installation money | ₹4,85,300 |
| Top-up money | ₹26,69,985 |
| **Total payout** | **₹31,55,285** |
| Floor-eligible | 319 (≤2 leads 182 + Secured 137) |
| Piece-rate only | 158 |
| Higher-rate installs so far (750/1000) | 23 → +₹11,600 vs flat ₹300 |

Live per-CSP numbers: **MG pilot sheet → tab "MG Payout (prorata)"**.
