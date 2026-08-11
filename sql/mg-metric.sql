-- MG metric: NUMERATOR = installs done ; DENOMINATOR = leads that reached "tech assigned"
-- Source = execution service (IEC). "Tech assigned" = a technician (EXECUTOR_ID) was assigned.
-- Per CSP, current calendar month, month-to-date (auto-rolls). Installs are a subset of tech-assigned.
--
-- ┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
-- │ Received 11-Aug-2026. SUPERSEDES sql/ontime-m1.sql (the 10-Aug on-time /M1   │
-- │ definition) — the numerator is ALL installs again, and the denominator is    │
-- │ tech-assigned leads from IEC, not the quality ledger's onsite outcomes.      │
-- │ Kept VERBATIM — do not "improve" it. sql/metrics.sql (what the pipeline runs)│
-- │ reproduces these two counts exactly; its only deviations are documented      │
-- │ there (month window parameterised for the snapshot freeze + IST).            │
-- └─────────────────────────────────────────────────────────────────────────────┘
WITH agg AS (        -- one row per (connection, CSP): install flag + tech-assigned flag
  SELECT iec.CONNECTION_ID, iec.CSP_ID,
    MAX(IFF(iec.OTP_VERIFIED=TRUE OR iec.INSTALLATION_COMPLETED_AT IS NOT NULL OR iec.COMPLETED_STEP>=7, 1, 0)) AS has_installed,
    MAX(IFF(iec.EXECUTOR_ID IS NOT NULL, 1, 0)) AS tech_assigned,
    TO_DATE(DATEADD(minute,330, MAX(iec.UPDATED_AT))) AS last_date
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES iec
  WHERE iec._FIVETRAN_ACTIVE
  GROUP BY 1, 2
)
SELECT CSP_ID,
  SUM(IFF(has_installed=1  AND last_date >= DATE_TRUNC('month', CURRENT_DATE), 1, 0)) AS installs,  -- NUMERATOR (mbg_installs)
  SUM(IFF(tech_assigned=1  AND last_date >= DATE_TRUNC('month', CURRENT_DATE), 1, 0)) AS denom      -- DENOMINATOR (mbg_leads)
FROM agg
GROUP BY CSP_ID
-- pct = ROUND(100 * installs / denom).  Filter to enrolled cohort with:  HAVING/WHERE CSP_ID IN (...) now
