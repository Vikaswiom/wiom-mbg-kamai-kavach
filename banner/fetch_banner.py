#!/usr/bin/env python3
"""
Refresh banner-data.json — MBG banner_opened engagement for the 477 enrolled CSPs.

Runs one query against Metabase (db 113, Snowflake), joining the 477 cspIds ->
CleverTap IDs -> banner_opened events since the payout window, and writes the
aggregated metrics (overall, by payout outcome, daily) to ../banner-data.json.

CleverTap EVENTS_DATA.TIMESTAMP is ALREADY IST (do NOT add +330).
Secret: METABASE_API_KEY (env / CI). Run by .github/workflows/refresh-banner.yml.
"""
import os, sys, json, subprocess, urllib.request
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
IST  = timezone(timedelta(hours=5, minutes=30))
WINDOW_START = "2026-08-01 12:30:00"    # since the 1-Aug payout (IST)


def api_key():
    k = os.environ.get("METABASE_API_KEY", "").strip()
    if k:
        return k
    for envf in (r"C:\credentials\.env", os.path.join(ROOT, ".env")):
        try:
            for line in open(envf, encoding="utf-8"):
                if line.startswith("METABASE_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
        except OSError:
            pass
    raise SystemExit("METABASE_API_KEY not set")


def run_sql(sql):
    req = urllib.request.Request("https://metabase.wiom.in/api/dataset",
        data=json.dumps({"database": 113, "type": "native", "native": {"query": sql}}).encode(),
        headers={"x-api-key": api_key(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    if "data" not in d or d["data"].get("rows") is None:
        raise SystemExit("Metabase error: " + json.dumps(d)[:800])
    cols = [c["name"] for c in d["data"]["cols"]]
    return cols, d["data"]["rows"]


def main():
    groups = json.load(open(os.path.join(HERE, "banner-groups.json")))   # {cspid: 'topup'|'piece'}
    eligible = list(groups.keys())
    inlist = "','".join(eligible)

    # one query: per (cspId, day) open counts + first/last timestamp
    sql = f"""
WITH prof AS (
  SELECT DISTINCT LOWER(CSPID) AS cspid, CLEVERTAP_ID
  FROM PROD_DB.CLEVERTAP_CSP_API.PROFILE_DATA
  WHERE _FIVETRAN_DELETED = FALSE AND LOWER(CSPID) IN ('{inlist}')
),
opens AS (
  SELECT p.cspid, e.TIMESTAMP AS ts
  FROM PROD_DB.CLEVERTAP_CSP_API.EVENTS_DATA e
  JOIN prof p ON p.CLEVERTAP_ID = e.CLEVERTAP_ID
  WHERE e.EVENT_NAME = 'banner_opened' AND e._FIVETRAN_DELETED = FALSE
    AND e.TIMESTAMP >= '{WINDOW_START}'
)
SELECT cspid, TO_DATE(ts) AS d, COUNT(*) AS n, MIN(ts) AS mn, MAX(ts) AS mx
FROM opens GROUP BY cspid, TO_DATE(ts)
"""
    cols, rows = run_sql(sql)
    ix = {c: i for i, c in enumerate(cols)}

    opened_csps = set()
    total_opens = 0
    daily = {}                       # date -> {csps:set, opens:int}
    grp_open = {"topup": set(), "piece": set()}
    mn = mx = None
    for r in rows:
        c = str(r[ix["CSPID"]]).lower(); d = str(r[ix["D"]])[:10]; n = int(r[ix["N"]] or 0)
        opened_csps.add(c); total_opens += n
        daily.setdefault(d, {"csps": set(), "opens": 0})
        daily[d]["csps"].add(c); daily[d]["opens"] += n
        g = groups.get(c)
        if g in grp_open:
            grp_open[g].add(c)
        rmn, rmx = r[ix["MN"]], r[ix["MX"]]
        mn = rmn if mn is None or rmn < mn else mn
        mx = rmx if mx is None or rmx > mx else mx

    grp_total = {"topup": sum(1 for v in groups.values() if v == "topup"),
                 "piece": sum(1 for v in groups.values() if v == "piece")}
    n_elig = len(eligible)
    n_open = len(opened_csps)

    def pct(a, b): return round(100.0 * a / b) if b else 0

    out = {
        "generated_ist": datetime.now(IST).strftime("%Y-%m-%d %H:%M IST"),
        "window_start":  WINDOW_START + " IST",
        "eligible":      n_elig,
        "csps_opened":   n_open,
        "pct_opened":    pct(n_open, n_elig),
        "total_opens":   total_opens,
        "avg_per_opener": round(total_opens / n_open, 1) if n_open else 0,
        "first_open":    str(mn) if mn else None,
        "last_open":     str(mx) if mx else None,
        "by_outcome": {
            "topup": {"label": "Got a top-up (guarantee applied)",
                      "opened": len(grp_open["topup"]), "total": grp_total["topup"],
                      "pct": pct(len(grp_open["topup"]), grp_total["topup"])},
            "piece": {"label": "No top-up — <60% & \u22653 leads",
                      "opened": len(grp_open["piece"]), "total": grp_total["piece"],
                      "pct": pct(len(grp_open["piece"]), grp_total["piece"])},
        },
        "daily": [{"date": d, "csps": len(daily[d]["csps"]), "opens": daily[d]["opens"]}
                  for d in sorted(daily)],
    }
    with open(os.path.join(ROOT, "banner-data.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("wrote banner-data.json:", n_open, "of", n_elig, "opened,", total_opens, "opens")
    return out


def git_push():
    def git(*a, check=False): return subprocess.run(["git", "-C", ROOT, *a], check=check)
    path = os.path.join(ROOT, "banner-data.json")
    fresh = open(path, encoding="utf-8").read()
    for attempt in range(1, 4):
        git("fetch", "origin", "main", check=True)
        git("reset", "--hard", "FETCH_HEAD", check=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(fresh)
        git("add", "banner-data.json", check=True)
        if git("diff", "--cached", "--quiet").returncode == 0:
            print("no change — skip push"); return
        git("-c", "commit.gpgsign=false", "commit", "-q", "-m",
            "data: refresh banner engagement", check=True)
        if git("push", "-q", "origin", "HEAD:main").returncode == 0:
            print("pushed"); return
        print(f"push rejected — retry {attempt}/3")
    raise SystemExit("push failed after 3 attempts")


if __name__ == "__main__":
    main()
    if "--push" in sys.argv:
        git_push()
