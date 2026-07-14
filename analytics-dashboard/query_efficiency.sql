-- Partner efficiency the MBG (Kamai Kavach) way, June (pre-MBG) vs July (MBG live 1 Jul),
-- by enrolment bucket. Replicates the live program calc (mbg-kamai-kavach/sql/metrics.sql):
--   * one row per (CONNECTION_ID, CSP_ID), final state via MAX_BY(_, UPDATED_AT), 120-day window.
--   * a lead's bucket = its terminal outcome; reached_slot = customer confirmed a slot.
--   * denom (LEADS) = slot-confirmed leads that reached an END STATE this month
--                     (reached_slot=1 AND bucket NOT IN ('open','system_other')).
--   * installs      = those that ended 'installed'.
--   * efficiency = installs / denom  ·  60%+ ("secured", cleared the gate) = installs/denom > 0.60.
-- Month = the month the lead reached its end state (last_date). MBG launched 1 Jul so June is the
-- pre-program baseline for the same partners. Buckets (from the belief-break enrolment audit):
--   enrolled = Flow-1 "ENROLLED" / audit done (429 csp) · eligible = offered but not enrolled
--   (Flow-1 not-enrolled + all Flow-2 = 140 csp) · nonmbg = everyone else. Matches
--   vikaswiom.github.io/wiom-mbg-kamai-kavach/data.json for July.
WITH base AS (
  SELECT CONNECTION_ID, CSP_ID,
    MAX_BY(CURRENT_STATE, UPDATED_AT)          AS last_state,
    MAX_BY(REASON_CODE, UPDATED_AT)            AS rc,
    MAX_BY(FAILURE_REASON, UPDATED_AT)         AS fr,
    MAX_BY(FAILURE_SUBREASON_CODE, UPDATED_AT) AS fsc,
    MAX(CASE WHEN OTP_VERIFIED=TRUE OR INSTALLATION_COMPLETED_AT IS NOT NULL
             OR COMPLETED_STEP>=7 THEN 1 ELSE 0 END) AS has_installed,
    MAX(CASE WHEN CONFIRMED_SLOT_AT IS NOT NULL THEN 1 ELSE 0 END) AS reached_slot,
    TO_DATE(DATEADD(minute, 330, MAX(UPDATED_AT))) AS last_date
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES
  WHERE _FIVETRAN_ACTIVE=TRUE AND CSP_ID IS NOT NULL
    AND UPDATED_AT >= DATEADD(day, -120, CURRENT_DATE)
  GROUP BY CONNECTION_ID, CSP_ID
),
bucketed AS (
  SELECT *,
    CASE
      WHEN has_installed=1 THEN 'installed'
      WHEN last_state='DECLINED' THEN 'csp_denied'
      WHEN last_state='CANCELLED_BY_UPSTREAM' AND fr='TIMEOUT_P74' AND fsc='CSP_NO_SHOW' AND rc='ALLOCATION_ACCEPTED' THEN 'csp_no_show'
      WHEN fsc='CSP_NO_SHOW' THEN 'csp_abandoned'
      WHEN last_state='CANCELLED_BY_UPSTREAM' AND rc='TIMEOUT_P41' THEN 'csp_timeout'
      WHEN last_state='CANCELLED_BY_CUSTOMER' AND reached_slot=1 THEN 'cust_cancel_after_slot'
      WHEN last_state='CANCELLED_BY_CUSTOMER' AND reached_slot=0 THEN 'cust_cancel_before_slot'
      WHEN last_state='INSTALLATION_REPORTED_FAILED' THEN 'install_failed'
      WHEN last_state='CANCELLED_BY_UPSTREAM' THEN 'system_other'
      WHEN last_state='INSTALLATION_CANCELLED_ONSITE' THEN 'cancelled_onsite'
      ELSE 'open'
    END AS bucket
  FROM base
),
per_csp AS (
  SELECT CSP_ID,
    CASE WHEN last_date >= DATE '2026-07-01' THEN 'july'
         WHEN last_date >= DATE '2026-06-01' AND last_date < DATE '2026-07-01' THEN 'june'
    END AS period,
    COUNT_IF(bucket='installed' AND reached_slot=1)                       AS installs,
    COUNT_IF(reached_slot=1 AND bucket NOT IN ('open','system_other'))    AS denom
  FROM bucketed
  GROUP BY CSP_ID,
    CASE WHEN last_date >= DATE '2026-07-01' THEN 'july'
         WHEN last_date >= DATE '2026-06-01' AND last_date < DATE '2026-07-01' THEN 'june' END
),
cat AS (
  SELECT CSP_ID, period, installs, denom,
    installs / NULLIF(denom, 0)::float AS eff,
    CASE WHEN CSP_ID IN ('a0a6y4','a0a6y6','a0a6y9','a0a6z0','a0a6z1','a0a6z2','a0a6z4','a0a6z7','a0a6z8','a0a7a0','a0a7a2','a0a7a3','a0a7a4','a0a7a5','a0a7a6','a0a7a7','a0a7a9','a0a7b1','a0a7b2','a0a7b3','a0a7b4','a0a7b5','a0a7b6','a0a7b7','a0a7b8','a0a7b9','a0a7c0','a0a7c1','a0a7c2','a0a7c4','a0a7c7','a0a7d3','a0a7d4','a0a7d9','a0a7e3','a0a7e4','a0a7f5','a0a7f8','a0a7g0','a0a7g2','a0a7g5','a0a7g6','a0a7g7','a0a7g9','a0a7h2','a0a8a5','a0a9j4','a0a9m4','a0a9o4','a0a9s3','a0a9w2','a0b0n9','a0b0w0','a0b1b5','a0b3m4','a0b5l8','a0b5l9','a0b5m0','a0b5m1','a0b5m3','a0b5m5','a0b5m6','a0b5n2','a0b5n3','a0b5n7','a0b5n8','a0b5o0','a0b5o3','a0b5o4','a0b5o5','a0b5p5','a0b5p7','a0b5q6','a0b5q7','a0b5r2','a0b5r4','a0b5r7','a0b5r9','a0b5s4','a0b5t0','a0b5t3','a0b5t5','a0b5t9','a0b5u1','a0b5v0','a0b5v3','a0b5v4','a0b5v5','a0b5v7','a0b5v8','a0b5w1','a0b5w4','a0b5w5','a0b5w9','a0b5x0','a0b5x1','a0b5y1','a0b5y3','a0b5y5','a0b5y9','a0b5z0','a0b5z1','a0b5z6','a0b5z7','a0b6a1','a0b6a3','a0b6a6','a0b6a8','a0b6a9','a0b6b1','a0b6b2','a0b6b5','a0b6b8','a0b6c4','a0b6c5','a0b6c6','a0b6d0','a0b6d1','a0b6d3','a0b6d4','a0b6d8','a0b6e0','a0b6e2','a0b6e3','a0b6e6','a0b6e7','a0b6e8','a0b6f0','a0b6f1','a0b6f2','a0b6f3','a0b6f5','a0b6f6','a0b6f7','a0b6f8','a0b6f9','a0b6g1','a0b6g2','a0b6g6','a0b6g9','a0b6h2','a0b6h3','a0b6h4','a0b6h5','a0b6h6','a0b6h8','a0b6h9','a0b6i0','a0b6i1','a0b6i2','a0b6i4','a0b6i8','a0b6j2','a0b6j7','a0b6j8','a0b6k4','a0b6k8','a0b6l2','a0b6l3','a0b6l6','a0b6l7','a0b6m3','a0b6m4','a0b6m6','a0b6n2','a0b6n3','a0b6o1','a0b6o2','a0b6o4','a0b6o5','a0b6o8','a0b6p0','a0b6p1','a0b6p3','a0b6p7','a0b6p8','a0b6p9','a0b6q5','a0b6q6','a0b6q9','a0b6r1','a0b6r4','a0b6r6','a0b6r8','a0b6s7','a0b6t0','a0b6t1','a0b6t2','a0b6t3','a0b6t7','a0b6t9','a0b6u0','a0b6u2','a0b6u3','a0b6u4','a0b6u5','a0b6u7','a0b6u8','a0b6v0','a0b6v1','a0b6v3','a0b6v8','a0b6w0','a0b6w1','a0b6w2','a0b6w7','a0b6w8','a0b6x2','a0b6x3','a0b6x6','a0b6x8','a0b6x9','a0b6y1','a0b6y2','a0b6y3','a0b6y5','a0b6y6','a0b6y7','a0b6y8','a0b6z2','a0b6z9','a0b7a1','a0b7a2','a0b7a3','a0b7a4','a0b7a9','a0b7b1','a0b7b4','a0b7b5','a0b7b7','a0b7c1','a0b7c2','a0b7c3','a0b7c6','a0b7c7','a0b7d0','a0b7d1','a0b7e3','a0b7e5','a0b7e6','a0b7e7','a0b7f2','a0b7f6','a0b7g1','a0b7g4','a0b7g5','a0b7g6','a0b7g7','a0b7h0','a0b7h5','a0b7h8','a0b7i0','a0b7i6','a0b7i7','a0b7j1','a0b7j2','a0b7j4','a0b8o2','a0b8o3','a0b8o4','a0b8o5','a0b8o7','a0b8o8','a0b8p2','a0b8p6','a0b8q2','a0b8r0','a0b8r1','a0b8r4','a0b8r5','a0b8r9','a0b8s0','a0b8s1','a0b8s3','a0b8s4','a0b8s7','a0b8u2','a0b8u9','a0b8v3','a0b8v4','a0b8v5','a0b8v8','a0b8v9','a0b8w1','a0b8w5','a0b8w6','a0b8w7','a0b8w8','a0b8x0','a0b8x3','a0b8x4','a0b8x6','a0b8y0','a0b8y2','a0b8y3','a0b8y6','a0b8y7','a0b8y8','a0b8y9','a0b8z0','a0b8z1','a0b8z7','a0b9a0','a0b9a2','a0b9a4','a0b9a8','a0b9a9','a0b9b5','a0b9b9','a0b9c0','a0b9c1','a0b9c2','a0b9c5','a0b9c8','a0b9c9','a0b9d2','a0b9d5','a0b9d9','a0b9e3','a0b9f2','a0b9g3','a0b9g4','a0b9g7','a0b9g8','a0b9h2','a0b9h4','a0b9h5','a0b9h6','a0b9i0','a0b9i5','a0b9i8','a0b9j0','a0b9j1','a0b9j3','a0b9j5','a0b9j6','a0b9j7','a0b9k1','a0b9k9','a0b9l3','a0b9l5','a0b9l6','a0b9l8','a0b9m2','a0b9m4','a0b9m6','a0b9m7','a0b9m8','a0b9n1','a0b9n2','a0b9n5','a0b9n6','a0b9n7','a0b9o4','a0b9p0','a0b9p1','a0b9p2','a0b9p4','a0b9p5','a0b9p6','a0b9p7','a0b9q0','a0b9q4','a0b9q7','a0b9r3','a0b9r4','a0b9r9','a0b9s4','a0b9s6','a0b9s8','a0b9t2','a0b9t7','a0b9u0','a0b9u7','a0b9v1','a0b9v5','a0b9v8','a0b9v9','a0b9w5','a0b9w7','a0b9w8','a0b9x1','a0b9x3','a0b9x5','a0b9x8','a0b9x9','a0b9y0','a0b9y2','a0b9y3','a0b9y4','a0b9y5','a0b9y9','a0b9z2','a0b9z4','a0b9z6','a0b9z7','a0b9z9','a0c0a0','a0c0a1','a0c0a2','a0c0a5','a0c0a6','a0c0a9','a0c0b4','a0c0b5','a0c0b6','a0c0c0','a0c0c3','a0c0c7','a0c0c8','a0c0c9','a0c0e1','a0c0e2','a0c0e4','a0c0e6','a0c0e9','a0c0f0','a0c0f2','a0c0f3','a0c0f6','a0c0g0','a0c0g1','a0c0g4','a0c0g7','a0c0g8','a0c0g9','a0c0h3','a0c0i5','a0c0j1')   THEN 'enrolled'
         WHEN CSP_ID IN ('a0a6z3','a0a7a1','a0a7c3','a0a7c5','a0a7c6','a0a7d1','a0a7d2','a0a7d5','a0a7d6','a0a7e0','a0a7f3','a0a7f7','a0a7g3','a0a7h0','a0a7h1','a0a9d4','a0b0a0','a0b2v8','a0b2w1','a0b3l5','a0b5m4','a0b5m8','a0b5n0','a0b5n4','a0b5n5','a0b5n6','a0b5o1','a0b5o6','a0b5p0','a0b5p1','a0b5p4','a0b5q8','a0b5r5','a0b5s1','a0b5s8','a0b5t4','a0b5u0','a0b5u2','a0b5u7','a0b5u8','a0b5w6','a0b5w8','a0b5x3','a0b5x4','a0b5x6','a0b5y2','a0b5y6','a0b6a0','a0b6b0','a0b6b6','a0b6c7','a0b6d6','a0b6g0','a0b6h7','a0b6j1','a0b6j4','a0b6k3','a0b6l0','a0b6l4','a0b6m0','a0b6n9','a0b6p6','a0b6q2','a0b6q3','a0b6q8','a0b6r3','a0b6s9','a0b6t5','a0b6u1','a0b6u9','a0b6v7','a0b6x4','a0b6x5','a0b6z4','a0b6z7','a0b7a0','a0b7c0','a0b7c4','a0b7c9','a0b7d3','a0b7f3','a0b7f7','a0b7h1','a0b7h4','a0b7i2','a0b7i4','a0b7i5','a0b8o1','a0b8o6','a0b8p3','a0b8p8','a0b8q1','a0b8q5','a0b8q8','a0b8t7','a0b8t8','a0b8u0','a0b8u7','a0b8v1','a0b8v7','a0b8w3','a0b9a1','a0b9a6','a0b9c7','a0b9e1','a0b9e7','a0b9f0','a0b9f6','a0b9f8','a0b9g5','a0b9h8','a0b9h9','a0b9i9','a0b9j9','a0b9l1','a0b9m1','a0b9o3','a0b9o9','a0b9q5','a0b9r2','a0b9r7','a0b9r8','a0b9s0','a0b9s2','a0b9s9','a0b9t5','a0b9v2','a0b9y6','a0b9y8','a0b9z1','a0b9z5','a0c0a8','a0c0b1','a0c0b7','a0c0d5','a0c0e8','a0c0f9','a0c0g5','a0c0h4','a0c0h5') THEN 'eligible'
         ELSE 'nonmbg' END AS category
  FROM per_csp
  WHERE period IS NOT NULL AND denom > 0
)
SELECT period AS PERIOD, category AS CATEGORY,
  COUNT(*)                                   AS PARTNERS,
  SUM(denom)                                 AS LEADS,
  SUM(installs)                              AS INSTALLS,
  ROUND(100.0 * SUM(installs) / NULLIF(SUM(denom), 0), 1) AS AGG_EFF,
  COUNT_IF(eff > 0.60)                        AS SECURED,
  ROUND(100.0 * COUNT_IF(eff > 0.60) / COUNT(*), 1) AS PCT_SECURED
FROM cat
GROUP BY 1, 2
ORDER BY 1, 2
