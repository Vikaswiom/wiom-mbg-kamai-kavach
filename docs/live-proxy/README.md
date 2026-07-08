# Live-per-tap proxy (Google Apps Script)

A static GitHub Pages site can't query Metabase itself (no server, and the key can't be
exposed in the page). This tiny Apps Script Web App sits in between: the page calls it
with `?cspId=`, it runs the Metabase query for **that one CSP right now**, and returns
fresh data. The Metabase key stays server-side (Script Property). Same pattern as the
CleverTap-reporting proxy.

```
CSP taps banner → index.html (?cspId=a0a0b1) → Apps Script /exec?cspId=a0a0b1
                → runs Metabase query for that CSP → { installs, denom, pending, tickets }
                → page computes screen + renders   ← LIVE, ~2–4s per tap
```

If `PROXY_URL` is empty (or the proxy errors), the page falls back to the baked
`data.json` snapshot — so it always shows something.

## Deploy (one-time, ~2 min)

1. Go to **script.google.com** → *New project* → paste **`Code.gs`** (this folder).
2. *Project Settings* (⚙) → **Script Properties** → *Add property*:
   - `METABASE_API_KEY` = the key from `C:\credentials\.env`
3. *Deploy* → **New deployment** → select type **Web app**:
   - **Execute as:** Me
   - **Who has access:** Anyone
   - Deploy, authorize, and **copy the `/exec` URL**.
4. Open `index.html`, set:
   ```js
   var PROXY_URL = "https://script.google.com/macros/s/AKfy…/exec";
   ```
5. Commit & push. The bottom demo line will now say **(live)** instead of **(snapshot)**.

## Test the proxy directly

```
https://script.google.com/macros/s/AKfy…/exec?cspId=a0b9y0
→ {"cspId":"a0b9y0","userId":"...","installs":5,"denom":7,"pending":3,"tickets":[...]}
```

## Notes

- **Keep the SQL in sync** with `sql/metrics.sql` — the proxy embeds the same logic
  filtered to one `CSP_ID`. If you change one, change the other.
- **Latency:** each tap runs a Snowflake query (~2–4s). The page shows the snapshot
  values first only if you wire that; currently it awaits the live call then renders.
- **Security:** `cspId` is sanitized to `[a-z0-9]` before it touches SQL. The key is
  never sent to the browser. The endpoint is public but only returns MBG numbers for a
  given cspId (same exposure you already accepted for the public snapshot).
- **Best long-term:** your own authenticated `GET /api/mbg/me` (no cspId in the URL —
  the session identifies the CSP). Swapping `PROXY_URL`/`getCspData()` for it is trivial.
