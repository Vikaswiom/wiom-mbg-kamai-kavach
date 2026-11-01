/**
 * Google Apps Script — Belief Break event logger.
 *
 * Receives every event from belief-break.html and appends one row to the
 * "Events" tab of the Google Sheet this script is bound to.
 *
 * SETUP (one time, ~3 min):
 *   1. Create a Google Sheet → Extensions → Apps Script.
 *   2. Replace Code.gs with this whole file → Save.
 *   3. Deploy → New deployment → type "Web app"
 *        Execute as:      Me
 *        Who has access:  Anyone
 *      → Deploy → authorise → copy the Web app URL (ends in /exec).
 *   4. Paste that URL into GAS_URL in belief-break.html and push to main.
 *
 * Changing this script later? Deploy → Manage deployments → edit → "New
 * version". That keeps the same /exec URL, so the page needs no change.
 *
 * Test: open the /exec URL in a browser and you should see {"ok":true,"rows":N}.
 */

var SHEET = 'Events';
var HEAD = ['received_at', 'event', 'cspId', 'response', 'lang', 'platform',
            'embedded', 'session', 'client_ts', 'user_agent'];

function sheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(SHEET) || ss.insertSheet(SHEET);
  if (sh.getLastRow() === 0) {
    sh.appendRow(HEAD);
    sh.setFrozenRows(1);
  }
  return sh;
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(10000); // many CSPs answering at once must not overwrite rows
  try {
    var d = {};
    try { d = JSON.parse((e && e.postData && e.postData.contents) || '{}'); } catch (err) {}
    var s = function (v) { return String(v == null ? '' : v).slice(0, 500); };
    sheet_().appendRow([
      new Date(), s(d.event), s(d.cspId), s(d.response), s(d.lang), s(d.platform),
      s(d.embedded), s(d.session), s(d.ts), s(d.ua)
    ]);
    return json_({ ok: true });
  } finally {
    lock.releaseLock();
  }
}

function doGet() {
  return json_({ ok: true, rows: Math.max(sheet_().getLastRow() - 1, 0) });
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o))
    .setMimeType(ContentService.MimeType.JSON);
}
