# TAS CORS relay — fixing "जानकारी लोड नहीं हो पाई"

## What the error actually means

The screen loaded. The API call is what failed.

`daily-installation.html` is served from `vikaswiom.github.io` and calls
`csp-tas-service.i2e1agents.in` from the browser. That is a **cross-origin**
request, so the browser only hands the response to the page if TAS replies with
an `Access-Control-Allow-Origin` header. TAS does not send one — the path is
`/api/internal/`, so nobody expected a browser origin — and the browser
therefore fetches the response and throws it away.

This is why **the URL works when you paste it into a tab but fails inside the
page**. Typing it into the address bar is a top-level navigation, not a
cross-origin request, so CORS never applies. Both facts are consistent with a
perfectly healthy API.

## Confirm it in 10 seconds

Open the screen with `&debug=1`:

```
…/daily-installation.html?technicianId=10374&debug=1
```

The error screen then prints the reason.

| What it prints | What it means |
|---|---|
| `reason network_or_cors` · `status 0` | **CORS.** The header is missing. Fix below. |
| `reason http_401` / `http_403` | TAS answered and refused. Not CORS — needs a token. |
| `reason http_5xx` | TAS answered with an error. Not CORS. Upstream problem. |
| `reason timeout` | No answer in 9s. Not CORS. |

`status 0` is not an HTTP status — there is no HTTP 0. It means the response
never reached the page.

## Fix A — the real one (ask the TAS team)

Have TAS return this on that endpoint:

```
Access-Control-Allow-Origin: https://vikaswiom.github.io
```

One header, no page change. Hosting on Pages is what makes this possible at
all: the in-app WebView's origin is `null` and cannot be allow-listed, but
`https://vikaswiom.github.io` is a real origin.

## Fix B — the one you can ship today (this relay)

Apps Script is a **server**, and servers are not bound by CORS. It fetches TAS
normally and re-serves the identical JSON from `script.google.com`, which does
send the header.

```
page → /exec?executorId=10374 → TAS → same JSON back, now with CORS
```

1. **script.google.com** → *New project* → paste **`Code.gs`** from this folder.
2. *Deploy* → **New deployment** → type **Web app**
   - **Execute as:** Me
   - **Who has access:** Anyone
   - Deploy, authorize, copy the **`/exec`** URL.
3. Check the relay alone in a tab — you should see TAS's JSON:
   ```
   <exec-url>?executorId=10374
   ```
4. Check it end to end, **with no code change**:
   ```
   …/daily-installation.html?technicianId=10374&proxy=<exec-url>
   ```
5. When that renders cards, make it permanent — set `PROXY_URL` in
   `daily-installation.html` (in `CFG`, near the top) to the `/exec` URL,
   then commit and push:
   ```js
   PROXY_URL : 'https://script.google.com/macros/s/AKfy…/exec',
   ```

`?proxy=` only accepts `https://script.google.com/…` URLs. A free-form value
there would let a crafted link feed a technician someone else's data.

## Do NOT use a public CORS proxy

Not `corsproxy.io`, not `allorigins`, not any of them. This response carries
customer **names, full phone numbers and home addresses**. A public proxy
receives every byte of it. That is a subscriber-data leak, not a workaround.

## Notes

- **"Who has access: Anyone"** makes the relay reachable by anyone holding the
  URL — exactly like the TAS endpoint it fronts, which is already public and
  unauthenticated on the same id. It widens nothing. (Separately: that endpoint
  returning PII keyed only on a guessable `executorId` is worth raising with
  the TAS team on its own merits.)
- **If TAS later needs a token**, put it in a Script Property and add it to the
  `UrlFetchApp.fetch` headers in `Code.gs`. It then stays server-side instead of
  sitting in a page anyone can view-source.
- **Latency:** one extra hop, typically well under a second.
- **Reverting** to a direct call once TAS sends the header is just blanking
  `PROXY_URL`. The payload is passed through untouched, so nothing else changes.
- **`RELAY_UNREACHABLE`** from the relay means Google's servers could not reach
  TAS at all (e.g. the ALB restricts by IP). That needs Fix A instead.
