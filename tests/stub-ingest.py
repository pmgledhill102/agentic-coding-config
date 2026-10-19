#!/usr/bin/env python3
"""A stand-in for the telemetry ingest (gcp-org-management ADR 026).

The helper under test (home/bin/agent-telemetry) talks to the ingest over HTTP
and nothing else, so replacing the ingest is enough to drive its paths without
a Cloud Run service.

Behaviour is read from files on every request, so one long-lived server serves
a whole run: the test writes the next scenario and calls the helper again.

  $STUB_DIR/records.mode   "<status> [retry-after=<n>]"   for POST /v1/records/*
  $STUB_DIR/uploads.mode   the same, for POST /v1/uploads
  $STUB_DIR/put.mode       the same, for the signed PUT
  (default 200 for uploads and the PUT, 204 for records)

Everything received is appended to $STUB_DIR/received.jsonl, one object per
request: method, path, the lowercased headers, and the body as text. Header
VALUES are recorded so a test can assert what was sent (a key present, a key
absent); the test, not this server, decides whether that is allowed in output.

The signed-URL flow is imitated: POST /v1/uploads answers with a url pointing
back at this server (/put/<object>), the headers a real signature would bind,
and an object name built from the key name and session; PUT /put/<object>
stores the body under $STUB_DIR/puts/.

The chosen port is printed as "PORT <n>"; port 0 lets the OS pick.
"""

import http.server
import json
import os
import socketserver
import sys

STUB_DIR = os.environ["STUB_DIR"]
PUTS = os.path.join(STUB_DIR, "puts")
os.makedirs(PUTS, exist_ok=True)


def mode(name, default_status):
    """(status, extra headers) from the control file, else the default."""
    try:
        with open(os.path.join(STUB_DIR, name + ".mode")) as f:
            parts = f.read().split()
    except OSError:
        return default_status, {}
    if not parts:
        return default_status, {}
    status = int(parts[0])
    headers = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        headers[k] = v
    return status, headers


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # silence the default stderr access log
        pass

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _record(self, body):
        entry = {
            "method": self.command,
            "path": self.path,
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": body.decode("utf-8", "replace"),
        }
        with open(os.path.join(STUB_DIR, "received.jsonl"), "a") as f:
            f.write(json.dumps(entry) + "\n")

    def _reply(self, status, headers=None, body=b""):
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_POST(self):
        body = self._body()
        self._record(body)
        if self.path.startswith("/v1/records/"):
            status, extra = mode("records", 204)
            hdrs = {"Retry-After": extra["retry-after"]} if "retry-after" in extra else {}
            self._reply(status, hdrs)
        elif self.path == "/v1/uploads":
            status, extra = mode("uploads", 200)
            hdrs = {"Retry-After": extra["retry-after"]} if "retry-after" in extra else {}
            if status != 200:
                self._reply(status, hdrs)
                return
            size = json.loads(body or b"{}").get("size", 0)
            session = self.headers.get("X-Session-Id") or "_nosession"
            n = len(os.listdir(PUTS))
            obj = f"v1/stub-key/{session}/transcript/{n:06d}.part"
            payload = {
                "url": f"http://127.0.0.1:{self.server.server_address[1]}/put/{obj}?sig=SIGNED-URL-SECRET",
                "method": "PUT",
                "headers": {
                    "x-goog-content-length-range": f"1,{size}",
                    "x-goog-if-generation-match": "0",
                },
                "object": obj,
            }
            self._reply(200, {"Content-Type": "application/json"}, json.dumps(payload).encode())
        else:
            self._reply(404)

    def do_PUT(self):
        body = self._body()
        self._record(body)
        status, _ = mode("put", 200)
        # The real URL binds both headers into its signature; refuse without them.
        if not self.headers.get("x-goog-content-length-range") or self.headers.get("x-goog-if-generation-match") != "0":
            self._reply(403)
            return
        if status == 200:
            name = self.path.split("?", 1)[0][len("/put/"):].replace("/", "__")
            with open(os.path.join(PUTS, name), "wb") as f:
                f.write(body)
        self._reply(status)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main():
    srv = Server(("127.0.0.1", 0), Handler)
    print(f"PORT {srv.server_address[1]}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
