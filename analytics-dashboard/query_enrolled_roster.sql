-- Enrolled MBG (Kamai Kavach) roster breakdown for July -- headline visibility table.
-- Universe = the 429 enrolled CSPs (same list as query_efficiency.sql), LEFT JOINed to July
-- metrics so partners with NO resolved leads still appear. Mirrors the live program calc
-- (one row per (CONNECTION_ID, CSP_ID), final state via MAX_BY, 120-day window).
--   with_leads  = enrolled partners with >=1 slot-confirmed lead that reached an end state in July (denom>0)
--   eff_60_plus = of those, installs/leads > 0.60 (cleared the gate, "secured")
--   eff_60_minus= of those, installs/leads <= 0.60 (below the gate; includes exactly-60)
--   pending_only= no resolved lead yet but has open pipeline
--   no_activity = no leads at all this month
-- Split base for 60%+/- is with_leads (292), per the (B) framing on the dashboard.
WITH enrolled AS (
  SELECT CSP_ID FROM VALUES ('a0a6y4'),('a0a6y6'),('a0a6y9'),('a0a6z0'),('a0a6z1'),('a0a6z2'),('a0a6z4'),('a0a6z7'),('a0a6z8'),('a0a7a0'),('a0a7a2'),('a0a7a3'),('a0a7a4'),('a0a7a5'),('a0a7a6'),('a0a7a7'),('a0a7a9'),('a0a7b1'),('a0a7b2'),('a0a7b3'),('a0a7b4'),('a0a7b5'),('a0a7b6'),('a0a7b7'),('a0a7b8'),('a0a7b9'),('a0a7c0'),('a0a7c1'),('a0a7c2'),('a0a7c4'),('a0a7c7'),('a0a7d3'),('a0a7d4'),('a0a7d9'),('a0a7e3'),('a0a7e4'),('a0a7f5'),('a0a7f8'),('a0a7g0'),('a0a7g2'),('a0a7g5'),('a0a7g6'),('a0a7g7'),('a0a7g9'),('a0a7h2'),('a0a8a5'),('a0a9j4'),('a0a9m4'),('a0a9o4'),('a0a9s3'),('a0a9w2'),('a0b0n9'),('a0b0w0'),('a0b1b5'),('a0b3m4'),('a0b5l8'),('a0b5l9'),('a0b5m0'),('a0b5m1'),('a0b5m3'),('a0b5m5'),('a0b5m6'),('a0b5n2'),('a0b5n3'),('a0b5n7'),('a0b5n8'),('a0b5o0'),('a0b5o3'),('a0b5o4'),('a0b5o5'),('a0b5p5'),('a0b5p7'),('a0b5q6'),('a0b5q7'),('a0b5r2'),('a0b5r4'),('a0b5r7'),('a0b5r9'),('a0b5s4'),('a0b5t0'),('a0b5t3'),('a0b5t5'),('a0b5t9'),('a0b5u1'),('a0b5v0'),('a0b5v3'),('a0b5v4'),('a0b5v5'),('a0b5v7'),('a0b5v8'),('a0b5w1'),('a0b5w4'),('a0b5w5'),('a0b5w9'),('a0b5x0'),('a0b5x1'),('a0b5y1'),('a0b5y3'),('a0b5y5'),('a0b5y9'),('a0b5z0'),('a0b5z1'),('a0b5z6'),('a0b5z7'),('a0b6a1'),('a0b6a3'),('a0b6a6'),('a0b6a8'),('a0b6a9'),('a0b6b1'),('a0b6b2'),('a0b6b5'),('a0b6b8'),('a0b6c4'),('a0b6c5'),('a0b6c6'),('a0b6d0'),('a0b6d1'),('a0b6d3'),('a0b6d4'),('a0b6d8'),('a0b6e0'),('a0b6e2'),('a0b6e3'),('a0b6e6'),('a0b6e7'),('a0b6e8'),('a0b6f0'),('a0b6f1'),('a0b6f2'),('a0b6f3'),('a0b6f5'),('a0b6f6'),('a0b6f7'),('a0b6f8'),('a0b6f9'),('a0b6g1'),('a0b6g2'),('a0b6g6'),('a0b6g9'),('a0b6h2'),('a0b6h3'),('a0b6h4'),('a0b6h5'),('a0b6h6'),('a0b6h8'),('a0b6h9'),('a0b6i0'),('a0b6i1'),('a0b6i2'),('a0b6i4'),('a0b6i8'),('a0b6j2'),('a0b6j7'),('a0b6j8'),('a0b6k4'),('a0b6k8'),('a0b6l2'),('a0b6l3'),('a0b6l6'),('a0b6l7'),('a0b6m3'),('a0b6m4'),('a0b6m6'),('a0b6n2'),('a0b6n3'),('a0b6o1'),('a0b6o2'),('a0b6o4'),('a0b6o5'),('a0b6o8'),('a0b6p0'),('a0b6p1'),('a0b6p3'),('a0b6p7'),('a0b6p8'),('a0b6p9'),('a0b6q5'),('a0b6q6'),('a0b6q9'),('a0b6r1'),('a0b6r4'),('a0b6r6'),('a0b6r8'),('a0b6s7'),('a0b6t0'),('a0b6t1'),('a0b6t2'),('a0b6t3'),('a0b6t7'),('a0b6t9'),('a0b6u0'),('a0b6u2'),('a0b6u3'),('a0b6u4'),('a0b6u5'),('a0b6u7'),('a0b6u8'),('a0b6v0'),('a0b6v1'),('a0b6v3'),('a0b6v8'),('a0b6w0'),('a0b6w1'),('a0b6w2'),('a0b6w7'),('a0b6w8'),('a0b6x2'),('a0b6x3'),('a0b6x6'),('a0b6x8'),('a0b6x9'),('a0b6y1'),('a0b6y2'),('a0b6y3'),('a0b6y5'),('a0b6y6'),('a0b6y7'),('a0b6y8'),('a0b6z2'),('a0b6z9'),('a0b7a1'),('a0b7a2'),('a0b7a3'),('a0b7a4'),('a0b7a9'),('a0b7b1'),('a0b7b4'),('a0b7b5'),('a0b7b7'),('a0b7c1'),('a0b7c2'),('a0b7c3'),('a0b7c6'),('a0b7c7'),('a0b7d0'),('a0b7d1'),('a0b7e3'),('a0b7e5'),('a0b7e6'),('a0b7e7'),('a0b7f2'),('a0b7f6'),('a0b7g1'),('a0b7g4'),('a0b7g5'),('a0b7g6'),('a0b7g7'),('a0b7h0'),('a0b7h5'),('a0b7h8'),('a0b7i0'),('a0b7i6'),('a0b7i7'),('a0b7j1'),('a0b7j2'),('a0b7j4'),('a0b8o2'),('a0b8o3'),('a0b8o4'),('a0b8o5'),('a0b8o7'),('a0b8o8'),('a0b8p2'),('a0b8p6'),('a0b8q2'),('a0b8r0'),('a0b8r1'),('a0b8r4'),('a0b8r5'),('a0b8r9'),('a0b8s0'),('a0b8s1'),('a0b8s3'),('a0b8s4'),('a0b8s7'),('a0b8u2'),('a0b8u9'),('a0b8v3'),('a0b8v4'),('a0b8v5'),('a0b8v8'),('a0b8v9'),('a0b8w1'),('a0b8w5'),('a0b8w6'),('a0b8w7'),('a0b8w8'),('a0b8x0'),('a0b8x3'),('a0b8x4'),('a0b8x6'),('a0b8y0'),('a0b8y2'),('a0b8y3'),('a0b8y6'),('a0b8y7'),('a0b8y8'),('a0b8y9'),('a0b8z0'),('a0b8z1'),('a0b8z7'),('a0b9a0'),('a0b9a2'),('a0b9a4'),('a0b9a8'),('a0b9a9'),('a0b9b5'),('a0b9b9'),('a0b9c0'),('a0b9c1'),('a0b9c2'),('a0b9c5'),('a0b9c8'),('a0b9c9'),('a0b9d2'),('a0b9d5'),('a0b9d9'),('a0b9e3'),('a0b9f2'),('a0b9g3'),('a0b9g4'),('a0b9g7'),('a0b9g8'),('a0b9h2'),('a0b9h4'),('a0b9h5'),('a0b9h6'),('a0b9i0'),('a0b9i5'),('a0b9i8'),('a0b9j0'),('a0b9j1'),('a0b9j3'),('a0b9j5'),('a0b9j6'),('a0b9j7'),('a0b9k1'),('a0b9k9'),('a0b9l3'),('a0b9l5'),('a0b9l6'),('a0b9l8'),('a0b9m2'),('a0b9m4'),('a0b9m6'),('a0b9m7'),('a0b9m8'),('a0b9n1'),('a0b9n2'),('a0b9n5'),('a0b9n6'),('a0b9n7'),('a0b9o4'),('a0b9p0'),('a0b9p1'),('a0b9p2'),('a0b9p4'),('a0b9p5'),('a0b9p6'),('a0b9p7'),('a0b9q0'),('a0b9q4'),('a0b9q7'),('a0b9r3'),('a0b9r4'),('a0b9r9'),('a0b9s4'),('a0b9s6'),('a0b9s8'),('a0b9t2'),('a0b9t7'),('a0b9u0'),('a0b9u7'),('a0b9v1'),('a0b9v5'),('a0b9v8'),('a0b9v9'),('a0b9w5'),('a0b9w7'),('a0b9w8'),('a0b9x1'),('a0b9x3'),('a0b9x5'),('a0b9x8'),('a0b9x9'),('a0b9y0'),('a0b9y2'),('a0b9y3'),('a0b9y4'),('a0b9y5'),('a0b9y9'),('a0b9z2'),('a0b9z4'),('a0b9z6'),('a0b9z7'),('a0b9z9'),('a0c0a0'),('a0c0a1'),('a0c0a2'),('a0c0a5'),('a0c0a6'),('a0c0a9'),('a0c0b4'),('a0c0b5'),('a0c0b6'),('a0c0c0'),('a0c0c3'),('a0c0c7'),('a0c0c8'),('a0c0c9'),('a0c0e1'),('a0c0e2'),('a0c0e4'),('a0c0e6'),('a0c0e9'),('a0c0f0'),('a0c0f2'),('a0c0f3'),('a0c0f6'),('a0c0g0'),('a0c0g1'),('a0c0g4'),('a0c0g7'),('a0c0g8'),('a0c0g9'),('a0c0h3'),('a0c0i5'),('a0c0j1') AS v(CSP_ID)
),
base AS (
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
metrics AS (
  SELECT CSP_ID,
    COUNT_IF(bucket='installed' AND reached_slot=1 AND last_date >= DATE '2026-07-01') AS installs,
    COUNT_IF(reached_slot=1 AND bucket NOT IN ('open','system_other') AND last_date >= DATE '2026-07-01') AS leads,
    COUNT_IF(bucket='open') AS pending
  FROM bucketed
  GROUP BY CSP_ID
),
j AS (
  SELECT e.CSP_ID,
    COALESCE(m.installs,0) AS installs,
    COALESCE(m.leads,0)    AS leads,
    COALESCE(m.pending,0)  AS pending
  FROM enrolled e
  LEFT JOIN metrics m ON m.CSP_ID = e.CSP_ID
)
SELECT
  'ROSTER'                                       AS GRP,
  COUNT(*)                                       AS ENROLLED_TOTAL,
  COUNT_IF(leads > 0)                            AS WITH_LEADS,
  COUNT_IF(leads > 0 AND installs/leads >  0.60) AS EFF_60_PLUS,
  COUNT_IF(leads > 0 AND installs/leads <= 0.60) AS EFF_60_MINUS,
  COUNT_IF(leads = 0 AND pending > 0)            AS PENDING_ONLY,
  COUNT_IF(leads = 0 AND pending = 0)            AS NO_ACTIVITY,
  SUM(installs)                                  AS TOTAL_INSTALLS,
  SUM(leads)                                     AS TOTAL_LEADS
FROM j;
