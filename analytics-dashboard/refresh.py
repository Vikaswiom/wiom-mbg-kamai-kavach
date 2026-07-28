#!/usr/bin/env python
"""Refresh the MBG banner analytics dashboard: re-run Metabase queries, regenerate
data.js, commit and push.

This file is kept byte-identical in both homes of the dashboard:
  * Vikaswiom/wiom-mbg-banner-dashboard  — standalone repo, served on GitHub Pages
  * Wiom-using-AI/wiom-mbg-kamai-kavach  — as analytics-dashboard/, served on Railway
    (there, server.py also calls build() directly on a timer)

build() is pure (no git) so the Railway server can call it; main() adds the
commit + push and is what the GitHub Actions job runs."""
import json, os, subprocess, time, urllib.request
from datetime import datetime, timezone, timedelta

# REPO = the directory holding this file — the repo root in the standalone repo, or
# the analytics-dashboard/ subfolder in the monorepo. Either way `git -C REPO` resolves
# the enclosing repo, and staging "data.js" stages the copy next to this script.
REPO = os.path.dirname(os.path.abspath(__file__))
URL = "https://metabase.wiom.in/api/dataset"
IST = timezone(timedelta(hours=5, minutes=30))


def get_api_key():
    """Read the Metabase key from env (GitHub secret) or a local .env fallback.
    Never hard-coded — this repo is public."""
    k = os.environ.get("METABASE_API_KEY")
    if k:
        return k.strip()
    for envf in (r"C:\credentials\.env", os.path.join(REPO, ".env")):
        if os.path.exists(envf):
            for line in open(envf, encoding="utf-8"):
                if line.strip().startswith("METABASE_API_KEY"):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("METABASE_API_KEY not set (env var or C:\\credentials\\.env)")


_API_KEY = None


def api_key():
    """Resolved lazily (and cached) — importing this module must never fail just
    because the key isn't set; server.py catches that at refresh time instead."""
    global _API_KEY
    if _API_KEY is None:
        _API_KEY = get_api_key()
    return _API_KEY


def log(msg):
    line = datetime.now(IST).strftime("%Y-%m-%d %H:%M:%S") + "  " + msg
    print(line)
    with open(os.path.join(REPO, "refresh.log"), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def run_sql(sql):
    payload = {"database": 113, "type": "native", "native": {"query": sql}}
    req = urllib.request.Request(
        URL, data=json.dumps(payload).encode(),
        headers={"x-api-key": api_key(), "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.loads(resp.read().decode())
    cols = [c["name"] for c in data["data"]["cols"]]
    rows = data["data"]["rows"]
    return [dict(zip(cols, r)) for r in rows]


def by_group(rows):
    return {r["GRP"]: r for r in rows}


def build():
    """Re-run the queries and rewrite data.js. No git — safe to call from the
    live server's background refresh thread (server.py). Returns the data dict."""
    log("start")
    csp = by_group(run_sql(open(os.path.join(REPO, "query_csp_funnel.sql")).read()))
    seg = {r["SEGMENT"]: r for r in run_sql(
        open(os.path.join(REPO, "query_segment_funnel.sql")).read())}
    eff = {(r["PERIOD"], r["CATEGORY"]): r for r in run_sql(
        open(os.path.join(REPO, "query_efficiency.sql")).read())}
    roster = run_sql(open(os.path.join(REPO, "query_enrolled_roster.sql")).read())[0]

    def g(d, k):
        return int(d.get(k) or 0)

    m = csp["MBG"]

    def seg_obj(key):
        s = seg[key]
        return {
            "base": g(s, "BASE_CSPS"), "active": g(s, "ACTIVE_CSPS"),
            # per-CSP: reached the stage at least once
            "slot": g(s, "SLOT_CSPS"), "tech": g(s, "TECH_CSPS"),
            "install": g(s, "INSTALL_CSPS"),
            # per-TASK: how many connections/tasks reached the stage
            "tasks": g(s, "CONNECTIONS"),
            "t_slot_prop": g(s, "T_SLOT_PROP"), "t_slot_conf": g(s, "T_SLOT_CONF"),
            "t_tech": g(s, "T_TECH"), "t_arrived": g(s, "T_ARRIVED"),
            "t_install": g(s, "T_INSTALL"),
        }

    now = datetime.now(IST)

    data = {
        "last_updated": now.strftime("%d %b %Y, %I:%M %p IST"),
        "window_start": "09 Jul",
        "window_end": now.strftime("%d %b %Y"),
        "live": 425,
        "engagement": {
            "clicked": g(m, "CLICKERS"), "clicks": g(m, "TOTAL_CLICKS"),
            "ct_profiles": g(m, "CT_PROFILES"),
            "c1": g(m, "C1"), "c2": g(m, "C2"), "c3": g(m, "C3"), "c4plus": g(m, "C4PLUS"),
        },
        "segments": {
            "clicked": seg_obj("A_clicked"),
            "noclick": seg_obj("B_noclick"),
            "nonmbg": seg_obj("C_nonmbg"),
        },
        # enrolled roster funnel: full 429 → with-leads (292) → 60%+/- → no-lead split
        "enrolled_roster": {
            "total": g(roster, "ENROLLED_TOTAL"),
            "with_leads": g(roster, "WITH_LEADS"),
            "eff_60_plus": g(roster, "EFF_60_PLUS"),
            "eff_60_minus": g(roster, "EFF_60_MINUS"),
            "pending_only": g(roster, "PENDING_ONLY"),
            "no_activity": g(roster, "NO_ACTIVITY"),
            "installs": g(roster, "TOTAL_INSTALLS"),
            "leads": g(roster, "TOTAL_LEADS"),
        },
        "efficiency": {
            period: {cat: {
                "partners": g(eff.get((period, cat), {}), "PARTNERS"),   # with leads (denom>0)
                "leads": g(eff.get((period, cat), {}), "LEADS"),         # resolved slot-confirmed leads
                "installs": g(eff.get((period, cat), {}), "INSTALLS"),
                "agg_eff": float((eff.get((period, cat)) or {}).get("AGG_EFF") or 0),
                "secured": g(eff.get((period, cat), {}), "SECURED"),     # cleared the 60% gate
                "pct_secured": float((eff.get((period, cat)) or {}).get("PCT_SECURED") or 0),
            } for cat in ("enrolled", "eligible", "nonmbg")}
            for period in ("june", "july")},
    }

    out = "// Auto-generated by refresh.py — do not edit by hand.\n"
    out += "window.DASHBOARD_DATA = " + json.dumps(data, indent=2) + ";\n"
    with open(os.path.join(REPO, "data.js"), "w", encoding="utf-8") as f:
        f.write(out)
    log("built data.js (" + data["last_updated"] + ")")
    return data


def main():
    """CLI / GitHub Actions path: build, then commit + push data.js.

    This dashboard lives as a subfolder in the shared banner repo, whose own
    hourly job — and this job's own prior runs — push to the same main. Rebasing
    our commit onto a moved main CONFLICTS whenever data.js also changed remotely
    (two refreshes racing), which is what kept failing all four attempts in the
    same second. Instead we re-lay our freshly-built data.js on top of the latest
    remote each attempt: fetch -> hard-reset to origin/main -> rewrite data.js ->
    commit -> push. A concurrent push can only cost us a retry, never a conflict.
    """
    data = build()
    data_js = os.path.join(REPO, "data.js")
    with open(data_js, "rb") as f:
        fresh = f.read()                       # authoritative freshly-built bytes

    def git(*a, check=True):
        return subprocess.run(["git", "-C", REPO, *a], check=check,
                              capture_output=True, text=True)

    for attempt in range(1, 6):
        git("fetch", "origin", "main")
        git("reset", "--hard", "origin/main")            # clean slate = latest remote
        with open(data_js, "wb") as f:
            f.write(fresh)                                # lay our build on top
        git("add", "data.js")                            # REPO = analytics-dashboard/, stages that folder's data.js
        if not git("status", "--porcelain", "data.js").stdout.strip():
            log("no change vs latest main — nothing to push")
            return
        git("-c", "user.name=Vikaswiom", "-c", "user.email=design.3@wiom.in",
            "commit", "-m", "chore: hourly analytics dashboard refresh " + data["last_updated"])
        push = git("push", "origin", "HEAD:main", check=False)
        if push.returncode == 0:
            log("pushed: %s (attempt %d)" % (data["last_updated"], attempt))
            return
        tail = (push.stderr.strip().splitlines() or [""])[-1]
        log("push rejected (main moved) — resync and retry %d/5: %s" % (attempt, tail))
        time.sleep(2 * attempt)                          # backoff before re-fetch
    raise RuntimeError("push failed after 5 attempts")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log("ERROR: " + repr(exc))
        raise
