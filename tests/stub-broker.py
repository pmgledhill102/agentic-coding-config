#!/usr/bin/env python3
"""A canned-response stand-in for the credential broker.

The helper under test (home/bin/gcp-credentials) talks to the broker over
HTTP and nothing else, so replacing the broker is enough to drive every one
of its exit paths without a Cloud Run service, a Discord bot, or a human.

Responses are read from files on every request rather than held in memory, so
one long-lived server serves a whole test run: the test writes the next
scenario and calls the helper again.

  $STUB_DIR/<endpoint>.status   HTTP status to return    (default 200)
  $STUB_DIR/<endpoint>.json     verbatim response body   (default {})

where <endpoint> is one of: request, poll, exchange, revoke.

Requests are appended to $STUB_DIR/calls.log as "METHOD PATH", so a test can
assert on what the helper *sent* as well as what it did with the reply. The
X-Client-Version header of each call is recorded alongside it, which is the
one piece of the wire contract the broker uses to refuse stale clients.

The chosen port is printed to stdout as "PORT <n>" and then the process
serves until killed. Port 0 lets the OS pick, so concurrent runs do not
collide.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STUB_DIR = os.environ.get("STUB_DIR", ".")


def canned(endpoint):
    """Return (status, body-bytes) for an endpoint, with defaults."""
    status_path = os.path.join(STUB_DIR, endpoint + ".status")
    body_path = os.path.join(STUB_DIR, endpoint + ".json")
    status = 200
    if os.path.exists(status_path):
        with open(status_path) as fh:
            status = int(fh.read().strip() or 200)
    body = b"{}"
    if os.path.exists(body_path):
        with open(body_path, "rb") as fh:
            body = fh.read()
    return status, body


def endpoint_for(method, path):
    if method == "POST" and path == "/request":
        return "request"
    if method == "POST" and path == "/exchange":
        return "exchange"
    if method == "POST" and path.endswith("/revoke"):
        return "revoke"
    if method == "GET" and path.startswith("/requests/"):
        return "poll"
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # the access log would drown the test output

    def _record(self):
        with open(os.path.join(STUB_DIR, "calls.log"), "a") as fh:
            fh.write("%s %s client=%s\n" % (
                self.command,
                self.path,
                self.headers.get("X-Client-Version", "absent"),
            ))

    def _respond(self):
        self._record()
        endpoint = endpoint_for(self.command, self.path)
        if endpoint is None:
            status, body = 404, json.dumps({"error": "no such endpoint"}).encode()
        else:
            status, body = canned(endpoint)
        # Drain the request body, or curl sees a broken pipe rather than the
        # status we are trying to test.
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = _respond
    do_POST = _respond


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print("PORT %d" % server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
