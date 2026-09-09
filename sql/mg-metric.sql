-- MG metric: NUMERATOR = installs done ; DENOMINATOR = leads that reached "tech assigned"
-- Source = execution service (IEC). "Tech assigned" = a technician (EXECUTOR_ID) was assigned.
-- Per CSP, current calendar month, month-to-date (auto-rolls).
--
-- v3.1 (09-Sep-2026): month attribution moved OFF UPDATED_AT (it lags — the row is
-- touched for unrelated reasons, surfaced via CSP BUG-571) ONTO the lead's actual
-- terminal-event timestamp:
--   Numerator (installs)              = INSTALLATION_COMPLETED_AT
--   Denominator (tech-assigned leads) = latest of INSTALLATION_COMPLETED_AT /
--                                       FAILURE_REPORTED_AT / DISMISSED_AT
-- Leads are also deduped by MOBILE: one phone = one lead per CSP.
--
-- ┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
-- │ Received 09-Sep-2026. Kept VERBATIM — do not "improve" it. sql/metrics.sql   │
-- │ (what the pipeline runs) reproduces these counts exactly; its deviations are │
-- │ documented there (month window parameterised + IST for the snapshot freeze,  │
-- │ the {{csp}} template filter dropped, impacted-booking `imp` CTE kept).       │
-- │ Supersedes the v3.0 UPDATED_AT version (11-Aug-2026) — see git history.      │
-- └─────────────────────────────────────────────────────────────────────────────┘
WITH agg AS (
  SELECT iec.CONNECTION_ID, iec.CSP_ID,
    MAX(IFF(iec.EXECUTOR_ID IS NOT NULL, 1, 0))              AS tech_assigned,
    MAX(IFF(iec.INSTALLATION_COMPLETED_AT IS NOT NULL, 1, 0)) AS installed,
    TO_DATE(DATEADD(minute, 330, MAX(iec.INSTALLATION_COMPLETED_AT))) AS install_d,
    IFF(MAX(iec.INSTALLATION_COMPLETED_AT) IS NULL AND MAX(iec.FAILURE_REPORTED_AT) IS NULL
        AND MAX(iec.DISMISSED_AT) IS NULL, NULL,
        TO_DATE(DATEADD(minute, 330, GREATEST(
          COALESCE(MAX(iec.INSTALLATION_COMPLETED_AT), '1900-01-01'::timestamp_tz),
          COALESCE(MAX(iec.FAILURE_REPORTED_AT),       '1900-01-01'::timestamp_tz),
          COALESCE(MAX(iec.DISMISSED_AT),              '1900-01-01'::timestamp_tz)))) ) AS terminal_d
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES iec
  WHERE iec._FIVETRAN_ACTIVE
    [[ AND iec.CSP_ID IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE({{csp}}, ','))) ]]
  GROUP BY 1, 2
),
mob AS (
  SELECT CONNECTION_ID, MAX(MOBILE) AS mobile FROM (
    SELECT CONNECTION_ID, MOBILE FROM PROD_DB.DBT.TASKVANILLA WHERE MOBILE IS NOT NULL
    UNION ALL
    SELECT CONNECTION_ID, MOBILE FROM PROD_DB.DBT.TASKVANILLA_AUDIT WHERE MOBILE IS NOT NULL
  ) GROUP BY 1
),
lead AS (
  SELECT a.CSP_ID, COALESCE(m.mobile, a.CONNECTION_ID) AS lead_key,
    MAX(IFF(a.tech_assigned=1 AND a.installed=1 AND a.install_d >= DATE_TRUNC('month', CURRENT_DATE), 1, 0)) AS installed_mtd,
    MAX(IFF(a.tech_assigned=1 AND a.terminal_d           >= DATE_TRUNC('month', CURRENT_DATE), 1, 0)) AS denom_mtd
  FROM agg a LEFT JOIN mob m ON m.CONNECTION_ID = a.CONNECTION_ID
  GROUP BY 1, 2
)
SELECT CSP_ID,
  SUM(installed_mtd) AS installs,
  SUM(denom_mtd)     AS denom,
  ROUND(100.0*SUM(installed_mtd)/NULLIF(SUM(denom_mtd),0), 1) AS install_pct
FROM lead GROUP BY CSP_ID ORDER BY denom DESC
