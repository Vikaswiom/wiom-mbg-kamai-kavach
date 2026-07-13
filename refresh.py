#!/usr/bin/env python3
"""
Refresh the MBG / Kamai Kavach data snapshot.

Runs sql/metrics.sql against Metabase (Snowflake), transforms the rows into the
per-CSP RAW inputs the banner needs, and writes data.json (committed to the repo,
served alongside index.html on GitHub Pages).

The page computes screen/pct/needed/etc. itself from these raw inputs — this script
only supplies { userId, installs, denom, pending, committed, tickets:[{no,area,cid}] }
per identity. (committed = open leads whose CURRENT attempt has a confirmed slot;
used by the almost screen's needed.)

Usage:
    python refresh.py           # pull + write data.json
    python refresh.py --push    # pull + write + git commit & push (redeploys Pages)

Runs on a schedule in GitHub Actions (.github/workflows/refresh-data.yml).

Secrets: reads METABASE_API_KEY from the environment (CI), falling back to
C:\\credentials\\.env for local runs (never committed).

NOTE on --push: it hard-syncs this clone to origin/main before committing
(the snapshot is fully regenerated each run, so nothing of value can be lost),
which means any local-only commits or edits in the clone are DISCARDED.
Run it only from a dedicated refresh clone or CI, never a working dev copy.
"""
import os, sys, json, subprocess, urllib.request
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = r"C:\credentials\.env"
DB   = 113
URL  = "https://metabase.wiom.in/api/dataset"
IST  = timezone(timedelta(hours=5, minutes=30))


def api_key():
    key = os.environ.get("METABASE_API_KEY", "").strip()
    if key:
        return key
    try:
        with open(ENV, encoding="utf-8") as f:
            for line in f:
                if line.startswith("METABASE_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    raise SystemExit("METABASE_API_KEY not set in the environment and not found in " + ENV)


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
            "installs":  int(r[idx["INSTALLS"]] or 0),
            "denom":     int(r[idx["DENOM"]] or 0),
            "pending":   int(r[idx["PENDING"]] or 0),
            "committed": int(r[idx["COMMITTED"]] or 0),
            "tickets":   tickets,
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
    def git(*args, check=False):
        return subprocess.run(["git", "-C", HERE, *args], check=check)

    # refuse to run from a feature-branch checkout — the hard sync below would
    # clobber it (this script's push flow is main-only by design)
    branch = subprocess.run(["git", "-C", HERE, "rev-parse", "--abbrev-ref", "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
    if branch != "main":
        raise SystemExit(f"--push must run from a 'main' checkout (this clone is on '{branch}')")

    # keep the fresh snapshot in memory: the sync below resets the working tree
    path = os.path.join(HERE, "data.json")
    with open(path, encoding="utf-8") as f:
        fresh = f.read()

    msg = f"data: refresh snapshot ({n} CSPs)"
    for attempt in range(1, 4):
        # hard-sync to origin/main FIRST — main moves under this job (other people
        # push UI/docs commits), and a plain push from a stale clone is rejected
        # as non-fast-forward, which is exactly how the old pipeline died
        git("fetch", "origin", "main", check=True)
        git("reset", "--hard", "FETCH_HEAD", check=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(fresh)
        # only push when data.json actually changed — avoids empty commits and
        # needless GitHub Pages rebuilds (Pages allows ~10 builds/hour)
        if git("diff", "--quiet", "--", "data.json").returncode == 0:
            print("no data change — skip push")
            return
        git("add", "data.json", check=True)
        git("-c", "commit.gpgsign=false", "commit", "-q", "-m", msg, check=True)
        if git("push", "-q", "origin", "HEAD:main").returncode == 0:
            print("pushed -> GitHub Pages will redeploy in ~1 min")
            return
        print(f"push rejected (main moved mid-run?) — resync and retry {attempt}/3")
    raise SystemExit("push failed after 3 attempts")


if __name__ == "__main__":
    n = build()
    if "--push" in sys.argv:
        git_push(n)
