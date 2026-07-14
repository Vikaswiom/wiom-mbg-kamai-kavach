#!/usr/bin/env python
"""Static server for Railway — serves the MBG banner dashboard on $PORT.

Stdlib only (no dependencies). data.js and the page shell are sent no-store so
the hourly data refresh shows immediately without a hard reload. Railway sets
$PORT; we bind 0.0.0.0 so the container is reachable.
"""
import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", "8080"))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        path = self.path.split("?")[0]
        if path == "/" or path.endswith(("data.js", "index.html")):
            self.send_header("Cache-Control", "no-store, max-age=0")
        super().end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"dashboard serving on 0.0.0.0:{PORT}", flush=True)
    httpd.serve_forever()
