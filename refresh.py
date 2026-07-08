#!/usr/bin/env python3
"""
Refresh the MBG / Kamai Kavach data snapshot.

Runs sql/metrics.sql against Metabase (Snowflake), transforms the rows into the
per-CSP RAW inputs the banner needs, and writes data.json (committed to the repo,
served alongside index.html on GitHub Pages).

The page computes screen/pct/needed/etc. itself from these raw inputs — this script
only supplies { userId, installs, denom, pending, tickets:[{no,area,cid}] } per identity.

Usage:
    python refresh.py           # pull + write data.json
    python refresh.py --push    # pull + write + git commit & push (redeploys Pages)

Secrets: reads METABASE_API_KEY from C:\\credentials\\.env (never committed).
"""
import os, sys, json, subprocess, urllib.request
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = r"C:\credentials\.env"
DB   = 113
URL  = "https://metabase.wiom.in/api/dataset"
IST  = timezone(timedelta(hours=5, minutes=30))


def api_key():
    with open(ENV, encoding="utf-8") as f:
        for line in f:
            if line.startswith("METABASE_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("METABASE_API_KEY not found in " + ENV)


def run_sql(sql):
    body = json.dumps({"database": DB, "type": "native", "native": {"query": sql}}).encode()
    req = urllib.request.Request(URL, data=body,
        headers={"x-api-key": api_key(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    if "data" not in d or d["data"].get("rows") is None:
        raise SystemExit("Metabase error: " + json.dumps(d)[:1000])
    cols = [c["name"] for c in d["data"]["cols"]]
    return cols, d["data"]["rows"]


def build():
    with open(os.path.join(HERE, "sql", "metrics.sql"), encoding="utf-8") as f:
        sql = f.read()
    cols, rows = run_sql(sql)
    idx = {c: i for i, c in enumerate(cols)}

    def ticket(r, n):
        no = r[idx[f"T{n}_NO"]]
        if not no:
            return None
        return {"no": no, "area": r[idx[f"T{n}_AREA"]] or "", "cid": r[idx[f"T{n}_CID"]] or ""}

    data = {}
    for r in rows:
        cid = str(r[idx["CSP_ID"]])                       # key by cspId (e.g. a0a0b1)
        tickets = [t for t in (ticket(r, 1), ticket(r, 2)) if t]
        data[cid] = {
            "cspId":    cid,
            "userId":   str(r[idx["USER_ID"]] or ""),     # representative identity (for mbg_id/tracking)
            "installs": int(r[idx["INSTALLS"]] or 0),
            "denom":    int(r[idx["DENOM"]] or 0),
            "pending":  int(r[idx["PENDING"]] or 0),
            "tickets":  tickets,
        }

    out = {
        "meta": {
            "generated_ist": datetime.now(IST).strftime("%Y-%m-%d %H:%M IST"),
            "count": len(data),
            "note": "Raw MBG inputs per identity; screen/pct/needed computed client-side in index.html.",
        },
        "data": data,
    }
    path = os.path.join(HERE, "data.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {len(data)} identities -> data.json ({out['meta']['generated_ist']})")
    return len(data)


def git_push(n):
    msg = f"data: refresh snapshot ({n} identities)"
    subprocess.run(["git", "-C", HERE, "add", "data.json"], check=True)
    subprocess.run(["git", "-C", HERE, "-c", "commit.gpgsign=false", "commit", "-q", "-m", msg], check=True)
    subprocess.run(["git", "-C", HERE, "push", "-q", "origin", "main"], check=True)
    print("pushed -> GitHub Pages will redeploy in ~1 min")


if __name__ == "__main__":
    n = build()
    if "--push" in sys.argv:
        git_push(n)
