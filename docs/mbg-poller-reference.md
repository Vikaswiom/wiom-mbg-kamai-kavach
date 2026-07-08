# CleverTap · Poller · Campaign — MBG & CI Consolidated Reference

Everything proven on the Wiom **MBG (Kamai Kavach)** and **CI (Capability Intervention)** programs:
how the poller → profile → campaign loop works, the four CleverTap APIs, the measurement
accuracy gotchas (the ones that cost real debugging), the HTML in-app rules, and the two
programs' specifics. Wiom account region = **`eu1`**.

---

## 0. The ONE mental model

**warehouse compute → write flags + content to CleverTap profiles → a campaign (trigger + audience filter + content) renders each profile's own values when its trigger fires.**

- The **poller** is the backend that runs this loop on a schedule (MBG: every 5 min; CI: daily).
- **Profile writes fire NOTHING.** `/1/upload` (type:profile) only updates the profile — always safe to run.
- **Campaigns do the firing**, gated on profile properties. You never "send" from the poller; you flip flags and the campaign renders.
- So you target "today's cohort" without touching the campaign — just write the flag/prop.

---

## 1. The four CleverTap APIs

### 1a. Write profile properties — `POST /1/upload` (type: profile)  → fires nothing
```json
{ "d": [ { "identity": "u123", "type": "profile",
           "profileData": { "mbg_screen": "keepgoing", "mbg_pct": "45", "mbg_installpay": "1,500" } } ] }
```
- `identity` = the CleverTap **identity** (Wiom = the app **userId** = `CSP_USER.ID`). **A phone is NOT an identity.**
- **All values as strings** — templates/filters compare text (`"true"`, `"45"`).
- Batch (~30–900/call). Response `{status, processed, unprocessed:[...]}` — **check `unprocessed`** (a bad identity is dropped there silently, not raised).

### 1b. Resolve your key → CleverTap identity — `POST /1/profiles.json` (cursor export)
Your warehouse doesn't store the CT identity. Stamp a known prop (`cspid`/`mbg_id`) on each profile, then export and build `{ key → identity }`, **freshest profile wins** (`platformInfo[].ls` last-seen). POST returns a `cursor`; GET `?cursor=` pages until gone.
- **The export is intermittently empty — retry; abort the whole job if it never reaches a sane count.** Never push to a half-resolved audience.
- CI: `cspid → numeric userId`. Re-resolve every run; identities drift.

### 1c. Measure counts — `POST /1/counts/events.json` (async)
POST returns `req_id`, poll `?req_id=` until `status=="success"` → `{ "count": N }`.
- **`count` = TOTAL event occurrences (taps), for the date range. NOT unique users, NOT per-day in one call** (query each day: `from=to=YYYYMMDD`). On a healthy day ≈ **2.4× the unique CSP count** (a CSP opens the banner several times).
- Per-campaign in-app: `Notification Viewed` (denominator) / `Notification Clicked`. **Push `Sent` is NOT fetchable** — read off the dashboard.

### 1d. Export raw events — `POST /1/events.json?batch_size=N` (cursor)  ← the accurate per-day source
POST `{event_name, from:YYYYMMDD, to:YYYYMMDD}` → `cursor`; GET `?cursor=` pages until records empty.
Each record: `{ "profile": {"identity","phone","all_identities",...}, "ts": <int>, "event_props":{...} }`.
- **`ts` is a `YYYYMMDDHHMMSS` integer — NOT an epoch timestamp.** (Parsing it as epoch zeroes everything.) Day = `str(ts)[:8]`.
- This is **THE way to count true unique CSPs PER DAY** — map `profile.identity → csp_id`, dedupe per day. A CSP who acted on D-1 AND D-0 correctly counts on **both** days.
- Caveats: **rate-limits (429) → retry with backoff, keep concurrency ≤3**; **lags the live feed** (so use last-active for D-0/today); **wobbles ±10–25% run-to-run** → **cache past days** to a file (they're fixed once the day is over).

**Cross-API rules:** region must match the account (`eu1`; wrong region = silent 401/empty). **GET polls (`?req_id`, `?cursor`) must NOT carry `Content-Type`** (it 400s them — use separate header dicts).

---

## 2. Measuring engagement — which API for what  (the session's biggest lesson)

| You want | Use | Gotcha |
|---|---|---|
| **Taps / interactions** (a CSP acts many times) | counts API, OR `len(event export)` | not unique |
| **Unique CSPs per day** | **event export** (accurate) | rate-limits + lag → cache past days |
| **Unique, latest day only** | profile export last-active is fine | — |
| **Unique, older days** | **last-active UNDER-COUNTS** — use event export | a CSP who acted D-1 & D-0 lands in D-0 only |

- **Last-active** (from `/1/profile.json` first/last-seen) buckets a CSP on the day of its *last* event → exact only for the latest day. This is why MBG Page-3 "D-1 Viewed" read **162** when the true event-export count was **~277**.
- **`MBG_*` custom events are NOT in the warehouse.** `PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA` has `App Launched` / `InApp_Shown` (system events) but not `MBG_View_*` etc. — CleverTap API only.
- **`InApp_Shown` (coverHtml) over-counts MBG views** — it also fires for Flow-3 and other enrolled in-apps, so "viewed" reads ≈ targeted. Use the MBG-specific `MBG_View_*` event, not `InApp_Shown`.

---

## 3. Campaign mechanics & gotchas

- A campaign = **Trigger** (system event like `App Launched`, or a custom event) + **Audience filter** (`mbg_screen equals keepgoing`) + **Content** (static or `{{ Profile.x }}`).
- **One in-app per session, by priority.** Two in-apps on the same trigger → only the higher-priority/newer one shows; the loud one starves the others (SR-1 starved SR-3 → 0 views). Fixes: (a) different **trigger contexts** (`Notification Clicked` enters a different session than `App Launched`); (b) **yield via a flag** — the loud campaign's backend sets its own gate false for users who currently qualify for an urgent one. **Mutually-exclusive audiences don't collide** — MBG keepgoing / almost / secured / noleads never overlap (a CSP is exactly one), so their priorities are safe.
- **Stopped + recreated = a NEW `campaign_id`.** To report a *logical* campaign, keep the list of **all variant ids** and **SUM** across them. Keep a committed `name → [live id + stopped variant ids]` inventory. (MBG **no-leads relaunched 07-Jul-2026 as new campaign `1783348147`** — "Flow 4 noleads MBG", App Launched, filter `mbg_screen==noleads`, priority 9, once/day — because the old one wasn't editable.)
- **A custom prop doesn't exist in the audience picker until it's been written to ≥1 profile.** Seed the schema first (push to a throwaway identity), wait ~1–2 min for indexing.
- **Flags persist → night-firing.** An in-app fires whenever its trigger happens *and* the flag is still set — a morning flag fires at 10 PM. Backstops: evening **clear-flags** cron writing `flag="false"` to every identity + CleverTap native **time-window/DND**.
- **A flag-gated campaign AND'd against a static uploaded list renders to NOBODY** (server-flag identities ≠ list identities). Drop the static-list row; let the server flag be the sole audience.

---

## 4. HTML in-app rules (the paste/token minefield)

- **Token syntax:** `{{ Profile.PropertyName | default: "value" }}` — **capital `Profile`**, Liquid `| default:` with the value **in quotes**. Lowercase `{{profile.x|y}}` renders as bare dashes — it does NOT resolve.
- **Tokens resolve EVERYWHERE in the pasted HTML — comments and `<script>` included.** Don't write a token in a comment to "document" it; it gets processed and can break the paste.
- **Never put `#` (or reserved chars) INSIDE a token.** Put it outside: `#{{ Profile.color | default: "dc2626" }}`, push the value without it.
- **Simple cards:** go **JS-free** — precompute every value server-side, put tokens directly in HTML text + inline `style=`.
- **Multi-screen interactive flows DO run inline JS** (Inline HTML + "Include JavaScript" ON). Hard-won rules:
  - This app supports **Inline HTML ONLY, not URL mode** (a hosted URL renders as plain text).
  - **Each screen/element on ONE LINE** — multi-line indented *body* markup gets mangled on paste and the whole `<script>` dies. (`<style>`/`<script>` may stay multi-line.)
  - **Debugging signal:** works in a browser but fails only in CleverTap inline = a **paste/format** problem, not a code bug.
  - Insert tokens via the editor's `@`/`{}` button (makes a recognized chip). Per-CSP data → token in a **hidden element's TEXT** (`<span style="display:none">@Profile - x</span>`) read in JS, never in an attribute. **Empty the box (Ctrl+A→Del) before pasting.**
- **MBG banner events** (per screen suffix): `MBG_View_<screen>` (on load), `MBG_Scroll_`, `MBG_SawGuarantee_`, `MBG_TapGuarantee_` (guarantee card is non-clickable — just tracks the tap), `MBG_Ticket_` (ticket-row tap), `MBG_Click_` (back-arrow = "Exit"). CleverTap bridge: `pushEvent`, `openDeepLink`, `dismissInAppNotification`.

---

## 5. The MBG poller — `mbg_stage3_poller.py`

Runs **every 5 min** inside the tv-wall `_tracker_loop`. Modes: `MBG_DRY=1` (no push) · `MBG_TEST=1` (first 2 identities) · default full push. Constants: `FLOOR=10000`, `PAY=300`, `GATE=0.60`, `MS`=month-start (`2026-07-01`).

**Cohort (enrolled):** `frozen_cohort.json` (flow1 ∪ flow2) ∩ `mg_optins` (Supabase audit `gonqnxpdtvjydppbrnie`, `first_opted_at NOT NULL`); flow2 also requires `campaign_partners.scan_complete_at NOT NULL` for campaign `108a08d1-…`.

**Per-CSP metrics** from the RAW candidate table `PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES` (`MAX_BY(state, UPDATED_AT)` per connection → bucket):
- **DENOM** (doc-aligned) = every **customer-confirmed** (`reached_slot=1`) connection that reached an **END STATE this month**: installed + cust-cancel-after-slot + CSP-cancelled/no-show/timeout-post-accept + install-failed + cancelled-onsite. **EXCLUDE** `reached_slot=0` (declined, P41 timeout, cust-cancel-before-slot), system/upstream cancels, and still-open.
- **pending** = ALL open leads (`bucket='open'`) — the live pipeline (for banner routing/engagement, **not** payout).

**`route(installs, denom, pending)`** → `total = denom + pending`:
- `noleads` if `total == 0`
- `secured` if `denom > 0 and installs/denom > 0.60`
- `almost` if `(installs + pending) > 0.60 * total` (reachable via the open pipeline)
- else `keepgoing`

**Tokens pushed** (strings): `mbg_screen`, **`mbg_screen_real`** (the TRUE screen — survives the visibility gate, for analytics), `mbg_installs`, `mbg_leads`(=DENOM), `mbg_pending`, `mbg_needed`, `mbg_pct`, `mbg_next_pct`, `mbg_installpay`, `mbg_topup`, `mbg_days_left`, `mbg_id`, `mbg_month`, `mbg_t1_no/area/cid`, `mbg_t2_*`, `mbg_tkt_n`.

**Visibility gate:** before **11 AM IST**, `mbg_screen="hold"` (no campaign matches → nothing renders even though the campaign window opens at 9 AM); `mbg_screen_real` keeps the true screen.

**Identities:** `DIM_CSP × CSP_USER` (ROLE in OWNER/MANAGER/MANAGER_PLUS, STATUS=ACTIVE) → `u.ID` is the CleverTap identity. **Tickets:** top-2 OPEN install tickets per CSP (`#`+last-4 of exec-candidate-id + zone).

> **"149 no-leads CSPs" is a misnomer.** Of ~148: only **~19** truly never got a lead; **~129** GOT leads but let them ALL lapse before slot-confirmation — **~88% CSP-side** (P41 timeout/no-show 361 + declined 165). The banner arguably should say "act on your leads," not "no leads," for those 129.

---

## 6. MBG banner tracking — `mbg_tracking_tab.py` → Page 3

Per-CSP profile events → per-day unique + coverage → MG-pilot gsheet (`1UFm9qu…`) → TV-wall Page 3 (`tv_dashboard.py` HTML3, manual tab).
- **D-1 unique = event export, CACHED** (`.d1_export_cache.json`, keyed by D-1 yyyymmdd — a past day is fixed, compute once). **D-0 = last-active** (exact for the latest day; the export lags live).
- `_tracker_loop` script timeout **bumped 220→400s** for the tracking tab (the daily uncached event-export run is heavy).
- **Targeting auto-detects no-leads-live** via today's `MBG_View_noleads` count (>5): live → target INCLUDES noleads (~423 CSPs / 778 identities); stopped → non-noleads (~275). So it self-corrects when no-leads relaunches — no manual edit.
- Coverage `%` is **customer-active-base** based (viewers' active base ÷ targeted active base), not CSP-count.

---

## 7. CI (Capability Intervention) specifics

- **Identity bridge:** `cspid → CleverTap identity (numeric userId)` comes from the **profile EXPORT**, NOT the warehouse. Phone isn't an identity. Pick the **freshest** profile per cspid.
- **Integration:** Identity = `userId`; distinguish **app-set props** vs **CI-feed-pushed props**; in-app **HOME-only suppression**; `CtPageName` deep-link **allowlist**; events emitted per SR/DH module.
- **Dashboard (`ci-dashboard-generator`):** live counts API **per campaign**; **stopped+recreated campaigns get NEW ids → group ALL variant ids per SR and SUM**; push `Sent` not fetchable → hard-code from dashboard; a total across `[live, stopped, stopped]` can read healthy while the LIVE id is dead at 0 — **always break a suspicious total down per-id**.
- **Daily push (`ci_daily_push.py`):** compute cohort in warehouse → `ct_bridge()` map keys → build one `profile(identity, **props)` per row → `ct_upload()`; **abort if `pushable < cohort − slack`**.

---

## 8. Conventions worth keeping

- **One Python module owns the CleverTap calls**; everything else imports it. Secrets via env (`CLEVERTAP_ACCOUNT/PASSCODE/REGION`) — never hard-code the passcode.
- Keep a **committed campaign-id inventory** (logical name → live id + stopped variant ids + manual push `Sent`). It rots fast.
- **Log every push** (`cohort=N pushable=M unreachable=[...]`) and every counts/export call's id/args, so a zero is debuggable.
- **Profile writes are safe** (fire nothing) → use them freely for flags/content/suppression. **Sends are show-then-confirm** — estimate audience + dry-run + get approval before any real push/in-app.

---

## Appendix A — EXACT profile-property calculation (MBG poller `mbg_stage3_poller.py`)

Every token the poller writes and precisely how it's computed. Source: `PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES` (RAW candidate table, `_FIVETRAN_ACTIVE=TRUE`), aggregated **one row per (CONNECTION_ID, CSP_ID)** with `MAX_BY(field, UPDATED_AT)`.

**Step 1 — per-connection bucket.** `last_state = MAX_BY(CURRENT_STATE, UPDATED_AT)`; `rc/fr/fsc = MAX_BY(REASON_CODE / FAILURE_REASON / FAILURE_SUBREASON_CODE, UPDATED_AT)`.
- `has_installed = MAX(OTP_VERIFIED=TRUE OR INSTALLATION_COMPLETED_AT IS NOT NULL OR COMPLETED_STEP>=7)`
- `reached_slot  = MAX(CONFIRMED_SLOT_AT IS NOT NULL)`   ← "customer confirmed a slot"
- `last_date     = TO_DATE(DATEADD(minute,330,MAX(UPDATED_AT)))`  (IST)
- **bucket** (first match wins):
  `installed`(has_installed=1) · `csp_denied`(last_state=DECLINED) · `csp_no_show`(CANCELLED_BY_UPSTREAM+fr=TIMEOUT_P74+fsc=CSP_NO_SHOW+rc=ALLOCATION_ACCEPTED) · `csp_abandoned`(…+fsc=CSP_NO_SHOW) · `csp_timeout`(CANCELLED_BY_UPSTREAM+rc=TIMEOUT_P41) · `cust_cancel_after_slot`(CANCELLED_BY_CUSTOMER+reached_slot=1) · `cust_cancel_before_slot`(CANCELLED_BY_CUSTOMER+reached_slot=0) · `install_failed`(INSTALLATION_REPORTED_FAILED) · `system_other`(any other CANCELLED_BY_UPSTREAM) · `cancelled_onsite`(INSTALLATION_CANCELLED_ONSITE) · else `open`.

**Step 2 — per-CSP aggregate** (`MS` = month-start `2026-07-01`):
- `installs = COUNT(bucket='installed' AND reached_slot=1 AND last_date>=MS)`
- `denom` (= token **`mbg_leads`**) `= COUNT(reached_slot=1 AND bucket NOT IN ('open','system_other') AND last_date>=MS)` — every customer-confirmed connection that reached an END STATE this month
- `pending = COUNT(bucket='open')` — the whole live pipeline (any open, incl not-yet-confirmed)

**Step 3 — `route()` + tokens** (`FLOOR=10000, PAY=300, GATE=0.60`; `total = denom + pending`):

| Token | Exact formula |
|---|---|
| **`mbg_screen`** | `noleads` if `total==0` · `secured` if `denom>0 and installs/denom>0.60` · `almost` if `(installs+pending) > 0.60*total` · else `keepgoing` |
| `mbg_screen_real` | same value, but ALWAYS the true screen (before 11 AM IST `mbg_screen` is overwritten to `"hold"` so no campaign matches → nothing renders; `mbg_screen_real` keeps the truth for analytics) |
| `mbg_installs` | `str(installs)` |
| `mbg_leads` | `str(denom)` |
| `mbg_pending` | `str(pending)` |
| `mbg_pct` | `str(round(100 * installs/denom))`  (0 if denom=0) |
| `mbg_next_pct` | `str(round(100 * (installs+1)/(denom+1)))` — rate if one more confirmed lead installs |
| `mbg_needed` | `str(max(1, floor(0.60*total)+1 − installs))` if total>0 else `"0"` — installs still needed to clear 60% |
| `mbg_installpay` | `"{:,}".format(300 * installs)` (₹) |
| `mbg_topup` | `str(max(0, 10000 − 300*installs))` — guarantee top-up |
| `mbg_days_left` | `str(calendar.monthrange(y,m)[1] − today.day)` |
| `mbg_month` | `"महीना " + str(max(1, today.month − 6))` (program month; Jul=1) |
| `mbg_id` | `str(userId).zfill(6)` |
| `mbg_tkt_n` | count of the CSP's top-2 OPEN install tickets (`"0"`–`"2"`) |
| `mbg_t{1,2}_no` | `"#" + RIGHT(EXECUTION_CANDIDATE_ID, 4)` (matches the in-app ticket #) |
| `mbg_t{1,2}_area` | `ZONE_ID` (e.g. `zone_00…`) |
| `mbg_t{1,2}_cid` | full `EXECUTION_CANDIDATE_ID` (for the deep-link) |

**"OPEN install ticket"** = `CURRENT_STATE IN` (ACCEPTED, AWAITING_SLOT_PROPOSAL, SLOT_SELECTED, AWAITING_CUSTOMER_SLOT_CONFIRMATION, SLOT_CONFIRMED_BY_CUSTOMER, SLOT_AUTO_CONFIRMED, AWAITING_TECHNICIAN_ASSIGNMENT, TECHNICIAN_ASSIGNED, ARRIVED_AT_SITE, INSTALLATION_IN_PROGRESS_PRE_FEE, FEE_COLLECTION_PENDING, INSTALLATION_IN_PROGRESS_POST_FEE, AWAITING_CUSTOMER_OTP). **Top-2 per CSP** by state rank (ARRIVED_AT_SITE 8 > TECHNICIAN_ASSIGNED 7 > AWAITING_TECH 6 > SLOT_CONFIRMED/AUTO 5 > AWAITING_CUST_SLOT 4 > SLOT_SELECTED 3 > AWAITING_SLOT_PROPOSAL 2 > else 1), then **oldest** UPDATED_AT.

**Identity & cohort.** Identities = `DIM_CSP (ETL_CURRENT) × CSP_USER` where `ROLE IN (OWNER, MANAGER, MANAGER_PLUS)` and `STATUS='ACTIVE'` → **`u.ID` is the CleverTap identity** (NOT the cspid — cspid is only a *property*, `mbg_id` is derived from the userId). Enrolled cohort = `frozen_cohort.json` (flow1 ∪ flow2) ∩ Supabase `mg_optins` (`first_opted_at NOT NULL`); flow2 additionally requires `campaign_partners.scan_complete_at NOT NULL`.

> **Uploading a CSP list to a CleverTap segment:** the CSV must contain **userIds** (the identity), NOT CSPIDs — a CSPID matches no profile. Map `CSP_ID → CSP_USER.ID` (owner/admin) first, then upload the userId column against "Identity."

### Appendix B — CI profile properties (conceptual; exact per module in `ci_daily_push.py`)
CI writes per-CSP flags + content the campaign renders: a `<module>_fire`/`<module>_active` gate flag (which cohort qualifies today), a `<module>_has_data` guard (don't render an empty banner), and content tokens (`line1`, `pending_count`, ticket text, etc.), all computed in the warehouse per SR/DH module, resolved `cspid → numeric userId` via the profile export, then `ct_upload()`. Each module owns its own flag (single owner, to avoid set/unset races).
