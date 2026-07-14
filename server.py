#!/usr/bin/env python
"""Railway entrypoint: static server + self-refreshing data.

Serves the whole repo:
    /                      -> CSP banner        (index.html + data.json)
    /analytics-dashboard/  -> analytics dashboard (index.html + data.js)

and runs a background thread that rebuilds BOTH data files straight from
Metabase every REFRESH_MINUTES. This replaces the GitHub Actions cron, which
does not fire reliably — the live app now keeps its own data fresh.

Requires METABASE_API_KEY in the environment (Railway -> Variables).

Notes:
  * Data files are rewritten on the container's ephemeral disk; nothing is
    committed to git. After a redeploy the repo's committed snapshot is served
    until the first refresh finishes (a few seconds later).
  * A failing refresh never takes the site down — it logs and retries next cycle,
    and the last-good data keeps being served.
"""
import http.server
import importlib.util
import os
import socketserver
import threading
import time
import traceback

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8080"))
REFRESH_MINUTES = int(os.environ.get("REFRESH_MINUTES", "15"))
NO_CACHE_SUFFIXES = ("data.json", "data.js", "index.html", "/")


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def refresh_once():
    """Rebuild the banner's data.json and the dashboard's data.js (no git)."""
    banner = _load(os.path.join(ROOT, "refresh.py"), "banner_refresh")
    n = banner.build()
    dash = _load(os.path.join(ROOT, "analytics-dashboard", "refresh.py"), "dash_refresh")
    d = dash.build()
    print(f"[refresh] banner={n} CSPs · dashboard={d['last_updated']}", flush=True)


def refresh_loop():
    while True:
        try:
            refresh_once()
            print(f"[refresh] ok — next in {REFRESH_MINUTES}m", flush=True)
        except Exception:
            # never let a bad refresh kill the server; keep serving last-good data
            print("[refresh] FAILED (serving last-good data):\n" + traceback.format_exc(),
                  flush=True)
        time.sleep(REFRESH_MINUTES * 60)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        path = self.path.split("?")[0]
        if path.endswith(NO_CACHE_SUFFIXES):
            # the data is rewritten in place — never let a browser cache it
            self.send_header("Cache-Control", "no-store, max-age=0")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # keep Railway logs to refresh output only


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    # bind the port first (Railway health check), refresh in the background
    threading.Thread(target=refresh_loop, daemon=True).start()
    with Server(("0.0.0.0", PORT), Handler) as httpd:
        print(f"serving {ROOT} on 0.0.0.0:{PORT} (refresh every {REFRESH_MINUTES}m)",
              flush=True)
        httpd.serve_forever()
