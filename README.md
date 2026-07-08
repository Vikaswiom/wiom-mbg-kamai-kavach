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

## Viewing / demo

- Open `index.html` directly, or via GitHub Pages.
- Pick a CSP with `?cspId=` — e.g. `.../?cspId=100002`.
- Sample CSPs (one per screen): `100001` almost · `100002` secured · `100003` keepgoing · `100004` noleads.
- A demo switcher at the bottom links all four (remove it once behind real auth).

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
