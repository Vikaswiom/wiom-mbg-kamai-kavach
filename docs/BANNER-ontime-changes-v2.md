# CleverTap Banner — Changes for the ON-TIME metric (v2.0)

**For:** Vikas · **Date:** 08-Aug-2026 · Scope = **only what changes in the MBG banner / poller tokens.** Everything else (screens, HTML, campaign setup) stays the same.

The metric moves from *install rate* to **on-time install rate** (matches the app's M1 / Installation Compliance). Three things change in the banner: the **denominator**, the **rate numerator (on-time)**, and the **copy**. Per-install pay is unchanged.

---

## 1. Denominator (`mbg_leads`) — new definition (= product app M1 formula, **calendar-month window**)
A lead counts in `mbg_leads` **only if the technician actually went onsite** — i.e. **only** these four outcomes: **install on-time + install late + `install_failed` (reported onsite) + `cancelled_onsite`**.

**Exclude everything else:** declines (`csp_denied`), customer cancellations (`cust_cancel_*`), and **ALL** upstream cancels — `csp_timeout` (P41 before tech), `csp_no_show` (P74 after tech), `csp_retryx`, `system_other` — plus `reached_slot=0` and still-open.
> No before/after-tech split needed. Cleanest source = the app's own ledger `CSP_QUALITY_SERVICE.INSTALL_MATURATION_LEDGER.TERMINAL_OUTCOME IN ('ON_TIME_ACTIVE','LATE_ACTIVE','REPORTED_FAILED','CANCELLED_ONSITE')` — same table as the numerator.
> **Impacted-booking phones:** drop from `mbg_leads` unless that connection was installed.

**⚠️ Window = the calendar MONTH (month-to-date), NOT the app's 60-day rolling.** `mbg_leads` / `mbg_ontime` count only outcomes matured **this month**. The **product app's M1 card is 60-day rolling**, so the % a CSP sees in the app will *not* match the banner — same formula, different clock. Example: **DH Cable (`a0b9x8`), 10-Aug — app 86% (28/24, rolling) vs banner 71% (14/10, August).** This is expected; don't "fix" it to match the app card. (If the banner ever needs to equal the app card, that's a separate product decision to switch MG to rolling.)

## 2. Rate numerator = ON-TIME installs (NOT all installs)
Add an on-time flag per install: `ontime = installed AND (TO_DATE(INSTALLATION_COMPLETED_AT, IST) <= CONFIRMED_SLOT_DATE)`.
Then everything rate-related uses **on-time count**, not total installs:

| Token | OLD | **NEW** |
|---|---|---|
| `mbg_pct` | `round(100*installs/denom)` | **`round(100*ontime/denom)`** |
| `mbg_next_pct` | `(installs+1)/(denom+1)` | **`(ontime+1)/(denom+1)`** |
| `mbg_needed` | `ceil((0.6*denom − installs)/0.4)` | **`ceil((0.6*denom − ontime)/0.4)`** |
| `mbg_screen` route | `installs/denom` | **`ontime/denom`** (secured if `ontime/denom ≥ 0.60`) |

**Two NEW tokens to push:**
- `mbg_ontime` = `str(ontime)` — on-time install count (the number shown in "X लगे")
- `mbg_late` = `str(installs − ontime)` — late installs (for the copy in §3)

## 3. Pay tokens — UNCHANGED
`mbg_installpay` and `mbg_topup` stay on **ALL installs** (a late install still earns its ₹300/750/1000):
- `mbg_installpay = "{:,}".format(rate * installs)`  *(installs = total, incl. late)*
- `mbg_topup = max(0, 10000 − rate*installs)`

## 4. Copy changes (in the HTML)
- The "X मिले · Y लगे = Z%" line: **Y = `mbg_ontime`** (on-time), Z = `mbg_pct` (on-time rate). Use `mbg_ontime`, not the old all-install token.
- Add an on-time nudge on `keepgoing`/`almost`: *"समय पर लगाएँ — स्लॉट वाले दिन या उससे पहले"* ("install on time — on or before the slot day"). Optionally, when `mbg_late > 0`: *"{{ Profile.mbg_late }} देर से लगे — ये % में नहीं गिने"* ("N were late — they don't count in %").
- `mbg_needed` phrasing stays *"install your next N connections **on time**"*.

## 5. Unchanged
Screens (`secured`/`almost`/`keepgoing`/`noleads`), the 11 AM visibility gate, `mbg_screen_real`, tickets, identities, campaign setup, HTML paste rules — **all unchanged**. Floor stays "0 leads" (banner already shows `noleads` only at `total==0`).

---
**Net for eng:** add `ontime` computation + `mbg_ontime`/`mbg_late` tokens; point `mbg_pct`/`mbg_next_pct`/`mbg_needed`/screen at `ontime`; redefine `mbg_leads` (exclude declines/cx-cancel/before-tech-timeout, incl. impacted-drop); leave installpay/topup on all installs.
