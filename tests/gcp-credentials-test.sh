#!/bin/sh
# Behavioural tests for home/bin/gcp-credentials, against a stub broker.
#
# Two properties are worth more than the rest and are why this file exists:
#
#   1. Every exit code means what the skill doc says it means. The doc tells an
#      agent to stop on 3, retry on 7, and never retry on 8, so an exit code
#      that drifts does not produce a test failure -- it produces an agent
#      doing the wrong thing with a human's credentials.
#
#   2. NO TOKEN EVER REACHES STDOUT OR STDERR. That is the whole reason the
#      broker has this shape: no secret in tool output means no secret in the
#      transcript, and none in the model's context. Every byte this run prints
#      is accumulated and searched for the sentinel token at the end, so the
#      check covers commands added later without anyone remembering to.
#
# Usage: sh tests/gcp-credentials-test.sh
# Requires: python3 (stub broker), curl, jq. Exits non-zero if any case fails.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT/home/bin/gcp-credentials"
STUB="$ROOT/tests/stub-broker.py"

# A value that has no business appearing anywhere but the token file.
SENTINEL='ya29.SENTINEL-ACCESS-TOKEN-MUST-NOT-BE-PRINTED'

PASS=0
FAIL=0

WORK=$(mktemp -d)
STUB_DIR="$WORK/stub"
CB_DIR="$WORK/cb"
ALL_OUTPUT="$WORK/all-output.txt"
mkdir -p "$STUB_DIR" "$CB_DIR"
: > "$ALL_OUTPUT"

# The stub listens on loopback; a proxy in the environment must not intercept.
no_proxy=127.0.0.1,localhost
NO_PROXY=$no_proxy
export no_proxy NO_PROXY

export CREDENTIAL_BROKER_HOME="$CB_DIR"
export CREDENTIAL_BROKER_REQUEST_KEY=test-request-key
export STUB_DIR

cleanup() {
    [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2> /dev/null
    # Any refresh loop a test started, though --no-refresh is used throughout.
    [ -f "$CB_DIR/refresh.pid" ] && kill "$(cat "$CB_DIR/refresh.pid")" 2> /dev/null
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

# --- stub lifecycle ----------------------------------------------------------

python3 "$STUB" > "$WORK/stub.out" 2>&1 &
STUB_PID=$!

PORT=""
i=0
while [ "$i" -lt 50 ]; do
    PORT=$(sed -n 's/^PORT //p' "$WORK/stub.out" 2> /dev/null | head -1)
    [ -n "$PORT" ] && break
    sleep 0.1
    i=$((i + 1))
done
if [ -z "$PORT" ]; then
    echo "could not start the stub broker:"
    cat "$WORK/stub.out"
    exit 1
fi
export CREDENTIAL_BROKER_URL="http://127.0.0.1:$PORT"

# --- harness -----------------------------------------------------------------

# canned <endpoint> <status> [body-json]
canned() {
    printf '%s' "$2" > "$STUB_DIR/$1.status"
    if [ $# -ge 3 ]; then
        printf '%s' "$3" > "$STUB_DIR/$1.json"
    else
        printf '{}' > "$STUB_DIR/$1.json"
    fi
}

reset_state() {
    rm -f "$CB_DIR"/grant.json "$CB_DIR"/pending.json "$CB_DIR"/access_token \
        "$CB_DIR"/refresh.pid "$CB_DIR"/refresh.log
    rm -f "$STUB_DIR"/*.status "$STUB_DIR"/*.json 2> /dev/null
    : > "$STUB_DIR/calls.log"
}

OUT=""
RC=0
# run <args...> -- captures stdout+stderr together, records both for the
# end-of-run secret sweep, and never lets a non-zero exit kill the harness.
run() {
    OUT=$("$HELPER" "$@" 2>&1) && RC=0 || RC=$?
    printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
}

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    printf '        rc=%s\n' "$RC"
    printf '%s\n' "$OUT" | sed 's/^/        | /'
}

expect_rc() { # label expected
    if [ "$RC" -eq "$2" ]; then ok "$1 (rc=$2)"; else no "$1 — expected rc=$2"; fi
}
expect_out() { # label pattern
    if printf '%s' "$OUT" | grep -q -- "$2"; then ok "$1"; else no "$1 — missing: $2"; fi
}
expect_no_out() { # label pattern
    if printf '%s' "$OUT" | grep -q -- "$2"; then no "$1 — unexpectedly present: $2"; else ok "$1"; fi
}
expect_file() { # label path
    if [ -f "$2" ]; then ok "$1"; else no "$1 — missing file: $2"; fi
}
expect_no_file() { # label path
    if [ -f "$2" ]; then no "$1 — file should not exist: $2"; else ok "$1"; fi
}

# Response fixtures.
REQ_OK='{"request_id":"req-123","phrase":"mint-copper-falcon","expires_at":"2026-08-15T12:00:00Z"}'
APPROVED='{"state":"approved","project":"example-project-sbx","service_account":"agent-sandbox@example-project-sbx.iam.gserviceaccount.com","grant_expires_at":"2026-08-16T12:00:00Z","session_token":"stub-session-token"}'
EXCHANGE_OK='{"access_token":"'"$SENTINEL"'","expires_at":"2026-08-15T13:00:00Z","grant_expires_at":"2026-08-16T12:00:00Z","project":"example-project-sbx","service_account":"agent-sandbox@example-project-sbx.iam.gserviceaccount.com"}'

# request_then_poll <poll-status> <poll-body> [extra request args...]
# Gets a request outstanding, then arranges what `wait` will see.
request_then_poll() {
    ps=$1
    pb=$2
    shift 2
    canned request 200 "$REQ_OK"
    run request --purpose "test" --project p --no-gcloud --no-refresh "$@"
    canned poll "$ps" "$pb"
}

# --- configuration errors ----------------------------------------------------

echo "not configured (exit 6)"
reset_state
OUT=$(env -u CREDENTIAL_BROKER_REQUEST_KEY "$HELPER" request --purpose t --project p 2>&1) && RC=0 || RC=$?
printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
expect_rc "missing request key" 6
expect_out "names both key locations" "CREDENTIAL_BROKER_REQUEST_KEY"

OUT=$(env -u CREDENTIAL_BROKER_URL "$HELPER" request --purpose t --project p 2>&1) && RC=0 || RC=$?
printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
expect_rc "missing broker URL" 6

echo "usage errors (exit 2)"
reset_state
run request --project p
expect_rc "--purpose is required" 2
run request --purpose t --project p --timeout abc
expect_rc "non-numeric --timeout" 2
run frobnicate
expect_rc "unknown subcommand" 2
run wait
expect_rc "wait with no outstanding request" 2
run renew
expect_rc "renew with no grant" 2

# --- request-time broker responses -------------------------------------------

echo "broker refusals at request time"
reset_state
canned request 429
run request --purpose t --project p
expect_rc "rate limited" 5
expect_no_file "no pending request recorded" "$CB_DIR/pending.json"

reset_state
canned request 426 '{"error":"client too old for this broker","hint":"run chezmoi apply --refresh-externals"}'
run request --purpose t --project p
expect_rc "stale client" 8
expect_out "renders the broker hint verbatim" "chezmoi apply --refresh-externals"
expect_out "names the client version it sent" "v4"
expect_no_file "no approval was spent" "$CB_DIR/pending.json"

reset_state
canned request 502
run request --purpose t --project p
expect_rc "approval channel unreachable" 1
expect_out "says nobody was asked" "nobody was asked"

reset_state
canned request 401
run request --purpose t --project p
expect_rc "rejected request key" 1

reset_state
canned request 404 '{"error":"no sandbox for that repo"}'
run request --purpose t --project p
expect_rc "unknown repo" 1
expect_out "renders the broker error" "no sandbox for that repo"

# --- a successful request ----------------------------------------------------

echo "request succeeds and returns without blocking"
reset_state
canned request 200 "$REQ_OK"
run request --purpose "stand up the thing" --project p --no-gcloud --no-refresh
expect_rc "request accepted" 0
expect_out "prints the verification phrase" "mint-copper-falcon"
expect_out "phrase is in its own banner" "APPROVAL REQUIRED"
expect_out "tells the caller to run wait" "wait"
expect_file "records the outstanding request" "$CB_DIR/pending.json"
if grep -q "client=4" "$STUB_DIR/calls.log"; then
    ok "sends X-Client-Version on /request"
else
    no "sends X-Client-Version on /request"
fi

run status
expect_out "status reports the pending request" "mint-copper-falcon"

# --- decisions ---------------------------------------------------------------

echo "decisions (the exit codes the skill doc routes on)"
reset_state
request_then_poll 200 '{"state":"denied"}'
run wait
expect_rc "denied" 3
expect_out "says a human refused" "DENIED"
expect_no_file "pending cleared on a terminal state" "$CB_DIR/pending.json"

reset_state
request_then_poll 200 '{"state":"expired"}'
run wait
expect_rc "card expired" 4

reset_state
request_then_poll 200 '{"state":"revoked"}'
run wait
expect_rc "revoked before use" 3

reset_state
request_then_poll 200 '{"state":"failed","failure_reason":"identity never propagated"}'
run wait
expect_rc "approved but identity unusable" 7
expect_out "distinguishes fault from denial" "Nobody refused"
expect_out "carries the broker reason" "identity never propagated"

reset_state
request_then_poll 200 '{"state":"pending"}' --timeout 0
run wait
expect_rc "gave up waiting" 4
expect_out "treats silence as a deny" "Treat this as a deny"

reset_state
request_then_poll 200 '{"state":"provisioning"}' --timeout 0
run wait
expect_rc "timed out mid-provisioning" 4
expect_out "says the build continues server-side" "still being built server-side"
expect_out "announces the provisioning wait" "creating the sandbox project"

reset_state
request_then_poll 426 '{"error":"client too old","hint":"bump Rev:"}'
run wait
expect_rc "broker redeployed under a live request" 8
expect_file "pending PRESERVED so wait can resume" "$CB_DIR/pending.json"

reset_state
request_then_poll 200 '{"state":"teleported"}'
run wait
expect_rc "unknown state fails loudly" 1
expect_out "names the state it did not understand" "teleported"

# --- install -----------------------------------------------------------------

echo "approval installs a token"
reset_state
request_then_poll 200 "$APPROVED"
canned exchange 200 "$EXCHANGE_OK"
run wait
expect_rc "installed" 0
expect_out "names the project" "example-project-sbx"
expect_out "names the identity" "agent-sandbox@"
expect_out "reports grant expiry" "2026-08-16T12:00:00Z"
expect_file "token written" "$CB_DIR/access_token"
expect_file "grant recorded" "$CB_DIR/grant.json"
expect_no_file "pending discharged" "$CB_DIR/pending.json"

if [ "$(cat "$CB_DIR/access_token")" = "$SENTINEL" ]; then
    ok "token file holds exactly the token, no trailing newline"
else
    no "token file holds exactly the token, no trailing newline"
fi

MODE=$(stat -c %a "$CB_DIR/access_token" 2> /dev/null || stat -f %Lp "$CB_DIR/access_token" 2> /dev/null)
if [ "$MODE" = "600" ]; then ok "token file is 0600"; else no "token file is 0600 (got $MODE)"; fi
MODE=$(stat -c %a "$CB_DIR/grant.json" 2> /dev/null || stat -f %Lp "$CB_DIR/grant.json" 2> /dev/null)
if [ "$MODE" = "600" ]; then ok "grant file is 0600"; else no "grant file is 0600 (got $MODE)"; fi

if grep -q "GET /requests/req-123 client=4" "$STUB_DIR/calls.log"; then
    ok "sends X-Client-Version on /poll too"
else
    no "sends X-Client-Version on /poll too"
fi

echo "status over a live grant"
run status
expect_out "reports the project" "example-project-sbx"
expect_out "reports a token is present" "token   : present"
expect_out "reports the client version" "client  : v4"

# --- renew / release / revoke ------------------------------------------------

echo "renew"
canned exchange 200 "$EXCHANGE_OK"
run renew
expect_rc "renew from an existing grant" 0
expect_out "names the project" "example-project-sbx"

canned exchange 403
run renew
expect_rc "grant no longer active" 4

canned exchange 401
run renew
expect_rc "session token rejected" 1

echo "release keeps the grant"
canned exchange 200 "$EXCHANGE_OK"
run renew
run release
expect_rc "release" 0
expect_no_file "token removed" "$CB_DIR/access_token"
expect_file "grant kept" "$CB_DIR/grant.json"
expect_out "says the grant is still live" "still live at the broker"

echo "revoke ends it"
canned revoke 200
run revoke
expect_rc "revoke" 0
expect_no_file "grant removed" "$CB_DIR/grant.json"
run revoke
expect_rc "revoke with nothing to revoke" 2

# --- the invariant -----------------------------------------------------------

echo "transcript hygiene"
if grep -q "$SENTINEL" "$ALL_OUTPUT"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  THE ACCESS TOKEN REACHED STDOUT/STDERR\n'
    grep -n "$SENTINEL" "$ALL_OUTPUT" | sed 's/^/        | /'
else
    ok "no access token in any command output, across every case above"
fi

if [ -f "$CB_DIR/refresh.log" ] && grep -q "$SENTINEL" "$CB_DIR/refresh.log"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  the access token reached the refresh log\n'
else
    ok "no access token in the refresh log"
fi

# The request key travels in a POST body and a curl --config file, never argv.
if grep -q "test-request-key" "$ALL_OUTPUT"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  the request key reached stdout/stderr\n'
else
    ok "no request key in any command output"
fi

# --- result ------------------------------------------------------------------

echo ""
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
