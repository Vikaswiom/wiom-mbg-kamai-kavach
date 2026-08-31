WITH base AS (
  SELECT CONNECTION_ID, CSP_ID,
    MAX_BY(CURRENT_STATE, UPDATED_AT) AS last_state,
    MAX_BY(REASON_CODE, UPDATED_AT) AS rc,
    MAX_BY(FAILURE_REASON, UPDATED_AT) AS fr,
    MAX_BY(FAILURE_SUBREASON_CODE, UPDATED_AT) AS fsc,
    MAX_BY(EXECUTION_CANDIDATE_ID, UPDATED_AT) AS rep_ecid,  -- representative (latest) attempt
    MAX_BY(CREATED_AT, UPDATED_AT) AS offered,               -- CSP-offer date of that attempt
    MAX(CASE WHEN OTP_VERIFIED=TRUE OR INSTALLATION_COMPLETED_AT IS NOT NULL OR COMPLETED_STEP>=7 THEN 1 ELSE 0 END) AS has_installed,
    MAX(CASE WHEN CONFIRMED_SLOT_AT IS NOT NULL THEN 1 ELSE 0 END) AS reached_slot,
    -- the CURRENT attempt has a customer-confirmed slot (not sticky across retries:
    -- a connection retried after a failed slot-confirmed attempt must NOT keep it)
    CASE WHEN MAX_BY(CONFIRMED_SLOT_AT, UPDATED_AT) IS NOT NULL THEN 1 ELSE 0 END AS own_slot_latest,
    TO_DATE(DATEADD(minute,330,MAX(UPDATED_AT))) AS last_date
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES
  WHERE _FIVETRAN_ACTIVE=TRUE AND CSP_ID IS NOT NULL
    AND UPDATED_AT >= DATEADD(day,-120,CURRENT_DATE)
  GROUP BY CONNECTION_ID, CSP_ID
),
-- Denominator gate (payout-logic §3, Aug-2026): the bar is "customer confirmed
-- a slot" — the lead reached AWAITING_TECHNICIAN_ASSIGNMENT, i.e. reached_slot=1
-- (CONFIRMED_SLOT_AT IS NOT NULL). The new booking flow makes slot-confirmation
-- automatic at booking, so this (the pre-S4 rule) is the right proof-of-lead
-- again; the S4 hybrid slot/tech gate is retired. Technician-assigned is a later
-- funnel milestone, NOT the denom bar.
-- ⚠️ July was disbursed under the OLD S4 gate and is FROZEN — never rebuild
-- data-july.json with this SQL (refresh.py refuses --month july).
gated AS (
  SELECT b.*, b.reached_slot AS gate_ok
  FROM base b
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
      -- RETRY_EXHAUSTION = re-assigned until the retry cap blew; ~72% of those
      -- attempts died as CSP no-show/timeout, so it counts AGAINST the CSP
      -- (in denom), unlike the excused system_other catch-all below
      WHEN last_state='CANCELLED_BY_UPSTREAM' AND rc='RETRY_EXHAUSTION' THEN 'csp_retryx'
      WHEN last_state='CANCELLED_BY_UPSTREAM' THEN 'system_other'
      WHEN last_state='INSTALLATION_CANCELLED_ONSITE' THEN 'cancelled_onsite'
      -- terminal, not a phantom 'open' lead — expiry with last_date in July
      -- counts in the denom (CSP-side miss), expiry before July is excluded
      WHEN last_state='INSTALLATION_EXPIRED' THEN 'install_expired'
      ELSE 'open'
    END AS bucket
  FROM gated
),
-- The FULL enrolled roster (477 CSPs) — every enrolled CSP, not only the
-- mid-July joiners. JOINED = enrolment date where it matters for windowing
-- (July retro runs); NULL = enrolled before the program month starts.
-- Its main job now: KEEP-ALIVE — an enrolled CSP must appear in the output
-- even with zero activity, so the settle screen renders the noleads case
-- and never "हिसाब तैयार नहीं". REFRESH when CSPs enrol (enrolled-CSPs sheet).
enrol AS (
  SELECT * FROM VALUES
    ('a0a6y4',NULL::date),
    ('a0a6y6','2026-07-02'::date),
    ('a0a6y9',NULL::date),
    ('a0a6z0',NULL::date),
    ('a0a6z1',NULL::date),
    ('a0a6z2',NULL::date),
    ('a0a6z3','2026-07-10'::date),
    ('a0a6z4',NULL::date),
    ('a0a6z7',NULL::date),
    ('a0a6z8',NULL::date),
    ('a0a7a0',NULL::date),
    ('a0a7a2',NULL::date),
    ('a0a7a3',NULL::date),
    ('a0a7a4',NULL::date),
    ('a0a7a5',NULL::date),
    ('a0a7a6',NULL::date),
    ('a0a7a7',NULL::date),
    ('a0a7a9',NULL::date),
    ('a0a7b1',NULL::date),
    ('a0a7b2',NULL::date),
    ('a0a7b3',NULL::date),
    ('a0a7b4',NULL::date),
    ('a0a7b5','2026-07-05'::date),
    ('a0a7b6',NULL::date),
    ('a0a7b7',NULL::date),
    ('a0a7b8',NULL::date),
    ('a0a7b9',NULL::date),
    ('a0a7c0',NULL::date),
    ('a0a7c1',NULL::date),
    ('a0a7c2',NULL::date),
    ('a0a7c4',NULL::date),
    ('a0a7c5','2026-07-19'::date),
    ('a0a7c6','2026-07-14'::date),
    ('a0a7c7','2026-07-05'::date),
    ('a0a7d1','2026-07-14'::date),
    ('a0a7d2','2026-07-10'::date),
    ('a0a7d3',NULL::date),
    ('a0a7d4',NULL::date),
    ('a0a7d9',NULL::date),
    ('a0a7e3',NULL::date),
    ('a0a7e4',NULL::date),
    ('a0a7f5',NULL::date),
    ('a0a7f7','2026-07-02'::date),
    ('a0a7f8',NULL::date),
    ('a0a7g0',NULL::date),
    ('a0a7g2',NULL::date),
    ('a0a7g3','2026-07-10'::date),
    ('a0a7g5',NULL::date),
    ('a0a7g6',NULL::date),
    ('a0a7g7',NULL::date),
    ('a0a7g9',NULL::date),
    ('a0a7h0','2026-07-10'::date),
    ('a0a7h2',NULL::date),
    ('a0a8a5',NULL::date),
    ('a0a9d4','2026-07-10'::date),
    ('a0a9j4',NULL::date),
    ('a0a9m4',NULL::date),
    ('a0a9o4',NULL::date),
    ('a0a9s3',NULL::date),
    ('a0a9w2',NULL::date),
    ('a0b0a0','2026-07-10'::date),
    ('a0b0n9',NULL::date),
    ('a0b0w0',NULL::date),
    ('a0b1b5',NULL::date),
    ('a0b2w1','2026-07-08'::date),
    ('a0b3l5','2026-07-10'::date),
    ('a0b3m4',NULL::date),
    ('a0b5l8',NULL::date),
    ('a0b5l9','2026-07-02'::date),
    ('a0b5m0',NULL::date),
    ('a0b5m1',NULL::date),
    ('a0b5m3',NULL::date),
    ('a0b5m5','2026-07-02'::date),
    ('a0b5m6',NULL::date),
    ('a0b5n2',NULL::date),
    ('a0b5n3',NULL::date),
    ('a0b5n4','2026-07-10'::date),
    ('a0b5n7',NULL::date),
    ('a0b5n8',NULL::date),
    ('a0b5o0',NULL::date),
    ('a0b5o3',NULL::date),
    ('a0b5o4',NULL::date),
    ('a0b5o5',NULL::date),
    ('a0b5p0','2026-07-13'::date),
    ('a0b5p5','2026-07-03'::date),
    ('a0b5p7',NULL::date),
    ('a0b5q6',NULL::date),
    ('a0b5q7',NULL::date),
    ('a0b5r2',NULL::date),
    ('a0b5r4',NULL::date),
    ('a0b5r7',NULL::date),
    ('a0b5r9',NULL::date),
    ('a0b5s4',NULL::date),
    ('a0b5t0',NULL::date),
    ('a0b5t3',NULL::date),
    ('a0b5t5',NULL::date),
    ('a0b5t9',NULL::date),
    ('a0b5u1',NULL::date),
    ('a0b5u8','2026-07-06'::date),
    ('a0b5v0','2026-07-05'::date),
    ('a0b5v3','2026-07-02'::date),
    ('a0b5v4',NULL::date),
    ('a0b5v5',NULL::date),
    ('a0b5v7',NULL::date),
    ('a0b5v8',NULL::date),
    ('a0b5w1',NULL::date),
    ('a0b5w4',NULL::date),
    ('a0b5w5',NULL::date),
    ('a0b5w9','2026-07-05'::date),
    ('a0b5x0',NULL::date),
    ('a0b5x1',NULL::date),
    ('a0b5y1','2026-07-02'::date),
    ('a0b5y3',NULL::date),
    ('a0b5y5','2026-07-07'::date),
    ('a0b5y6','2026-07-06'::date),
    ('a0b5y9',NULL::date),
    ('a0b5z0',NULL::date),
    ('a0b5z1','2026-07-04'::date),
    ('a0b5z6',NULL::date),
    ('a0b5z7','2026-07-09'::date),
    ('a0b6a1',NULL::date),
    ('a0b6a3','2026-07-02'::date),
    ('a0b6a6','2026-07-03'::date),
    ('a0b6a8',NULL::date),
    ('a0b6a9',NULL::date),
    ('a0b6b0','2026-07-10'::date),
    ('a0b6b1',NULL::date),
    ('a0b6b2','2026-07-02'::date),
    ('a0b6b5',NULL::date),
    ('a0b6b6','2026-07-27'::date),
    ('a0b6b8',NULL::date),
    ('a0b6c4',NULL::date),
    ('a0b6c5',NULL::date),
    ('a0b6c6',NULL::date),
    ('a0b6d0',NULL::date),
    ('a0b6d1','2026-07-04'::date),
    ('a0b6d3',NULL::date),
    ('a0b6d4',NULL::date),
    ('a0b6d8',NULL::date),
    ('a0b6e0',NULL::date),
    ('a0b6e2','2026-07-11'::date),
    ('a0b6e3',NULL::date),
    ('a0b6e6','2026-07-08'::date),
    ('a0b6e7','2026-07-02'::date),
    ('a0b6e8',NULL::date),
    ('a0b6f0',NULL::date),
    ('a0b6f1','2026-07-02'::date),
    ('a0b6f2',NULL::date),
    ('a0b6f3',NULL::date),
    ('a0b6f5',NULL::date),
    ('a0b6f6',NULL::date),
    ('a0b6f7',NULL::date),
    ('a0b6f8',NULL::date),
    ('a0b6f9',NULL::date),
    ('a0b6g1','2026-07-03'::date),
    ('a0b6g2',NULL::date),
    ('a0b6g6','2026-07-04'::date),
    ('a0b6g9',NULL::date),
    ('a0b6h2','2026-07-02'::date),
    ('a0b6h3',NULL::date),
    ('a0b6h4',NULL::date),
    ('a0b6h5',NULL::date),
    ('a0b6h6','2026-07-02'::date),
    ('a0b6h7','2026-07-10'::date),
    ('a0b6h8',NULL::date),
    ('a0b6h9',NULL::date),
    ('a0b6i0',NULL::date),
    ('a0b6i1',NULL::date),
    ('a0b6i2','2026-07-05'::date),
    ('a0b6i4',NULL::date),
    ('a0b6i8',NULL::date),
    ('a0b6j2',NULL::date),
    ('a0b6j7',NULL::date),
    ('a0b6j8',NULL::date),
    ('a0b6k4',NULL::date),
    ('a0b6k8',NULL::date),
    ('a0b6l0','2026-07-10'::date),
    ('a0b6l2',NULL::date),
    ('a0b6l3',NULL::date),
    ('a0b6l6',NULL::date),
    ('a0b6l7',NULL::date),
    ('a0b6m0',NULL::date),
    ('a0b6m3',NULL::date),
    ('a0b6m4','2026-07-09'::date),
    ('a0b6m6',NULL::date),
    ('a0b6n2',NULL::date),
    ('a0b6n3',NULL::date),
    ('a0b6o1',NULL::date),
    ('a0b6o2',NULL::date),
    ('a0b6o4',NULL::date),
    ('a0b6o5',NULL::date),
    ('a0b6o8',NULL::date),
    ('a0b6p0','2026-07-02'::date),
    ('a0b6p1',NULL::date),
    ('a0b6p3',NULL::date),
    ('a0b6p7',NULL::date),
    ('a0b6p8',NULL::date),
    ('a0b6p9',NULL::date),
    ('a0b6q3','2026-07-10'::date),
    ('a0b6q5',NULL::date),
    ('a0b6q6',NULL::date),
    ('a0b6q9',NULL::date),
    ('a0b6r1','2026-07-02'::date),
    ('a0b6r4',NULL::date),
    ('a0b6r6','2026-07-02'::date),
    ('a0b6r8',NULL::date),
    ('a0b6s7',NULL::date),
    ('a0b6t0',NULL::date),
    ('a0b6t1',NULL::date),
    ('a0b6t2',NULL::date),
    ('a0b6t3',NULL::date),
    ('a0b6t7',NULL::date),
    ('a0b6t9',NULL::date),
    ('a0b6u0',NULL::date),
    ('a0b6u2','2026-07-02'::date),
    ('a0b6u3','2026-07-02'::date),
    ('a0b6u4','2026-07-03'::date),
    ('a0b6u5',NULL::date),
    ('a0b6u7','2026-07-02'::date),
    ('a0b6u8',NULL::date),
    ('a0b6u9','2026-07-10'::date),
    ('a0b6v0',NULL::date),
    ('a0b6v1',NULL::date),
    ('a0b6v3',NULL::date),
    ('a0b6v8',NULL::date),
    ('a0b6w0','2026-07-11'::date),
    ('a0b6w1',NULL::date),
    ('a0b6w2',NULL::date),
    ('a0b6w7','2026-07-03'::date),
    ('a0b6w8',NULL::date),
    ('a0b6x2',NULL::date),
    ('a0b6x3',NULL::date),
    ('a0b6x5','2026-07-10'::date),
    ('a0b6x6','2026-07-02'::date),
    ('a0b6x8',NULL::date),
    ('a0b6x9',NULL::date),
    ('a0b6y1',NULL::date),
    ('a0b6y2',NULL::date),
    ('a0b6y3',NULL::date),
    ('a0b6y5',NULL::date),
    ('a0b6y6',NULL::date),
    ('a0b6y7',NULL::date),
    ('a0b6y8',NULL::date),
    ('a0b6z2',NULL::date),
    ('a0b6z7','2026-07-15'::date),
    ('a0b6z9',NULL::date),
    ('a0b7a1',NULL::date),
    ('a0b7a2',NULL::date),
    ('a0b7a3',NULL::date),
    ('a0b7a4',NULL::date),
    ('a0b7a9','2026-07-02'::date),
    ('a0b7b1',NULL::date),
    ('a0b7b4',NULL::date),
    ('a0b7b5',NULL::date),
    ('a0b7b7',NULL::date),
    ('a0b7c1',NULL::date),
    ('a0b7c2',NULL::date),
    ('a0b7c3',NULL::date),
    ('a0b7c6',NULL::date),
    ('a0b7c7',NULL::date),
    ('a0b7d0','2026-07-02'::date),
    ('a0b7d1','2026-07-11'::date),
    ('a0b7d3',NULL::date),
    ('a0b7e3',NULL::date),
    ('a0b7e5',NULL::date),
    ('a0b7e6',NULL::date),
    ('a0b7e7','2026-07-02'::date),
    ('a0b7f2',NULL::date),
    ('a0b7f3','2026-07-10'::date),
    ('a0b7f6',NULL::date),
    ('a0b7g1',NULL::date),
    ('a0b7g4',NULL::date),
    ('a0b7g5',NULL::date),
    ('a0b7g6',NULL::date),
    ('a0b7g7',NULL::date),
    ('a0b7h0',NULL::date),
    ('a0b7h5',NULL::date),
    ('a0b7h8',NULL::date),
    ('a0b7i0',NULL::date),
    ('a0b7i2','2026-07-25'::date),
    ('a0b7i4','2026-07-08'::date),
    ('a0b7i5','2026-07-08'::date),
    ('a0b7i6',NULL::date),
    ('a0b7i7',NULL::date),
    ('a0b7j1',NULL::date),
    ('a0b7j2',NULL::date),
    ('a0b7j4',NULL::date),
    ('a0b8o1','2026-07-29'::date),
    ('a0b8o2',NULL::date),
    ('a0b8o3',NULL::date),
    ('a0b8o4',NULL::date),
    ('a0b8o5','2026-07-05'::date),
    ('a0b8o6','2026-07-03'::date),
    ('a0b8o7',NULL::date),
    ('a0b8o8',NULL::date),
    ('a0b8p2',NULL::date),
    ('a0b8p6',NULL::date),
    ('a0b8p8','2026-07-20'::date),
    ('a0b8q2',NULL::date),
    ('a0b8q5','2026-07-23'::date),
    ('a0b8r0',NULL::date),
    ('a0b8r1',NULL::date),
    ('a0b8r4',NULL::date),
    ('a0b8r5',NULL::date),
    ('a0b8r9','2026-07-04'::date),
    ('a0b8s0','2026-07-02'::date),
    ('a0b8s1',NULL::date),
    ('a0b8s3',NULL::date),
    ('a0b8s4',NULL::date),
    ('a0b8s7',NULL::date),
    ('a0b8u0','2026-07-18'::date),
    ('a0b8u2',NULL::date),
    ('a0b8u9',NULL::date),
    ('a0b8v3',NULL::date),
    ('a0b8v4',NULL::date),
    ('a0b8v5',NULL::date),
    ('a0b8v8',NULL::date),
    ('a0b8v9',NULL::date),
    ('a0b8w1',NULL::date),
    ('a0b8w3',NULL::date),
    ('a0b8w5','2026-07-02'::date),
    ('a0b8w6',NULL::date),
    ('a0b8w7',NULL::date),
    ('a0b8w8',NULL::date),
    ('a0b8x0',NULL::date),
    ('a0b8x3',NULL::date),
    ('a0b8x4',NULL::date),
    ('a0b8x6','2026-07-03'::date),
    ('a0b8y0',NULL::date),
    ('a0b8y2','2026-07-02'::date),
    ('a0b8y3',NULL::date),
    ('a0b8y6',NULL::date),
    ('a0b8y7',NULL::date),
    ('a0b8y8',NULL::date),
    ('a0b8y9',NULL::date),
    ('a0b8z0',NULL::date),
    ('a0b8z1','2026-07-08'::date),
    ('a0b8z7',NULL::date),
    ('a0b9a0',NULL::date),
    ('a0b9a1','2026-07-10'::date),
    ('a0b9a2',NULL::date),
    ('a0b9a4',NULL::date),
    ('a0b9a8',NULL::date),
    ('a0b9a9',NULL::date),
    ('a0b9b5','2026-07-02'::date),
    ('a0b9b9',NULL::date),
    ('a0b9c0',NULL::date),
    ('a0b9c1',NULL::date),
    ('a0b9c2',NULL::date),
    ('a0b9c5',NULL::date),
    ('a0b9c8',NULL::date),
    ('a0b9c9',NULL::date),
    ('a0b9d2',NULL::date),
    ('a0b9d5','2026-07-02'::date),
    ('a0b9d9',NULL::date),
    ('a0b9e1','2026-07-14'::date),
    ('a0b9e3','2026-07-02'::date),
    ('a0b9f2',NULL::date),
    ('a0b9f6','2026-07-16'::date),
    ('a0b9f8','2026-07-17'::date),
    ('a0b9g3',NULL::date),
    ('a0b9g4','2026-07-02'::date),
    ('a0b9g7',NULL::date),
    ('a0b9g8',NULL::date),
    ('a0b9h2',NULL::date),
    ('a0b9h4',NULL::date),
    ('a0b9h5','2026-07-07'::date),
    ('a0b9h6',NULL::date),
    ('a0b9h8','2026-07-10'::date),
    ('a0b9h9','2026-07-10'::date),
    ('a0b9i0',NULL::date),
    ('a0b9i5',NULL::date),
    ('a0b9i8',NULL::date),
    ('a0b9i9','2026-07-18'::date),
    ('a0b9j0',NULL::date),
    ('a0b9j1',NULL::date),
    ('a0b9j3',NULL::date),
    ('a0b9j5',NULL::date),
    ('a0b9j6',NULL::date),
    ('a0b9j7',NULL::date),
    ('a0b9k1',NULL::date),
    ('a0b9k9',NULL::date),
    ('a0b9l3',NULL::date),
    ('a0b9l5',NULL::date),
    ('a0b9l6',NULL::date),
    ('a0b9l8',NULL::date),
    ('a0b9m2',NULL::date),
    ('a0b9m4',NULL::date),
    ('a0b9m6','2026-07-10'::date),
    ('a0b9m7','2026-07-02'::date),
    ('a0b9m8',NULL::date),
    ('a0b9n1',NULL::date),
    ('a0b9n2',NULL::date),
    ('a0b9n5',NULL::date),
    ('a0b9n6',NULL::date),
    ('a0b9n7','2026-07-05'::date),
    ('a0b9o3','2026-07-15'::date),
    ('a0b9o4',NULL::date),
    ('a0b9p0',NULL::date),
    ('a0b9p1',NULL::date),
    ('a0b9p2',NULL::date),
    ('a0b9p4','2026-07-02'::date),
    ('a0b9p5',NULL::date),
    ('a0b9p6','2026-07-02'::date),
    ('a0b9p7',NULL::date),
    ('a0b9q0','2026-07-02'::date),
    ('a0b9q4',NULL::date),
    ('a0b9q7','2026-07-02'::date),
    ('a0b9r3',NULL::date),
    ('a0b9r4','2026-07-04'::date),
    ('a0b9r8','2026-07-10'::date),
    ('a0b9r9',NULL::date),
    ('a0b9s2','2026-07-10'::date),
    ('a0b9s4',NULL::date),
    ('a0b9s6',NULL::date),
    ('a0b9s8','2026-07-02'::date),
    ('a0b9t2',NULL::date),
    ('a0b9t7',NULL::date),
    ('a0b9u0','2026-07-02'::date),
    ('a0b9u7',NULL::date),
    ('a0b9v1',NULL::date),
    ('a0b9v5',NULL::date),
    ('a0b9v8',NULL::date),
    ('a0b9v9',NULL::date),
    ('a0b9w5',NULL::date),
    ('a0b9w7',NULL::date),
    ('a0b9w8',NULL::date),
    ('a0b9x1','2026-07-02'::date),
    ('a0b9x3','2026-07-04'::date),
    ('a0b9x5',NULL::date),
    ('a0b9x8',NULL::date),
    ('a0b9x9','2026-07-03'::date),
    ('a0b9y0',NULL::date),
    ('a0b9y2',NULL::date),
    ('a0b9y3',NULL::date),
    ('a0b9y4',NULL::date),
    ('a0b9y5',NULL::date),
    ('a0b9y6','2026-07-22'::date),
    ('a0b9y9',NULL::date),
    ('a0b9z2',NULL::date),
    ('a0b9z4',NULL::date),
    ('a0b9z6','2026-07-04'::date),
    ('a0b9z7',NULL::date),
    ('a0b9z9',NULL::date),
    ('a0c0a0',NULL::date),
    ('a0c0a1',NULL::date),
    ('a0c0a2',NULL::date),
    ('a0c0a5',NULL::date),
    ('a0c0a6',NULL::date),
    ('a0c0a9','2026-07-02'::date),
    ('a0c0b1','2026-07-06'::date),
    ('a0c0b4',NULL::date),
    ('a0c0b5',NULL::date),
    ('a0c0b6',NULL::date),
    ('a0c0c0',NULL::date),
    ('a0c0c3',NULL::date),
    ('a0c0c7',NULL::date),
    ('a0c0c8',NULL::date),
    ('a0c0c9',NULL::date),
    ('a0c0e1',NULL::date),
    ('a0c0e2',NULL::date),
    ('a0c0e4','2026-07-02'::date),
    ('a0c0e6','2026-07-03'::date),
    ('a0c0e9',NULL::date),
    ('a0c0f0',NULL::date),
    ('a0c0f2','2026-07-03'::date),
    ('a0c0f3',NULL::date),
    ('a0c0f6','2026-07-02'::date),
    ('a0c0g0',NULL::date),
    ('a0c0g1',NULL::date),
    ('a0c0g4',NULL::date),
    ('a0c0g7','2026-07-07'::date),
    ('a0c0g8',NULL::date),
    ('a0c0g9',NULL::date),
    ('a0c0h3',NULL::date),
    ('a0c0i5',NULL::date),
    ('a0c0j1','2026-07-07'::date)
  AS e(CSP_ID, JOINED)
),
-- ═══ MG METRIC (v3.0, 11-Aug-2026) ═══════════════════════════════════════════
-- Reproduces `sql/mg-metric.sql` — the authoritative definition:
--   NUMERATOR   installs done          (mbg_installs)
--   DENOMINATOR leads that reached "tech assigned" — EXECUTOR_ID IS NOT NULL
-- Source is the execution service (IEC), NOT the quality ledger. This SUPERSEDES
-- the 10-Aug on-time/M1 definition (sql/ontime-m1.sql): the numerator is ALL
-- installs again, so on-time vs late no longer changes a CSP's percentage.
-- Verified 11-Aug: installs really are a subset of tech-assigned (1102 of 2794
-- MTD, ZERO installs without an executor), so pct can never exceed 100.
--
-- Deviations from mg-metric.sql, both deliberate:
--  1. the month window is parameterised ({MS}/{ME}) and taken in IST, so
--     refresh.py can freeze each month's snapshot and retro-rebuild one month.
--     The source query has a lower bound only (DATE_TRUNC('month',CURRENT_DATE),
--     session UTC); for the live month the two agree.
--  2. `imp` — the impacted-booking rule from the payout spec is kept wired here
--     (an impacted connection drops out of the denominator UNLESS it installed).
--     It carries a dummy UUID = matches nothing, so it is a NO-OP until a real
--     list is pasted in, and mg-metric.sql's numbers are reproduced exactly.
imp AS (
  SELECT column1 AS conn FROM VALUES ('00000000-0000-0000-0000-000000000000')
),
mg_agg AS (   -- one row per (connection, CSP): install flag + tech-assigned flag
  SELECT iec.CONNECTION_ID, iec.CSP_ID,
    MAX(IFF(iec.OTP_VERIFIED=TRUE OR iec.INSTALLATION_COMPLETED_AT IS NOT NULL OR iec.COMPLETED_STEP>=7, 1, 0)) AS has_installed,
    MAX(IFF(iec.EXECUTOR_ID IS NOT NULL, 1, 0)) AS tech_assigned,
    TO_DATE(DATEADD(minute,330, MAX(iec.UPDATED_AT))) AS last_date
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES iec
  WHERE iec._FIVETRAN_ACTIVE
  GROUP BY 1, 2
),
mg AS (
  SELECT CSP_ID,
    SUM(IFF(has_installed=1 AND in_month, 1, 0)) AS installs,   -- NUMERATOR (mbg_installs)
    SUM(IFF(tech_assigned=1 AND in_month
            AND NOT (has_installed=0 AND CONNECTION_ID IN (SELECT conn FROM imp)), 1, 0)) AS denom  -- DENOMINATOR (mbg_leads)
  FROM (SELECT a.*, (last_date >= DATE '2026-08-01' /*{MS}*/
                     AND last_date < DATE '2026-09-01' /*{ME}*/) AS in_month
        FROM mg_agg a)
  GROUP BY CSP_ID
),
-- Reference only — the M1 on-time ledger numbers, carried in the snapshot so the
-- on-time view stays visible after v3.0 moved off it. NOTHING on the screens
-- reads these; they are for reconciliation and for answering "how many were
-- late?". Definition = sql/ontime-m1.sql (deduped to one row per CONNECTION).
led AS (
  SELECT CSP_ID,
    SUM(IFF(TERMINAL_OUTCOME='ON_TIME_ACTIVE',1,0)) AS ontime_m1,
    SUM(IFF(TERMINAL_OUTCOME='LATE_ACTIVE',1,0))    AS late_m1,
    SUM(IFF(TERMINAL_OUTCOME IN ('ON_TIME_ACTIVE','LATE_ACTIVE','REPORTED_FAILED','CANCELLED_ONSITE'),1,0)) AS leads_m1
  FROM (
    SELECT CSP_ID, CONNECTION_ID, TERMINAL_OUTCOME
    FROM PROD_DB.CSP_QUALITY_SERVICE_CSP_QUALITY_SERVICE.INSTALL_MATURATION_LEDGER
    WHERE TO_DATE(DATEADD(minute,330,TERMINAL_AT)) >= DATE '2026-08-01' /*{MS}*/
      AND TO_DATE(DATEADD(minute,330,TERMINAL_AT)) <  DATE '2026-09-01' /*{ME}*/
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONNECTION_ID ORDER BY TERMINAL_AT DESC NULLS LAST) = 1
  ) GROUP BY CSP_ID
),
-- Open-lead counts for the banner's `almost` screen and the ticket rows. These
-- keep the IEC bucket logic above (and its 120-day scan); the payout numbers do
-- not come from here any more.
metrics AS (
  SELECT b.CSP_ID,
    COUNT_IF(bucket='open') AS pending,
    COUNT_IF(bucket='open' AND own_slot_latest=1) AS committed
  FROM bucketed b
  GROUP BY b.CSP_ID
),
open_tk AS (
  SELECT CSP_ID, EXECUTION_CANDIDATE_ID, ZONE_ID, UPDATED_AT,
    CASE CURRENT_STATE
      WHEN 'ARRIVED_AT_SITE' THEN 8
      WHEN 'TECHNICIAN_ASSIGNED' THEN 7
      WHEN 'AWAITING_TECHNICIAN_ASSIGNMENT' THEN 6
      WHEN 'SLOT_CONFIRMED_BY_CUSTOMER' THEN 5
      WHEN 'SLOT_AUTO_CONFIRMED' THEN 5
      WHEN 'AWAITING_CUSTOMER_SLOT_CONFIRMATION' THEN 4
      WHEN 'SLOT_SELECTED' THEN 3
      WHEN 'AWAITING_SLOT_PROPOSAL' THEN 2
      ELSE 1 END AS rnk
  FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES
  WHERE _FIVETRAN_ACTIVE=TRUE AND CSP_ID IS NOT NULL
    AND CURRENT_STATE IN ('ACCEPTED','AWAITING_SLOT_PROPOSAL','SLOT_SELECTED','AWAITING_CUSTOMER_SLOT_CONFIRMATION',
      'SLOT_CONFIRMED_BY_CUSTOMER','SLOT_AUTO_CONFIRMED','AWAITING_TECHNICIAN_ASSIGNMENT','TECHNICIAN_ASSIGNED',
      'ARRIVED_AT_SITE','INSTALLATION_IN_PROGRESS_PRE_FEE','FEE_COLLECTION_PENDING','INSTALLATION_IN_PROGRESS_POST_FEE','AWAITING_CUSTOMER_OTP')
),
tk_ranked AS (
  SELECT CSP_ID, EXECUTION_CANDIDATE_ID, ZONE_ID,
    ROW_NUMBER() OVER (PARTITION BY CSP_ID ORDER BY rnk DESC, UPDATED_AT ASC) AS rn
  FROM open_tk
),
tk AS (
  SELECT CSP_ID,
    MAX(CASE WHEN rn=1 THEN '#'||RIGHT(EXECUTION_CANDIDATE_ID,4) END) AS t1_no,
    MAX(CASE WHEN rn=1 THEN ZONE_ID END) AS t1_area,
    MAX(CASE WHEN rn=1 THEN EXECUTION_CANDIDATE_ID END) AS t1_cid,
    MAX(CASE WHEN rn=2 THEN '#'||RIGHT(EXECUTION_CANDIDATE_ID,4) END) AS t2_no,
    MAX(CASE WHEN rn=2 THEN ZONE_ID END) AS t2_area,
    MAX(CASE WHEN rn=2 THEN EXECUTION_CANDIDATE_ID END) AS t2_cid
  FROM tk_ranked WHERE rn<=2 GROUP BY CSP_ID
),
owner AS (   -- one representative userId per CSP (for mbg_id / tracking), owner preferred
  SELECT CSP_ID,
    MAX_BY(ID::string, CASE ROLE WHEN 'OWNER' THEN 3 WHEN 'MANAGER_PLUS' THEN 2 ELSE 1 END) AS user_id
  FROM PROD_DB.CSP_GATEWAY_SERVICE_CSP_GATEWAY_SERVICE.CSP_USER
  WHERE _FIVETRAN_ACTIVE=TRUE AND STATUS='ACTIVE'
    AND ROLE IN ('OWNER','MANAGER','MANAGER_PLUS') AND ID IS NOT NULL
  GROUP BY CSP_ID
),
-- FULL OUTER so a CSP that appears in only one source still lands in the
-- snapshot (metric-only or open-leads-only), rather than silently vanishing.
agg AS (
  SELECT COALESCE(g.CSP_ID, m.CSP_ID, l.CSP_ID) AS CSP_ID,
    COALESCE(g.installs,0)  AS installs,    -- NUMERATOR + pay base (rate x installs)
    COALESCE(g.denom,0)     AS denom,       -- DENOMINATOR = tech-assigned leads
    COALESCE(m.pending,0)   AS pending,     -- open leads (IEC) — `almost` screen
    COALESCE(m.committed,0) AS committed,
    COALESCE(l.ontime_m1,0) AS ontime_m1,   -- reference only (no screen reads these)
    COALESCE(l.late_m1,0)   AS late_m1,
    COALESCE(l.leads_m1,0)  AS leads_m1
  FROM mg g
  FULL OUTER JOIN metrics m ON m.CSP_ID = g.CSP_ID
  FULL OUTER JOIN led     l ON l.CSP_ID = COALESCE(g.CSP_ID, m.CSP_ID)
)
SELECT COALESCE(a.CSP_ID, e.CSP_ID) AS csp_id, o.user_id,
  COALESCE(a.installs,0)  AS installs,  COALESCE(a.denom,0)     AS denom,
  COALESCE(a.pending,0)   AS pending,   COALESCE(a.committed,0) AS committed,
  COALESCE(a.ontime_m1,0) AS ontime_m1, COALESCE(a.late_m1,0)   AS late_m1,
  COALESCE(a.leads_m1,0)  AS leads_m1,
  tk.t1_no, tk.t1_area, tk.t1_cid, tk.t2_no, tk.t2_area, tk.t2_cid
-- FULL OUTER JOIN keeps (a) active non-enrolled CSPs (agg row, no enrol row)
-- and (b) every enrolled CSP with NO activity at all in the lookback (enrol
-- row, no agg row) — those must render as the noleads case on the settle
-- screen, never "हिसाब तैयार नहीं" (e.g. a0b5r4, quiet all of August).
FROM agg a
FULL OUTER JOIN enrol e ON e.CSP_ID = a.CSP_ID
LEFT JOIN tk    ON tk.CSP_ID = COALESCE(a.CSP_ID, e.CSP_ID)
LEFT JOIN owner o ON o.CSP_ID = COALESCE(a.CSP_ID, e.CSP_ID)
WHERE (COALESCE(a.installs,0) + COALESCE(a.denom,0) + COALESCE(a.pending,0)
       + COALESCE(a.leads_m1,0)) > 0
   OR e.CSP_ID IS NOT NULL
ORDER BY installs DESC, denom DESC
