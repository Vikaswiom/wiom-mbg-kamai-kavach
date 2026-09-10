# Call-first nudge — analytics context

Everything needed to build a dashboard for the call-first nudge in-app campaigns.
Written **10 Sep 2026**, against the pipeline this repo already uses
(`analytics-dashboard/` + `refresh.py`).

> **Read §4 before designing anything.** The events carry **no properties**, which
> rules out most of the funnel the original proposal specified. Knowing that up
> front saves building a dashboard that cannot be populated.

---

## 1. What the campaign is

A CleverTap Custom HTML in-app that asks the partner to phone the customer before
proposing an install slot. Two buttons: `अभी कॉल करें` (primary) and `बाद में`
(text dismiss). Tapping outside the card also dismisses.

Design rationale, copy sheet and the code blockers live in the proposal artifact
"Call-First Nudge" v0.1 (9 Sep 2026).

Source: `docs/inapp-call-first-nudge.html` (`_csp`) and
`docs/inapp-call-first-nudge-rohit.html` (`_rohit`). The two files are identical
apart from one `EVENT_SUFFIX` line.

---

## 2. The events

Two campaigns, one event set each. **No properties on any of them** — the event
name is the entire payload.

| Fires when | `_csp` campaign | `_rohit` campaign |
|---|---|---|
| Dialog rendered | `call_nudge_shown_csp` | `call_nudge_shown_rohit` |
| `अभी कॉल करें` tapped | `call_nudge_accepted_csp` | `call_nudge_accepted_rohit` |
| `बाद में` **or** outside tap | `call_nudge_dismissed_csp` | `call_nudge_dismissed_rohit` |

Guarantees worth relying on:

- `shown` fires once per render and is guarded against a webview reload, so
  `shown` ≈ impressions.
- `accepted` and `dismissed` are mutually exclusive per render — the handler sets
  an `acted` latch, so a render produces **at most one** of them.
- Every path closes the dialog.

Not guaranteed:

- **Hardware-back dismissals never reach `call_nudge_dismissed_*`.** CleverTap
  handles Android back natively and the webview never hears it. Those land only in
  CleverTap's built-in `Notification Dismissed`. So
  `shown > accepted + dismissed`, and the gap is back-button exits **plus** people
  who left the app with the dialog open. Do not present the gap as "ignored".

---

## 3. Where the data lands

Same path as the banner dashboard — CleverTap → Snowflake, queried through
Metabase.

| Thing | Where |
|---|---|
| Events | `PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA` — `EVENT_NAME`, `TIMESTAMP`, `CLEVERTAP_ID`, `CSP_ID` |
| CleverTap ID → cspid | `PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA` — `CLEVERTAP_ID`, `cspid` |
| Install funnel | `PROD_DB.DBT_CSP.TAS_INSTALL_EXECUTION_CANDIDATES` (`ETL_CURRENT=TRUE`), join on `CSP_ID` |
| Query endpoint | `https://metabase.wiom.in/api/dataset`, database **113** |
| Auth | `METABASE_API_KEY` — GitHub repo secret, or `C:\credentials\.env` locally. Never in code. |

Install stage flags, as used by the existing dashboard:
slot = `CONFIRMED_SLOT_AT` · technician = `EXECUTOR_ID` ·
installed = `OTP_VERIFIED=TRUE OR COMPLETED_STEP>=7`.

---

## 4. What you can and cannot measure

The events have no properties. That is a deliberate simplification, and it costs
the following.

### Cannot be built

| Wanted | Why not |
|---|---|
| Per-task funnel (nudge → this install completed) | No `execution_id`. A nudge cannot be tied to the install it was about. |
| "Called within 2 h of assignment" | No `assigned_at` and no per-task key. Both halves are missing. |
| Split by install state | No `install_state`. |
| Split by entry path (home card / FPN / push / bell) | No `entry_source`. |
| CSP vs technician split | No `assignee_type` — and technicians cannot log into this app at all yet (F-2). |
| `बाद में` vs outside tap | Both emit the same event. Needs two event names, not a property. |
| The proposal's 15% holdout read | Holdout assignment is per **task**; with no task key, nudged and held-out installs cannot be separated. |

### Can be built

- **Impressions, accepts, dismisses** — per day, per campaign, both as raw counts
  and as distinct CSPs.
- **Accept rate** = `accepted / shown`. The headline number.
- **Reach** — how many distinct CSPs saw it, against the eligible base.
- **Accept → call**, at CSP level: did a CSP who accepted fire `call_initiated`
  soon after? This is the closest available proxy for "the nudge produced a call",
  and it is a **proxy**: it matches on cspid and time, not on the customer, so a
  call to a different household inside the window counts as a hit. Treat it as an
  upper bound. (Confirm `call_initiated` is the literal `EVENT_NAME` in
  `EVENTS_DATA` before relying on it — the app emits it, but the warehouse name
  has not been checked.)
- **Install outcomes for accepters vs dismissers** — CSP-level, over a window.
  Directional only; see the caveat in §6.

If the per-task funnel matters, the fix is upstream, not in SQL: add
`execution_id` back as an event property. Everything in the first table becomes
possible the moment it exists.

---

## 5. Starter SQL

Idioms match `analytics-dashboard/query_csp_funnel.sql`. **Not yet run against
prod** — check the first result set before wiring it into a refresh job.
Replace the date with the campaign's actual go-live.

### 5a. Daily funnel, both campaigns

```sql
WITH prof AS (
  SELECT DISTINCT CLEVERTAP_ID, cspid
  FROM PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA
),
ev AS (
  SELECT p.cspid,
         e.CLEVERTAP_ID,
         e.TIMESTAMP AS ts,
         CASE WHEN ENDSWITH(e.EVENT_NAME, '_rohit') THEN 'rohit' ELSE 'csp' END AS variant,
         REGEXP_REPLACE(e.EVENT_NAME, '_(csp|rohit)$', '')                     AS step
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.EVENT_NAME IN (
          'call_nudge_shown_csp',   'call_nudge_accepted_csp',   'call_nudge_dismissed_csp',
          'call_nudge_shown_rohit', 'call_nudge_accepted_rohit', 'call_nudge_dismissed_rohit')
    AND e.TIMESTAMP >= '2026-09-10'
)
SELECT
  variant,
  DATE_TRUNC('day', ts) AS day,
  COUNT(CASE WHEN step='call_nudge_shown'     THEN 1 END)              AS n_shown,
  COUNT(CASE WHEN step='call_nudge_accepted'  THEN 1 END)              AS n_accepted,
  COUNT(CASE WHEN step='call_nudge_dismissed' THEN 1 END)              AS n_dismissed,
  COUNT(DISTINCT CASE WHEN step='call_nudge_shown'    THEN cspid END)  AS csps_shown,
  COUNT(DISTINCT CASE WHEN step='call_nudge_accepted' THEN cspid END)  AS csps_accepted,
  COUNT(DISTINCT CASE WHEN step='call_nudge_shown'    THEN CLEVERTAP_ID END) AS ct_profiles_shown
FROM ev
GROUP BY 1, 2
ORDER BY 1, 2;
```

`ct_profiles_shown` exists to reconcile with CleverTap's own UI, which counts
profiles rather than CSPs — see §6.

### 5b. Accept → call, within two hours (CSP-level proxy)

```sql
WITH prof AS (
  SELECT DISTINCT CLEVERTAP_ID, cspid
  FROM PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA
),
acc AS (
  SELECT p.cspid,
         e.TIMESTAMP AS accepted_at,
         CASE WHEN ENDSWITH(e.EVENT_NAME, '_rohit') THEN 'rohit' ELSE 'csp' END AS variant
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.EVENT_NAME IN ('call_nudge_accepted_csp', 'call_nudge_accepted_rohit')
    AND e.TIMESTAMP >= '2026-09-10'
),
calls AS (
  SELECT p.cspid, e.TIMESTAMP AS called_at
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.EVENT_NAME = 'call_initiated'
    AND e.TIMESTAMP >= '2026-09-10'
)
SELECT
  a.variant,
  COUNT(*)                                          AS accepts,
  COUNT(DISTINCT a.cspid)                           AS accepting_csps,
  SUM(CASE WHEN c.cspid IS NOT NULL THEN 1 ELSE 0 END) AS accepts_followed_by_call
FROM acc a
LEFT JOIN calls c
  ON  c.cspid     = a.cspid
  AND c.called_at >= a.accepted_at
  AND c.called_at <  DATEADD('hour', 2, a.accepted_at)
GROUP BY 1;
```

An accept with two calls in the window counts twice — de-duplicate with a
`QUALIFY ROW_NUMBER() OVER (PARTITION BY a.cspid, a.accepted_at ORDER BY c.called_at) = 1`
if you want accepts-with-at-least-one-call instead.

### 5c. Install outcomes, accepters vs dismissers

```sql
WITH prof AS (
  SELECT DISTINCT CLEVERTAP_ID, cspid
  FROM PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA
),
grp AS (
  SELECT p.cspid,
         MAX(CASE WHEN e.EVENT_NAME LIKE 'call_nudge_accepted%' THEN 1 ELSE 0 END) AS ever_accepted
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.EVENT_NAME LIKE 'call_nudge_%'
    AND e.TIMESTAMP >= '2026-09-10'
  GROUP BY p.cspid
),
inst AS (
  SELECT CSP_ID AS cspid,
         COUNT(*)                                                          AS candidates,
         COUNT(CASE WHEN CONFIRMED_SLOT_AT IS NOT NULL THEN 1 END)         AS slot_conf,
         COUNT(CASE WHEN EXECUTOR_ID     IS NOT NULL THEN 1 END)           AS exec_assigned,
         COUNT(CASE WHEN OTP_VERIFIED=TRUE OR COMPLETED_STEP>=7 THEN 1 END) AS installed
  FROM PROD_DB.DBT_CSP.TAS_INSTALL_EXECUTION_CANDIDATES
  WHERE ETL_CURRENT = TRUE
    AND CREATED_AT >= '2026-09-10'
  GROUP BY CSP_ID
)
SELECT
  CASE WHEN g.ever_accepted = 1 THEN 'accepted' ELSE 'dismissed only' END AS cohort,
  COUNT(*)                AS csps,
  SUM(i.candidates)       AS candidates,
  SUM(i.slot_conf)        AS slot_confirmed,
  SUM(i.exec_assigned)    AS technician_assigned,
  SUM(i.installed)        AS installed
FROM grp g
LEFT JOIN inst i ON i.cspid = g.cspid
GROUP BY 1;
```

---

## 6. Counting traps

1. **Profiles ≠ CSPs.** One cspid owns many `CLEVERTAP_ID`s from reinstalls and
   re-logins. CleverTap's UI counts profiles; this repo's dashboards count unique
   CSPs. The two will never match — carry both, as `query_csp_funnel.sql` does.
2. **`shown` is impressions, not people.** "Show only once" is a per-user
   CleverTap cap, not the proposal's "once per install task, ever" — CleverTap
   cannot express the latter. Say which one the campaign is actually set to on the
   dashboard, or the reach number will be misread.
3. **The `shown − accepted − dismissed` gap is not "ignored".** It is back-button
   exits plus app-backgrounding. Label it honestly or leave it out.
4. **§5c is correlational, twice over.** Partners who accept a nudge are already
   the diligent ones, and with no task key the install counts include installs the
   nudge never touched. It cannot support a causal claim. The proposal's own
   caveat applies with more force here: without the task-level holdout, this
   re-measures the habit, not the nudge. Put that on the dashboard, not just in
   this file.
5. **`_rohit` is a test campaign.** Keep it out of any headline number, or the
   test traffic inflates the real one.
6. **New event names are invisible until first ingest.** A name will not appear in
   CleverTap's event picker until one has been processed, and the Snowflake mirror
   lags further. An empty result on day one is usually latency, not breakage.

---

## 7. Building the dashboard the way this repo does

The established pattern, from `analytics-dashboard/`:

1. Write the query as `analytics-dashboard/query_call_nudge.sql`.
2. `refresh.py` POSTs it to `https://metabase.wiom.in/api/dataset` with
   `METABASE_API_KEY`, database 113, and rewrites a data file — `data.js` for the
   banner dashboard, `banner-data.json` for the engagement one. Include a
   `generated_ist` stamp; every page here shows last-updated.
3. A static `index.html` renders from that file. No build step.
4. GitHub Actions cron commits and pushes; GitHub Pages redeploys in about a
   minute.

`banner-data.json` is the closest shape to copy — `generated_ist`,
`window_start`, headline counts, `by_outcome`, `daily`. A call-nudge equivalent:

```json
{
  "generated_ist": "2026-09-10 18:05",
  "window_start": "2026-09-10",
  "campaigns": {
    "csp":   { "shown": 0, "accepted": 0, "dismissed": 0,
               "csps_shown": 0, "csps_accepted": 0, "accept_rate": 0.0 },
    "rohit": { "shown": 0, "accepted": 0, "dismissed": 0,
               "csps_shown": 0, "csps_accepted": 0, "accept_rate": 0.0 }
  },
  "daily": [
    { "day": "2026-09-10", "variant": "csp",
      "shown": 0, "accepted": 0, "dismissed": 0 }
  ]
}
```

Style: `banner-dashboard.html` already carries the house palette — maroon `#3f2a44`
header, purple `#6D17CE` hero, green `#008043`, amber `#B85C00`, Inter, KPI cards
at radius 14. Reuse it rather than starting a new visual language.

---

## 8. Open items that change the analytics

- **F-1 (blocker).** The customer call link is gated off in
  `AWAITING_SLOT_PROPOSAL` — the exact state the nudge fires in. Until that opens,
  accepters land on a screen with nothing to tap, so accept → call will read low
  for a reason that is not the copy. Do not tune the copy on that number.
- **`DEEPLINK` is empty.** The CTA currently just closes the dialog; it does not
  navigate. Accept → call is therefore measuring intent, not a completed path.
- **Naming.** `_csp` reads as a permanent role marker and `_rohit` as a test
  marker. If both are tests, rename to `_test_csp` / `_test_rohit` before anyone
  builds on them. If `_csp` is the production name, decide now what the technician
  app will emit (F-2) — a second suffix, or one shared name with a property.
