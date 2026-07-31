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

    # ── Per-month payout snapshots (data-<month>.json) ────────────────────────
    # Keep the CURRENT month's snapshot current; when the clock (IST) rolls to the
    # next month this stops writing the old file, so each month's LAST write stays
    # frozen — the settle screens read data-<month>.json via ?month=. Timing-proof:
    # no exact midnight moment to hit, and the IST month boundary here matches
    # metrics.sql's own, so each data-<month>.json only ever holds that month.
    # The program runs Jul–Sep 2026; other months are ignored.
    now = datetime.now(IST)
    MONTHKEY = {7: "july", 8: "aug", 9: "sep"}
    key = MONTHKEY.get(now.month) if now.year == 2026 else None
    if key:
        with open(os.path.join(HERE, "data-%s.json" % key), "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        print("also wrote data-%s.json (current-month snapshot; prior months stay frozen)" % key)
    else:
        print("outside Jul–Sep 2026 — month snapshots left frozen")
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

    # keep the fresh snapshot(s) in memory: the sync below resets the working
    # tree. All data-<month>.json ride along; frozen months rewrite identically
    # (no diff → not re-committed), only the current month's file changes.
    rels = ["data.json"]
    for fn in sorted(os.listdir(HERE)):
        if fn.startswith("data-") and fn.endswith(".json"):
            rels.append(fn)
    fresh = {}
    for rel in rels:
        with open(os.path.join(HERE, rel), encoding="utf-8") as f:
            fresh[rel] = f.read()

    msg = f"data: refresh snapshot ({n} CSPs)"
    for attempt in range(1, 4):
        # hard-sync to origin/main FIRST — main moves under this job (other people
        # push UI/docs commits), and a plain push from a stale clone is rejected
        # as non-fast-forward, which is exactly how the old pipeline died
        git("fetch", "origin", "main", check=True)
        git("reset", "--hard", "FETCH_HEAD", check=True)
        for rel, content in fresh.items():
            with open(os.path.join(HERE, rel), "w", encoding="utf-8") as f:
                f.write(content)
            git("add", rel, check=True)
        # only push when something actually changed — avoids empty commits and
        # needless GitHub Pages rebuilds (Pages allows ~10 builds/hour). In
        # August, data-july.json is rewritten identical (frozen) so it shows no
        # diff and only a genuine data.json change triggers a push.
        if git("diff", "--cached", "--quiet").returncode == 0:
            print("no data change — skip push")
            return
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
