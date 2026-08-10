-- Install-MG ON-TIME metric — per-CSP, matches the product app's M1 (INSTALL_COMPLIANCE).
-- SOURCE OF TRUTH = the app's maturation ledger. Window = current calendar month, MTD (auto-rolls).
--
-- ┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
-- │ Received from Shariq, 10-Aug-2026, as the authoritative definition of        │
-- │ mbg_ontime / mbg_late / installs / mbg_leads (denom) / mbg_pct / mbg_needed. │
-- │ Kept here VERBATIM — do not "improve" it. `sql/metrics.sql` (the file the    │
-- │ refresh pipeline actually runs) reproduces these four counts exactly; the    │
-- │ only deviation is its month window, which is parameterised ({MS}/{ME}) so    │
-- │ refresh.py can freeze each month's snapshot and retro-rebuild one month —    │
-- │ for the live month it resolves to exactly the DATE_TRUNC window below.       │
-- │ Companion spec: docs/BANNER-ontime-changes-v2.md · rules: MG-payout-logic §3.0│
-- └─────────────────────────────────────────────────────────────────────────────┘
WITH
-- Impacted-booking connections to drop from the denominator (unless installed).
-- Replace the dummy row with THIS MONTH's published impacted CONNECTION_IDs. Leave as-is to disable.
imp AS (
  SELECT column1 AS conn FROM VALUES ('00000000-0000-0000-0000-000000000000')
),
led AS (
  SELECT CSP_ID AS csp_id, CONNECTION_ID AS conn, TERMINAL_OUTCOME AS o,
         IFF(CONNECTION_ID IN (SELECT conn FROM imp),1,0) AS is_imp
  FROM PROD_DB.CSP_QUALITY_SERVICE_CSP_QUALITY_SERVICE.INSTALL_MATURATION_LEDGER
  WHERE TERMINAL_AT >= DATE_TRUNC('month', CURRENT_DATE)
    AND TERMINAL_AT <  DATEADD('month', 1, DATE_TRUNC('month', CURRENT_DATE))
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CONNECTION_ID ORDER BY TERMINAL_AT DESC NULLS LAST) = 1
),
agg AS (
  SELECT csp_id,
    SUM(IFF(o='ON_TIME_ACTIVE',1,0))                    AS ontime,    -- mbg_ontime (NUMERATOR)
    SUM(IFF(o='LATE_ACTIVE',1,0))                       AS late,      -- mbg_late (pays, NOT in numerator)
    SUM(IFF(o IN ('ON_TIME_ACTIVE','LATE_ACTIVE'),1,0)) AS installs,  -- install money = installs x rate
    SUM(IFF(o IN ('ON_TIME_ACTIVE','LATE_ACTIVE','REPORTED_FAILED','CANCELLED_ONSITE')
            AND NOT(is_imp=1 AND o IN ('REPORTED_FAILED','CANCELLED_ONSITE')),1,0)) AS denom  -- mbg_leads (DENOM)
  FROM led GROUP BY csp_id
)
SELECT csp_id, ontime, late, installs, denom,
  IFF(denom>0, ROUND(100*ontime/denom), 0)                        AS pct,     -- mbg_pct
  IFF(denom>0, GREATEST(0, CEIL((0.60*denom - ontime)/0.40)), 0)  AS needed   -- mbg_needed
FROM agg
-- WHERE csp_id IN (<enrolled cohort>)
