WITH prof AS (
  SELECT DISTINCT CLEVERTAP_ID, cspid FROM PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA
),
clicks AS (
  SELECT p.cspid, COUNT(*) AS n_clicks
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.event_name='banner_opened' AND e.TIMESTAMP >= '2026-07-09'
  GROUP BY p.cspid
),
inst AS (
  SELECT CSP_ID AS cspid,
    COUNT(CASE WHEN CONFIRMED_SLOT_AT IS NOT NULL THEN 1 END) AS slot_conf,
    COUNT(CASE WHEN EXECUTOR_ID IS NOT NULL THEN 1 END)        AS exec_assigned,
    COUNT(CASE WHEN OTP_VERIFIED=TRUE OR COMPLETED_STEP>=7 THEN 1 END) AS installed
  FROM PROD_DB.DBT_CSP.TAS_INSTALL_EXECUTION_CANDIDATES
  WHERE ETL_CURRENT=TRUE AND CREATED_AT >= '2026-07-09'
  GROUP BY CSP_ID
),
base AS (
  SELECT c.cspid,
    CASE WHEN c.cspid IN ('a0a6y4','a0a6y6','a0a6y9','a0a6z0','a0a6z1','a0a6z2','a0a6z4','a0a6z7','a0a6z8','a0a7a0','a0a7a2','a0a7a3','a0a7a4','a0a7a5','a0a7a6','a0a7a7','a0a7a9','a0a7b1','a0a7b2','a0a7b3','a0a7b4','a0a7b5','a0a7b6','a0a7b7','a0a7b8','a0a7b9','a0a7c0','a0a7c1','a0a7c2','a0a7c4','a0a7c7','a0a7d3','a0a7d4','a0a7d9','a0a7e3','a0a7e4','a0a7f5','a0a7f8','a0a7g0','a0a7g2','a0a7g5','a0a7g6','a0a7g7','a0a7g9','a0a7h2','a0a8a5','a0a9j4','a0a9m4','a0a9o4','a0a9s3','a0a9w2','a0b0n9','a0b0w0','a0b1b5','a0b3m4','a0b5l8','a0b5l9','a0b5m0','a0b5m1','a0b5m3','a0b5m5','a0b5m6','a0b5n2','a0b5n3','a0b5n7','a0b5n8','a0b5o0','a0b5o3','a0b5o4','a0b5o5','a0b5p5','a0b5p7','a0b5q6','a0b5q7','a0b5r2','a0b5r4','a0b5r7','a0b5r9','a0b5s4','a0b5t0','a0b5t3','a0b5t5','a0b5t9','a0b5u1','a0b5v0','a0b5v3','a0b5v4','a0b5v5','a0b5v7','a0b5v8','a0b5w1','a0b5w4','a0b5w5','a0b5w9','a0b5x0','a0b5x1','a0b5y1','a0b5y3','a0b5y5','a0b5y9','a0b5z0','a0b5z1','a0b5z6','a0b5z7','a0b6a1','a0b6a3','a0b6a6','a0b6a8','a0b6a9','a0b6b1','a0b6b2','a0b6b5','a0b6b8','a0b6c4','a0b6c5','a0b6c6','a0b6d0','a0b6d1','a0b6d3','a0b6d4','a0b6d8','a0b6e0','a0b6e3','a0b6e6','a0b6e7','a0b6e8','a0b6f0','a0b6f1','a0b6f2','a0b6f3','a0b6f5','a0b6f6','a0b6f7','a0b6f8','a0b6f9','a0b6g1','a0b6g2','a0b6g6','a0b6g9','a0b6h2','a0b6h3','a0b6h4','a0b6h5','a0b6h6','a0b6h8','a0b6h9','a0b6i0','a0b6i1','a0b6i2','a0b6i4','a0b6i8','a0b6j2','a0b6j7','a0b6j8','a0b6k4','a0b6k8','a0b6l2','a0b6l3','a0b6l6','a0b6l7','a0b6m3','a0b6m4','a0b6m6','a0b6n2','a0b6n3','a0b6o1','a0b6o2','a0b6o4','a0b6o5','a0b6o8','a0b6p0','a0b6p1','a0b6p3','a0b6p7','a0b6p8','a0b6p9','a0b6q5','a0b6q6','a0b6q9','a0b6r1','a0b6r4','a0b6r6','a0b6r8','a0b6s7','a0b6t0','a0b6t1','a0b6t2','a0b6t3','a0b6t7','a0b6t9','a0b6u0','a0b6u2','a0b6u3','a0b6u4','a0b6u5','a0b6u7','a0b6u8','a0b6v0','a0b6v1','a0b6v3','a0b6v8','a0b6w1','a0b6w2','a0b6w7','a0b6w8','a0b6x2','a0b6x3','a0b6x6','a0b6x8','a0b6x9','a0b6y1','a0b6y2','a0b6y3','a0b6y5','a0b6y6','a0b6y7','a0b6y8','a0b6z2','a0b6z9','a0b7a1','a0b7a2','a0b7a3','a0b7a4','a0b7a9','a0b7b1','a0b7b4','a0b7b5','a0b7b7','a0b7c1','a0b7c2','a0b7c3','a0b7c6','a0b7c7','a0b7d0','a0b7e3','a0b7e5','a0b7e6','a0b7e7','a0b7f2','a0b7f6','a0b7g1','a0b7g4','a0b7g5','a0b7g6','a0b7g7','a0b7h0','a0b7h5','a0b7h8','a0b7i0','a0b7i6','a0b7i7','a0b7j1','a0b7j2','a0b7j4','a0b8o2','a0b8o3','a0b8o4','a0b8o5','a0b8o7','a0b8o8','a0b8p2','a0b8p6','a0b8q2','a0b8r0','a0b8r1','a0b8r4','a0b8r5','a0b8r9','a0b8s0','a0b8s1','a0b8s3','a0b8s4','a0b8s7','a0b8u2','a0b8u9','a0b8v3','a0b8v4','a0b8v5','a0b8v8','a0b8v9','a0b8w1','a0b8w5','a0b8w6','a0b8w7','a0b8w8','a0b8x0','a0b8x3','a0b8x4','a0b8x6','a0b8y0','a0b8y2','a0b8y3','a0b8y6','a0b8y7','a0b8y8','a0b8y9','a0b8z0','a0b8z1','a0b8z7','a0b9a0','a0b9a2','a0b9a4','a0b9a8','a0b9a9','a0b9b5','a0b9b9','a0b9c0','a0b9c1','a0b9c2','a0b9c5','a0b9c8','a0b9c9','a0b9d2','a0b9d5','a0b9d9','a0b9e3','a0b9f2','a0b9g3','a0b9g4','a0b9g7','a0b9g8','a0b9h2','a0b9h4','a0b9h5','a0b9h6','a0b9i0','a0b9i5','a0b9i8','a0b9j0','a0b9j1','a0b9j3','a0b9j5','a0b9j6','a0b9j7','a0b9k1','a0b9k9','a0b9l3','a0b9l5','a0b9l6','a0b9l8','a0b9m2','a0b9m4','a0b9m7','a0b9m8','a0b9n1','a0b9n2','a0b9n5','a0b9n6','a0b9n7','a0b9o4','a0b9p0','a0b9p1','a0b9p2','a0b9p4','a0b9p5','a0b9p6','a0b9p7','a0b9q0','a0b9q4','a0b9q7','a0b9r3','a0b9r4','a0b9r9','a0b9s4','a0b9s6','a0b9s8','a0b9t2','a0b9t7','a0b9u0','a0b9u7','a0b9v1','a0b9v5','a0b9v8','a0b9v9','a0b9w5','a0b9w7','a0b9w8','a0b9x1','a0b9x3','a0b9x5','a0b9x8','a0b9x9','a0b9y0','a0b9y2','a0b9y3','a0b9y4','a0b9y5','a0b9y9','a0b9z2','a0b9z4','a0b9z6','a0b9z7','a0b9z9','a0c0a0','a0c0a1','a0c0a2','a0c0a5','a0c0a6','a0c0a9','a0c0b4','a0c0b5','a0c0b6','a0c0c0','a0c0c3','a0c0c7','a0c0c8','a0c0c9','a0c0e1','a0c0e2','a0c0e4','a0c0e6','a0c0e9','a0c0f0','a0c0f2','a0c0f3','a0c0f6','a0c0g0','a0c0g1','a0c0g4','a0c0g7','a0c0g8','a0c0g9','a0c0h3','a0c0i5','a0c0j1') THEN 'MBG' ELSE 'Non-MBG' END AS grp,
    c.n_clicks,
    COALESCE(i.slot_conf,0) AS slot_conf,
    COALESCE(i.exec_assigned,0) AS exec_assigned,
    COALESCE(i.installed,0) AS installed
  FROM clicks c LEFT JOIN inst i ON i.cspid = c.cspid
),
-- CleverTap-profile count (CLEVERTAP_ID) per group, to reconcile with CleverTap's UI.
-- CleverTap counts profiles; the dashboard headline counts unique CSPs. One CSP owns
-- many CleverTap profiles (reinstalls / re-logins), so ct_profiles > clickers.
ctprof AS (
  SELECT b.grp, COUNT(DISTINCT e.CLEVERTAP_ID) AS ct_profiles
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  JOIN base b ON b.cspid = p.cspid
  WHERE e.event_name='banner_opened' AND e.TIMESTAMP >= '2026-07-09'
  GROUP BY b.grp
)
SELECT agg.grp,
  agg.clickers, agg.total_clicks, agg.reached_slot, agg.reached_tech, agg.reached_install,
  agg.c1, agg.c2, agg.c3, agg.c4plus, cp.ct_profiles
FROM (
  SELECT grp,
    COUNT(*) AS clickers,
    SUM(n_clicks) AS total_clicks,
    COUNT(CASE WHEN slot_conf>0 THEN 1 END)     AS reached_slot,
    COUNT(CASE WHEN exec_assigned>0 THEN 1 END) AS reached_tech,
    COUNT(CASE WHEN installed>0 THEN 1 END)     AS reached_install,
    COUNT(CASE WHEN n_clicks=1 THEN 1 END) AS c1,
    COUNT(CASE WHEN n_clicks=2 THEN 1 END) AS c2,
    COUNT(CASE WHEN n_clicks=3 THEN 1 END) AS c3,
    COUNT(CASE WHEN n_clicks>=4 THEN 1 END) AS c4plus
  FROM base GROUP BY grp
) agg
JOIN ctprof cp ON cp.grp = agg.grp
ORDER BY agg.grp
