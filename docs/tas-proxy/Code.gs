/**
 * आज का इंस्टॉलेशन — TAS CORS relay (Google Apps Script Web App)
 *
 * WHY THIS EXISTS
 * The screen is served from vikaswiom.github.io and calls TAS from the
 * browser. That is a cross-origin request, so the browser only hands the
 * response to the page if TAS answers with an Access-Control-Allow-Origin
 * header. TAS does not (the path is /api/internal/ — nobody expected a
 * browser origin), so the response is fetched and then thrown away, and
 * the page shows "जानकारी लोड नहीं हो पाई".
 *
 * This relay sits in between. Apps Script is a SERVER, and servers are not
 * bound by CORS, so it fetches TAS normally and re-serves the identical
 * JSON from script.google.com, which does send the header.
 *
 *     page → /exec?executorId=10374 → TAS → same JSON back, with CORS
 *
 * The REAL fix is TAS returning the header itself; this is what unblocks
 * the campaign without waiting on a backend release. Nothing about the
 * payload changes, so switching back later is just blanking PROXY_URL.
 *
 * NOT a public CORS proxy. Do not swap this for corsproxy.io / allorigins
 * or similar: this response carries customer names, full phone numbers and
 * home addresses, and those services would receive all of it.
 *
 * DEPLOY (2 min):
 *   1. script.google.com → New project → paste this file.
 *   2. Deploy → New deployment → type "Web app":
 *          Execute as: Me   ·   Who has access: Anyone
 *      Copy the /exec URL.
 *   3. Test it in a tab:  <exec-url>?executorId=10374
 *      You should see the same JSON TAS returns.
 *   4. Test it end to end, no code change needed:
 *          daily-installation.html?technicianId=10374&proxy=<exec-url>
 *   5. When that renders, put the URL into PROXY_URL in
 *      daily-installation.html, commit & push.
 *
 * NOTE ON "Who has access: Anyone" — this endpoint is then reachable by
 * anyone who has the URL, exactly like the TAS endpoint it fronts, which
 * is already public and unauthenticated on the same id. It widens nothing.
 * If TAS later requires a token, put it in a Script Property and add it
 * below, and the token stays server-side instead of sitting in the page.
 */

var TAS = 'https://csp-tas-service.i2e1agents.in/api/internal/install/candidates/by-executor';

function doGet(e) {
  var id = ((e && e.parameter && e.parameter.executorId) || '').replace(/[^A-Za-z0-9_-]/g, '');

  if (!id) return json({ error_code: 'NO_EXECUTOR_ID', items: [] });

  try {
    var res = UrlFetchApp.fetch(TAS + '?executorId=' + encodeURIComponent(id), {
      method: 'get',
      muteHttpExceptions: true,      // read TAS's own 4xx/5xx instead of throwing
      followRedirects: true,
      validateHttpsCertificates: true
    });

    var code = res.getResponseCode();
    var body = res.getContentText();

    /* Pass TAS's failure through as a readable reason rather than an empty
       list — the page surfaces api_<code> and the screen stops looking
       like "no installs today" when it is really a broken upstream. */
    if (code < 200 || code >= 300) {
      return json({ error_code: 'TAS_HTTP_' + code, status: code,
                    detail: String(body).substring(0, 300), items: [] });
    }

    /* Return TAS's bytes untouched when they parse. The page maps the
       response itself, so the relay must not reshape anything. */
    try {
      JSON.parse(body);
      return raw(body);
    } catch (parseErr) {
      return json({ error_code: 'TAS_BAD_JSON',
                    detail: String(body).substring(0, 300), items: [] });
    }

  } catch (err) {
    /* Apps Script could not reach TAS at all — e.g. the ALB restricts by
       IP and Google's egress is not allowed. Distinct from a TAS error. */
    return json({ error_code: 'RELAY_UNREACHABLE', detail: String(err), items: [] });
  }
}

function json(o) { return raw(JSON.stringify(o)); }

function raw(text) {
  return ContentService.createTextOutput(text)
                       .setMimeType(ContentService.MimeType.JSON);
}
