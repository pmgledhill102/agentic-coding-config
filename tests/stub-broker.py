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

A POST body is also written verbatim to $STUB_DIR/<endpoint>-body.json,
overwritten per call. Some of this contract is about a field NOT being sent --
the broker 400s a teardown that names a project, deliberately, so that a client
cannot believe it targeted a sandbox it did not -- and an absence is only
testable against the bytes that actually went out.

Each calls.log line also says whether the call carried an X-Request-Key header
(key=header) or not (key=absent) -- never its value.

If $STUB_DIR/key-mode contains "proxy", the stub plays a broker behind a
platform proxy that supplies the key itself: any request carrying X-Request-Key
or a request_key body field is refused with 401. A helper in proxy-supplied
mode must send neither, and this is what makes a leak of either one a test
failure rather than a silent pass. Like everything else here it is re-read per
request, so a test can switch it on and off.

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


def proxy_mode():
    path = os.path.join(STUB_DIR, "key-mode")
    if not os.path.exists(path):
        return False
    with open(path) as fh:
        return fh.read().strip() == "proxy"


def client_sent_key(headers, body_sent):
    """True if the client presented a key in either carrier."""
    if headers.get("X-Request-Key") is not None:
        return True
    if not body_sent:
        return False
    try:
        return "request_key" in json.loads(body_sent)
    except (ValueError, TypeError):
        return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # the access log would drown the test output

    def _record(self):
        with open(os.path.join(STUB_DIR, "calls.log"), "a") as fh:
            fh.write("%s %s client=%s key=%s\n" % (
                self.command,
                self.path,
                self.headers.get("X-Client-Version", "absent"),
                "header" if self.headers.get("X-Request-Key") is not None else "absent",
            ))

    def _respond(self):
        self._record()
        endpoint = endpoint_for(self.command, self.path)
        # Drain the request body, or curl sees a broken pipe rather than the
        # status we are trying to test. Kept rather than discarded, so a test
        # can assert on what was sent as well as on what came back.
        body_sent = b""
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            body_sent = self.rfile.read(length)
            if endpoint is not None:
                path = os.path.join(STUB_DIR, endpoint + "-body.json")
                with open(path, "wb") as fh:
                    fh.write(body_sent)

        if endpoint is None:
            status, body = 404, json.dumps({"error": "no such endpoint"}).encode()
        elif proxy_mode() and client_sent_key(self.headers, body_sent):
            status = 401
            body = json.dumps({"error": "unauthorized",
                               "stub": "a key was sent by the client in proxy mode"}).encode()
        else:
            status, body = canned(endpoint)
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
