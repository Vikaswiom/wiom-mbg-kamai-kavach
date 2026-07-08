/**
 * MBG / Kamai Kavach — LIVE PER-TAP proxy (Google Apps Script Web App)
 *
 * The static page (index.html) calls this with ?cspId=a0a0b1 on every open; this
 * runs the Metabase query for THAT ONE CSP right now and returns fresh raw inputs.
 * The Metabase key stays server-side (Script Property) — never in the page.
 *
 * DEPLOY (2 min):
 *   1. script.google.com → New project → paste this file.
 *   2. Project Settings (gear) → Script Properties → add:
 *          METABASE_API_KEY = <the key from C:\credentials\.env>
 *   3. Deploy → New deployment → type "Web app":
 *          Execute as: Me   ·   Who has access: Anyone
 *      Copy the /exec URL.
 *   4. Put that URL into PROXY_URL in index.html, commit & push. Done — live per tap.
 *
 * Returns: { cspId, userId, installs, denom, pending, tickets:[{no,area,cid}] }
 * (Same shape as data.json records. Keep the SQL below in sync with sql/metrics.sql.)
 */

var DB = 113;
var MB_URL = 'https://metabase.wiom.in/api/dataset';
var MS = '2026-07-01';                 // program month start

function doGet(e) {
  var cspId = ((e && e.parameter && e.parameter.cspId) || '').toLowerCase().replace(/[^a-z0-9]/g, ''); // sanitize
  var out = { cspId: cspId, userId: cspId, installs: 0, denom: 0, pending: 0, tickets: [] };
  if (cspId) {
    try {
      var rows = runSql(buildSql(cspId));
      if (rows.length) {
        var r = rows[0]; // CSP_ID,USER_ID,INSTALLS,DENOM,PENDING,T1_NO,T1_AREA,T1_CID,T2_NO,T2_AREA,T2_CID
        out.userId   = String(r[1] || cspId);
        out.installs = +r[2] || 0;
        out.denom    = +r[3] || 0;
        out.pending  = +r[4] || 0;
        if (r[5]) out.tickets.push({ no: r[5], area: r[6] || '', cid: r[7] || '' });
        if (r[8]) out.tickets.push({ no: r[8], area: r[9] || '', cid: r[10] || '' });
      }
    } catch (err) { out.error = String(err); }   // on error → noleads-safe zeros
  }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

function runSql(q) {
  var key = PropertiesService.getScriptProperties().getProperty('METABASE_API_KEY');
  var res = UrlFetchApp.fetch(MB_URL, {
    method: 'post', contentType: 'application/json',
    headers: { 'x-api-key': key },
    payload: JSON.stringify({ database: DB, type: 'native', native: { query: q } }),
    muteHttpExceptions: true
  });
  var d = JSON.parse(res.getContentText());
  return (d.data && d.data.rows) || [];
}

function buildSql(cspId) {
  var C = "CSP_ID='" + cspId + "'";           // cspId already sanitized to [a-z0-9]
  return "" +
  "WITH base AS (SELECT CONNECTION_ID, CSP_ID," +
  " MAX_BY(CURRENT_STATE,UPDATED_AT) last_state, MAX_BY(REASON_CODE,UPDATED_AT) rc," +
  " MAX_BY(FAILURE_REASON,UPDATED_AT) fr, MAX_BY(FAILURE_SUBREASON_CODE,UPDATED_AT) fsc," +
  " MAX(CASE WHEN OTP_VERIFIED=TRUE OR INSTALLATION_COMPLETED_AT IS NOT NULL OR COMPLETED_STEP>=7 THEN 1 ELSE 0 END) has_installed," +
  " MAX(CASE WHEN CONFIRMED_SLOT_AT IS NOT NULL THEN 1 ELSE 0 END) reached_slot," +
  " TO_DATE(DATEADD(minute,330,MAX(UPDATED_AT))) last_date" +
  " FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES" +
  " WHERE _FIVETRAN_ACTIVE=TRUE AND " + C + " GROUP BY CONNECTION_ID,CSP_ID)," +
  "bucketed AS (SELECT *, CASE" +
  " WHEN has_installed=1 THEN 'installed'" +
  " WHEN last_state='DECLINED' THEN 'csp_denied'" +
  " WHEN last_state='CANCELLED_BY_UPSTREAM' AND fr='TIMEOUT_P74' AND fsc='CSP_NO_SHOW' AND rc='ALLOCATION_ACCEPTED' THEN 'csp_no_show'" +
  " WHEN fsc='CSP_NO_SHOW' THEN 'csp_abandoned'" +
  " WHEN last_state='CANCELLED_BY_UPSTREAM' AND rc='TIMEOUT_P41' THEN 'csp_timeout'" +
  " WHEN last_state='CANCELLED_BY_CUSTOMER' AND reached_slot=1 THEN 'cust_cancel_after_slot'" +
  " WHEN last_state='CANCELLED_BY_CUSTOMER' AND reached_slot=0 THEN 'cust_cancel_before_slot'" +
  " WHEN last_state='INSTALLATION_REPORTED_FAILED' THEN 'install_failed'" +
  " WHEN last_state='CANCELLED_BY_UPSTREAM' THEN 'system_other'" +
  " WHEN last_state='INSTALLATION_CANCELLED_ONSITE' THEN 'cancelled_onsite'" +
  " ELSE 'open' END AS bucket FROM base)," +
  "metrics AS (SELECT CSP_ID," +
  " COUNT_IF(bucket='installed' AND reached_slot=1 AND last_date>=DATE '" + MS + "') installs," +
  " COUNT_IF(reached_slot=1 AND bucket NOT IN ('open','system_other') AND last_date>=DATE '" + MS + "') denom," +
  " COUNT_IF(bucket='open') pending FROM bucketed GROUP BY CSP_ID)," +
  "open_tk AS (SELECT CSP_ID, EXECUTION_CANDIDATE_ID, ZONE_ID, UPDATED_AT, CASE CURRENT_STATE" +
  " WHEN 'ARRIVED_AT_SITE' THEN 8 WHEN 'TECHNICIAN_ASSIGNED' THEN 7 WHEN 'AWAITING_TECHNICIAN_ASSIGNMENT' THEN 6" +
  " WHEN 'SLOT_CONFIRMED_BY_CUSTOMER' THEN 5 WHEN 'SLOT_AUTO_CONFIRMED' THEN 5 WHEN 'AWAITING_CUSTOMER_SLOT_CONFIRMATION' THEN 4" +
  " WHEN 'SLOT_SELECTED' THEN 3 WHEN 'AWAITING_SLOT_PROPOSAL' THEN 2 ELSE 1 END rnk" +
  " FROM PROD_DB.CSP_TAS_SERVICE_CSP_TAS_SERVICE.INSTALL_EXECUTION_CANDIDATES" +
  " WHERE _FIVETRAN_ACTIVE=TRUE AND " + C + " AND CURRENT_STATE IN ('ACCEPTED','AWAITING_SLOT_PROPOSAL','SLOT_SELECTED'," +
  "'AWAITING_CUSTOMER_SLOT_CONFIRMATION','SLOT_CONFIRMED_BY_CUSTOMER','SLOT_AUTO_CONFIRMED','AWAITING_TECHNICIAN_ASSIGNMENT'," +
  "'TECHNICIAN_ASSIGNED','ARRIVED_AT_SITE','INSTALLATION_IN_PROGRESS_PRE_FEE','FEE_COLLECTION_PENDING'," +
  "'INSTALLATION_IN_PROGRESS_POST_FEE','AWAITING_CUSTOMER_OTP'))," +
  "tk_ranked AS (SELECT CSP_ID, EXECUTION_CANDIDATE_ID, ZONE_ID," +
  " ROW_NUMBER() OVER (PARTITION BY CSP_ID ORDER BY rnk DESC, UPDATED_AT ASC) rn FROM open_tk)," +
  "tk AS (SELECT CSP_ID," +
  " MAX(CASE WHEN rn=1 THEN '#'||RIGHT(EXECUTION_CANDIDATE_ID,4) END) t1_no," +
  " MAX(CASE WHEN rn=1 THEN ZONE_ID END) t1_area, MAX(CASE WHEN rn=1 THEN EXECUTION_CANDIDATE_ID END) t1_cid," +
  " MAX(CASE WHEN rn=2 THEN '#'||RIGHT(EXECUTION_CANDIDATE_ID,4) END) t2_no," +
  " MAX(CASE WHEN rn=2 THEN ZONE_ID END) t2_area, MAX(CASE WHEN rn=2 THEN EXECUTION_CANDIDATE_ID END) t2_cid" +
  " FROM tk_ranked WHERE rn<=2 GROUP BY CSP_ID)," +
  "owner AS (SELECT CSP_ID, MAX_BY(ID::string, CASE ROLE WHEN 'OWNER' THEN 3 WHEN 'MANAGER_PLUS' THEN 2 ELSE 1 END) user_id" +
  " FROM PROD_DB.CSP_GATEWAY_SERVICE_CSP_GATEWAY_SERVICE.CSP_USER" +
  " WHERE _FIVETRAN_ACTIVE=TRUE AND STATUS='ACTIVE' AND ROLE IN ('OWNER','MANAGER','MANAGER_PLUS') AND ID IS NOT NULL AND " + C +
  " GROUP BY CSP_ID) " +
  "SELECT m.CSP_ID, o.user_id, m.installs, m.denom, m.pending," +
  " tk.t1_no, tk.t1_area, tk.t1_cid, tk.t2_no, tk.t2_area, tk.t2_cid" +
  " FROM metrics m LEFT JOIN tk ON tk.CSP_ID=m.CSP_ID LEFT JOIN owner o ON o.CSP_ID=m.CSP_ID";
}
