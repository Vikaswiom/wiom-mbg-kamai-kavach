# गारंटी कमाई — Kamai Kavach (MBG) banner

A single, self-contained HTML page for the Wiom **MBG / Kamai Kavach** program. It
**calculates each CSP's data first, then renders the matching screen and copy** — one
of four mutually-exclusive states: `keepgoing` · `almost` · `secured` · `noleads`.

No build step, no framework, no external assets — just open `index.html`.

## Docs

- [`docs/CALCULATIONS.md`](./docs/CALCULATIONS.md) — the full calculation spec: raw
  inputs, screen routing, every derived formula, per-screen copy, IST handling, events,
  worked examples, and the go-live backend contract. **Single source of truth for the numbers.**
- [`docs/mbg-poller-reference.md`](./docs/mbg-poller-reference.md) — the consolidated
  MBG/CI poller · CleverTap reference (the four APIs, measurement gotchas, HTML in-app
  rules, and Appendix A with the exact poller formulas this page mirrors).

## How it works

```
getCspData()   → the CSP's RAW inputs { userId, installs, denom, pending, tickets }
computeMBG()   → routes the SCREEN + computes pct, needed, next_pct, installpay,
                 topup, days_left (IST), month, id   (exact poller formulas)
COPY[screen]   → swaps colour + earn-sub + big-% + headline + sub-line
render         → paints the banner; MBG_* events fire with the screen suffix
```

The **only** things that differ between the four screens are the progress-card colour
and its three copy lines (plus the earnings sub-line + `%`/`—` for noleads). Everything
else — earnings card, ticket action card, ₹10,000 guarantee card, footer — is shared.

### Screen routing (`total = denom + pending`)

| Screen | Condition | Colour |
|---|---|---|
| `noleads`   | `total == 0` | idle |
| `secured`   | `denom > 0 && installs/denom > 0.60` | green |
| `almost`    | `(installs + pending) > 0.60 · total` | amber |
| `keepgoing` | otherwise | red |

### Key derived values (exact poller formulas)

| Value | Formula |
|---|---|
| `pct` | `round(100 · installs / denom)` (0 if denom=0), half-to-even |
| `next_pct` | `round(100 · (installs+1) / (denom+1))` |
| `needed` | `max(1, floor(0.60·total) + 1 − installs)` if total>0 else 0 |
| `installpay` | `300 · installs` (₹, comma-grouped) |
| `topup` | `max(0, 10000 − 300·installs)` |
| `days_left` | days remaining in the current **IST** calendar month |
| `month` | `"महीना " + (IST_month − 6)` (program month, Jul = 1) |

## Data — real snapshot + refresh

Per-CSP data lives in **`data.json`** (`{ meta, data: { "<userId>": {installs, denom,
pending, tickets} } }`), a real snapshot pulled from Metabase/Snowflake. The page fetches
it, picks the viewer by `?cspId=`, and computes everything client-side. An **unknown
userId falls back to noleads** (safe default).

Refresh it with **`refresh.py`** (runs `sql/metrics.sql`, rewrites `data.json`):

```
python refresh.py           # pull + write data.json
python refresh.py --push     # pull + write + git commit & push (redeploys Pages)
```

`refresh.py` reads `METABASE_API_KEY` from `C:\credentials\.env` — **never committed**.
Schedule it (Task Scheduler / cron) to keep the snapshot fresh, like the poller.

## Viewing / demo

- Open via GitHub Pages, pick a CSP with `?cspId=<userId>` (any casing works).
- Real examples (one per screen): `10453` secured · `11950` almost · `9388` keepgoing · any unknown id (e.g. `000000`) → noleads.
- A demo switcher at the bottom links these (remove it once behind real auth).
- Note: opening the file via `file://` can't `fetch` `data.json` (browser CORS) → shows noleads. Use the hosted URL.

## Going live on the real platform

Right now the data comes from an embedded `SAMPLE` map keyed by `?cspId=` (fine for a
static GitHub-hosted preview). On the authenticated in-house platform, replace
**`getCspData()`** with a call to your backend — that's the whole integration:

```js
async function getCspData(){
  const r = await fetch('/api/mbg/me', { credentials: 'include' }); // session identifies the CSP
  return await r.json();  // { userId, installs, denom, pending, tickets:[{no,area,cid}] }
}
```

The backend only needs to return the **raw** inputs (the same ones the poller derives
from `INSTALL_EXECUTION_CANDIDATES`). All screen routing and number-crunching stays in
`computeMBG()` so the logic lives in one place.

Also swap the in-house analytics hook `track()` (currently a console log) for your own
event pipeline, and give the ticket rows a real deep-link/navigation via `data-cid`.

## Hosting on GitHub Pages

1. Push this folder to a GitHub repo (this file lives at the repo root as `index.html`).
2. Repo → **Settings → Pages** → *Deploy from a branch* → `main` / root.
3. Your link: `https://<user>.github.io/<repo>/` — append `?cspId=100002` to test a CSP.
