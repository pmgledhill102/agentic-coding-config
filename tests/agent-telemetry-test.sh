#!/bin/sh
# Behavioural tests for home/bin/agent-telemetry and its Claude hook wrapper,
# against a stub ingest.
#
# What this protects, in order of cost if it breaks:
#
#   1. NO KEY OR SIGNED URL EVER REACHES ARGV, STDOUT OR STDERR. The key travels
#      in a 0600 curl --config file, and so does the upload URL, which is a
#      credential for its 15-minute life. A fake `curl` on PATH records every
#      argument the helper passes, and the whole run's output is swept for the
#      sentinels at the end, so the check covers cases added later.
#   2. THE HELPER NEVER FAILS OR SLOWS ITS CALLER. With no URL configured it
#      spools and exits 0, silently; an unusable state directory is one stderr
#      line and still exit 0; `event` stays well under 100 ms.
#   3. THE OFFSET ADVANCES ONLY ON 2xx. Anything else leaves it, so the next
#      ship resumes; a 429/503 backs off by Retry-After; shipping again after
#      success sends nothing.
#   4. THE ALLOWLIST HOLDS. An unlisted key never reaches the spool, and values
#      are charset-restricted and capped.
#
# Usage: sh tests/agent-telemetry-test.sh
# Requires: python3 (stub ingest), curl, jq. Exits non-zero if any case fails.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT/home/bin/agent-telemetry"
HOOK="$ROOT/home/bin/agent-telemetry-claude-hook"
STUB="$ROOT/tests/stub-ingest.py"

# Values that have no business appearing in any output or argv.
KEY_SENTINEL='tlm_SENTINEL-WRITE-KEY-MUST-NOT-BE-PRINTED-0123456789abcdef'
URL_SENTINEL='SIGNED-URL-SECRET'

PASS=0
FAIL=0

WORK=$(mktemp -d)
STUB_DIR="$WORK/stub"
ALL_OUTPUT="$WORK/all-output.txt"
mkdir -p "$STUB_DIR" "$WORK/bin" "$WORK/home/.agents"
: > "$ALL_OUTPUT"

# Isolate every path the helper derives from $HOME.
HOME="$WORK/home"
export HOME STUB_DIR
unset TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY AGENT_TELEMETRY_HOME AGENT_TELEMETRY_MARKER \
    AGENT_TELEMETRY_MANIFEST AGENT_TELEMETRY_CONFIG AGENT_TELEMETRY_STOP_EVERY

STATE="$HOME/.agents/telemetry"
SPOOL="$STATE/spool.jsonl"
MARKER="$HOME/.agents/.session-marker"
MANIFEST="$HOME/.agents/.bootstrap-manifest"
RECEIVED="$STUB_DIR/received.jsonl"
ARGV_LOG="$WORK/curl-argv.log"

# The stub listens on loopback; a proxy in the environment must not intercept.
no_proxy=127.0.0.1,localhost
NO_PROXY=$no_proxy
export no_proxy NO_PROXY

cleanup() {
    [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2> /dev/null
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

# A curl that records its argv, then runs the real one. Process listings show
# argv to anyone on the machine, so this is what "never in argv" is checked
# against: every argument the helper ever passes is in this file.
REAL_CURL=$(command -v curl)
cat > "$WORK/bin/curl" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$ARGV_LOG"
exec "$REAL_CURL" "\$@"
EOF
chmod +x "$WORK/bin/curl"
PATH="$WORK/bin:$PATH"
export PATH

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
    echo "could not start the stub ingest:"
    cat "$WORK/stub.out"
    exit 1
fi
STUB_URL="http://127.0.0.1:$PORT"

# --- harness -----------------------------------------------------------------

ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    [ $# -lt 2 ] || printf '        %s\n' "$2"
}
expect() { # expect <description> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2', got '$3'"; fi
}

OUT=""
RC=0
run() {
    OUT=$("$HELPER" "$@" 2>&1) && RC=0 || RC=$?
    printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
}
expect_rc() { expect "$1" "$2" "$RC"; }
expect_out() {
    case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1" "output lacked '$2': $OUT" ;; esac
}
expect_no_out() {
    case "$OUT" in *"$2"*) bad "$1" "output had '$2': $OUT" ;; *) ok "$1" ;; esac
}

nputs() { find "$STUB_DIR/puts" -type f | wc -l | tr -d ' '; }
# Every uploaded object, concatenated in object-name order: what a reader does.
puts_cat() { find "$STUB_DIR/puts" -type f | sort | while read -r f; do cat "$f"; done; }
puts_last() { cat "$(find "$STUB_DIR/puts" -type f | sort | tail -1)"; }
# A failing `< file` is reported by the shell before any 2>/dev/null applies.
count_lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
spool_lines() { count_lines "$SPOOL"; }
spool_size() { if [ -f "$SPOOL" ]; then wc -c < "$SPOOL" | tr -d ' '; else echo 0; fi; }
# Lines in the body of the last request (jq -r adds a newline of its own, so count text lines).
body_lines() { tail -1 "$RECEIVED" | jq -r .body | grep -c .; }
offset() { head -1 "$STATE/shipped.offset" 2> /dev/null || echo 0; }
requests() { count_lines "$RECEIVED"; }
last_req() { tail -1 "$RECEIVED" | jq -r "$1"; }
set_mode() { printf '%s' "$2" > "$STUB_DIR/$1.mode"; }
clear_modes() { rm -f "$STUB_DIR"/*.mode; }

reset() {
    rm -rf "$STATE" "$STUB_DIR/puts" "$STUB_DIR/received.jsonl" "$ARGV_LOG" "$MARKER" "$MANIFEST"
    mkdir -p "$STUB_DIR/puts"
    clear_modes
    unset TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY
}

configure_proxy() {
    TELEMETRY_INGEST_URL=$STUB_URL
    TELEMETRY_INGEST_KEY=proxy-injected
    export TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY
}

now_ms() { date +%s%N 2> /dev/null | cut -c1-13; }

write_marker() {
    started=$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=120)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
    printf 'cache=hit\nmethod=exact\nsession_id=sess-abc-123\nobserved_at=%s\n' "$started" > "$MARKER"
}

# --- 1. no URL: spool only, silently ----------------------------------------

echo "no URL configured: spool only"
reset
run event skill step-done step=3 outcome=ok duration_ms=420
expect_rc "event exits 0" 0
expect "event prints nothing" "" "$OUT"
expect "event spools one line" 1 "$(spool_lines)"
line=$(head -1 "$SPOOL")
expect "spool line is valid JSON" true "$(printf '%s' "$line" | jq -e . > /dev/null 2>&1 && echo true || echo false)"
expect "kind is first and is event" '{"kind":"event"' "$(printf '%s' "$line" | cut -c1-15)"
expect "source and name recorded" "skill step-done" "$(printf '%s' "$line" | jq -r '.source + " " + .name')"
expect "ts is UTC ISO 8601" true "$(printf '%s' "$line" | jq -r '.ts' | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' && echo true || echo false)"
expect "no marker -> _nosession" _nosession "$(printf '%s' "$line" | jq -r .session_id)"
expect "integers are numbers" number "$(printf '%s' "$line" | jq -r '.duration_ms | type')"
expect "strings stay strings" string "$(printf '%s' "$line" | jq -r '.outcome | type')"

run ship
expect_rc "ship with no URL exits 0" 0
expect "ship with no URL prints nothing" "" "$OUT"
expect "ship with no URL makes no request" 0 "$(requests)"
if [ ! -f "$ARGV_LOG" ]; then ok "ship with no URL does not even run curl"; else bad "curl ran with no URL configured"; fi
run upload-transcript "$STATE/spool.jsonl"
expect_rc "upload with no URL exits 0" 0
expect "upload with no URL prints nothing" "" "$OUT"

run status
expect_rc "status exits 0" 0
expect_out "status says spool only" "not configured (spool only)"
expect_out "status reports unsent bytes" "unsent"

# --- 2. the session marker ---------------------------------------------------

echo "session marker"
write_marker
run event phase start
expect "session_id comes from the marker" sess-abc-123 "$(tail -1 "$SPOOL" | jq -r .session_id)"

# --- 3. the allowlist and value hygiene --------------------------------------

echo "metadata allowlist"
reset
run event skill step secret=hunter2 prompt="write me a poem" outcome=ok
expect_rc "event with unlisted keys exits 0" 0
expect_out "an unlisted key is reported" "dropped key 'secret'"
expect_out "each unlisted key is reported" "dropped key 'prompt'"
line=$(head -1 "$SPOOL")
expect "unlisted key never reaches the spool" null "$(printf '%s' "$line" | jq -r '.secret')"
expect "second unlisted key never reaches the spool" null "$(printf '%s' "$line" | jq -r '.prompt')"
expect "listed key survives alongside" ok "$(printf '%s' "$line" | jq -r .outcome)"
case "$line" in *hunter2*) bad "an unlisted VALUE reached the spool" ;; *) ok "an unlisted value never reaches the spool" ;; esac

run event skill step 'outcome=a b;rm -rf /'
expect "unsafe characters in a value become _" 'a_b_rm_-rf_/' "$(tail -1 "$SPOOL" | jq -r .outcome)"
long=$(python3 -c 'print("x" * 500)')
run event skill step "outcome=$long"
expect "a value is capped at 120 characters" 120 "$(tail -1 "$SPOOL" | jq -r '.outcome | length')"
run event skill step 'outcome=line1
line2'
expect "a newline in a value cannot split the record" 1 "$(tail -1 "$SPOOL" | jq -s 'length')"
expect "the spool stays one line per record" 4 "$(spool_lines)"
run event skill step novalue
expect_out "an argument without = is ignored loudly" "want key=value"

echo "invalid arguments"
run event
expect_rc "event with no arguments is a usage error" 2
run event onlysource
expect_rc "event with no name is a usage error" 2
run event "Bad Source" name
expect_rc "a source that is not an identifier is a usage error" 2
run event skill "bad/name"
expect_rc "a name that is not an identifier is a usage error" 2
run record "Bad Kind" /dev/null
expect_rc "a bad record kind is a usage error" 2
run record transcript /dev/null
expect_rc "the transcript kind is reserved" 2
run ship --nonsense
expect_rc "an unknown ship flag is a usage error" 2
run frobnicate
expect_rc "an unknown subcommand is a usage error" 2
run
expect_rc "no subcommand is a usage error" 2

# --- 4. record ----------------------------------------------------------------

echo "record"
reset
printf 'status=ok\nref=main\nsha=abc123\n# a comment\n\nduration_seconds=88\ntimings=a=1s b=2s\n' > "$WORK/manifest.txt"
run record bootstrap "$WORK/manifest.txt"
expect_rc "record exits 0" 0
expect "a key=value file becomes one record" 1 "$(spool_lines)"
line=$(head -1 "$SPOOL")
expect "record kind is forced" bootstrap "$(printf '%s' "$line" | jq -r .kind)"
expect "fields carry the manifest" "ok main" "$(printf '%s' "$line" | jq -r '.fields.status + " " + .fields.ref')"
expect "a value containing = is kept whole" "a=1s b=2s" "$(printf '%s' "$line" | jq -r .fields.timings)"
printf '{"a":1}\n{"b":2,"kind":"forged"}\nnot json\n' > "$WORK/lines.jsonl"
run record notes "$WORK/lines.jsonl"
expect_rc "record of JSON lines exits 0" 0
expect "each JSON object becomes a record, bad lines are skipped" 3 "$(spool_lines)"
expect "an inner kind cannot override the forced one" notes "$(tail -1 "$SPOOL" | jq -r .kind)"
run record bootstrap "$WORK/does-not-exist"
expect_rc "record of a missing file exits 0" 0
expect_out "record of a missing file says so" "cannot read"
head -c 600000 /dev/zero | tr '\0' 'a' > "$WORK/big.txt"
run record bootstrap "$WORK/big.txt"
expect_rc "record of an oversized file exits 0" 0
expect_out "an oversized file is refused loudly" "over the"

# --- 5. event is fast ---------------------------------------------------------

echo "performance"
reset
t0=$(now_ms)
case "$t0" in
    "" | *[!0-9]*) ok "skipped: this date has no %N, so event timing is not measured here" ;;
    *)
        n=0
        while [ "$n" -lt 20 ]; do
            "$HELPER" event skill step step=1 outcome=ok > /dev/null 2>&1
            n=$((n + 1))
        done
        t1=$(now_ms)
        avg=$(((t1 - t0) / 20))
        if [ "$avg" -lt 100 ]; then ok "event averages ${avg}ms, under the 100ms budget"; else bad "event averages ${avg}ms, over the 100ms budget"; fi
        ;;
esac

# --- 6. never fails ------------------------------------------------------------

echo "never fails its caller"
OUT=$(AGENT_TELEMETRY_HOME=/proc/no/such/place "$HELPER" event skill step 2>&1) && RC=0 || RC=$?
printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
expect_rc "an unusable state directory still exits 0" 0
expect_out "an unusable state directory is one stderr line" "cannot create"

# --- 7. shipping: proxy-injected key -----------------------------------------

echo "ship, proxy-injected key"
reset
configure_proxy
write_marker
run event skill a step=1
run event skill b step=2
run record bootstrap "$WORK/manifest.txt"
size=$(spool_size)
run ship
expect_rc "ship exits 0" 0
expect "ship prints nothing" "" "$OUT"
expect "two kinds -> two POSTs" 2 "$(requests)"
expect "events go to /v1/records/event" /v1/records/event "$(sed -n 1p "$RECEIVED" | jq -r .path)"
expect "the manifest goes to /v1/records/bootstrap" /v1/records/bootstrap "$(sed -n 2p "$RECEIVED" | jq -r .path)"
expect "both event lines travel in one body" 2 "$(sed -n 1p "$RECEIVED" | jq -r .body | grep -c .)"
expect "the body is newline-delimited JSON" application/x-ndjson "$(sed -n 1p "$RECEIVED" | jq -r '.headers["content-type"]')"
expect "X-Session-Id is sent" sess-abc-123 "$(sed -n 1p "$RECEIVED" | jq -r '.headers["x-session-id"]')"
expect "NO auth header when the key is proxy-injected" null "$(sed -n 1p "$RECEIVED" | jq -r '.headers["authorization"]')"
expect "no fallback key header either" null "$(sed -n 1p "$RECEIVED" | jq -r '.headers["x-telemetry-key"]')"
expect "the offset advanced to the end of the spool" "$size" "$(offset)"
run ship
expect "shipping again after success sends nothing" 2 "$(requests)"
run status
expect_out "status says proxy-injected" "proxy"
expect_out "status shows the last ship" " 204 "

# --- 8. shipping: the key itself, never in argv -------------------------------

echo "ship, key in the request"
reset
TELEMETRY_INGEST_URL=$STUB_URL
TELEMETRY_INGEST_KEY=$KEY_SENTINEL
export TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY
run event skill a step=1
run ship
expect "a Bearer header carries the key" "Bearer $KEY_SENTINEL" "$(last_req '.headers["authorization"]')"
if [ -f "$ARGV_LOG" ] && grep -qF "$KEY_SENTINEL" "$ARGV_LOG"; then bad "the key appeared in curl's argv"; else ok "the key never appears in curl's argv"; fi
if [ -s "$ARGV_LOG" ]; then ok "the argv log is non-empty, so that check could have failed"; else bad "the argv log is empty; the argv check proves nothing"; fi
run status
expect_no_out "status never prints the key" "$KEY_SENTINEL"
expect_out "status says a key is in use" "key"

# Fall back to the key file when the environment names none.
reset
TELEMETRY_INGEST_URL=$STUB_URL
export TELEMETRY_INGEST_URL
unset TELEMETRY_INGEST_KEY
run event skill a step=1
run ship
expect "with no key anywhere nothing is shipped" 0 "$(requests)"
run status
expect_out "status says there is no credential" "none"
mkdir -p "$HOME/.config/claude/telemetry"
printf '%s\n' "$KEY_SENTINEL" > "$HOME/.config/claude/telemetry/key"
chmod 600 "$HOME/.config/claude/telemetry/key"
run ship
expect "a key file is used when no environment key is set" "Bearer $KEY_SENTINEL" "$(last_req '.headers["authorization"]')"
if grep -qF "$KEY_SENTINEL" "$ARGV_LOG"; then bad "the file key appeared in curl's argv"; else ok "the file key never appears in curl's argv"; fi
rm -rf "$HOME/.config"

# A URL from the url file, when the environment names none.
reset
unset TELEMETRY_INGEST_URL
TELEMETRY_INGEST_KEY=proxy-injected
export TELEMETRY_INGEST_KEY
mkdir -p "$HOME/.config/claude/telemetry"
printf '%s\n' "$STUB_URL" > "$HOME/.config/claude/telemetry/url"
run event skill a step=1
run ship
expect "the url file is honoured" 1 "$(requests)"
rm -rf "$HOME/.config"

# --- 9. the offset advances only on 2xx ---------------------------------------

echo "offset advance"
reset
configure_proxy
run event skill a step=1
set_mode records "500"
run ship
expect_rc "a 500 does not fail the caller" 0
expect "a 500 leaves the offset alone" 0 "$(offset)"
expect "...so the request was attempted" 1 "$(requests)"
set_mode records "502"
run ship
expect "a 502 leaves the offset alone" 0 "$(offset)"
set_mode records "204"
run ship
expect "the next ship resumes and advances" "$(spool_size)" "$(offset)"
run event skill b step=2
before=$(offset)
run ship
expect "only the new bytes are sent" 1 "$(body_lines)"
if [ "$(offset)" -gt "$before" ]; then ok "the offset moved past the new line"; else bad "the offset did not move"; fi

echo "401 and 400"
reset
configure_proxy
run event skill a step=1
set_mode records "401"
run ship
expect_rc "a 401 does not fail the caller" 0
expect_out "a 401 is one stderr line" "rejected the credential"
expect "a 401 leaves the offset alone" 0 "$(offset)"
if [ ! -f "$STATE/retry-until" ]; then ok "a 401 does not start a back-off"; else bad "a 401 started a back-off"; fi
set_mode records "400"
run ship
expect "a 400 drops the batch and moves on" "$(spool_size)" "$(offset)"
expect_out "a dropped batch is reported" "dropping"

# --- 10. Retry-After ----------------------------------------------------------

echo "Retry-After"
reset
configure_proxy
run event skill a step=1
set_mode records "429 retry-after=120"
run ship
expect_rc "a 429 does not fail the caller" 0
expect "a 429 leaves the offset alone" 0 "$(offset)"
if [ -f "$STATE/retry-until" ]; then ok "a 429 records a back-off"; else bad "a 429 recorded no back-off"; fi
until=$(head -1 "$STATE/retry-until")
now=$(date +%s)
if [ "$until" -ge $((now + 100)) ] && [ "$until" -le $((now + 130)) ]; then ok "the back-off honours Retry-After (about 120s)"; else bad "back-off is $((until - now))s, want about 120"; fi
set_mode records "204"
n=$(requests)
run ship
expect "while backing off nothing is sent, even to a healthy ingest" "$n" "$(requests)"
run status
expect_out "status says it is backing off" "backing off"
rm -f "$STATE/retry-until"
run ship
expect "after the back-off the spool ships" "$(spool_size)" "$(offset)"

reset
configure_proxy
run event skill a step=1
set_mode records "503 retry-after=30"
run ship
expect "a 503 leaves the offset alone" 0 "$(offset)"
if [ -f "$STATE/retry-until" ]; then ok "a 503 records a back-off"; else bad "a 503 recorded no back-off"; fi

# --- 11. network failure -------------------------------------------------------

echo "network error"
reset
TELEMETRY_INGEST_URL="http://127.0.0.1:1"
TELEMETRY_INGEST_KEY=proxy-injected
export TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY
run event skill a step=1
run ship
expect_rc "a network error does not fail the caller" 0
expect "a network error is silent" "" "$OUT"
expect "a network error leaves the offset alone" 0 "$(offset)"

# --- 12. a record still being written ------------------------------------------

echo "partial line"
reset
configure_proxy
run event skill a step=1
printf '{"kind":"event","ts":"x","partial":' >> "$SPOOL"
whole=$(head -1 "$SPOOL" | wc -c | tr -d ' ')
run ship
expect "the complete line is shipped" "$whole" "$(offset)"
expect "the half-written line is not" 1 "$(body_lines)"

# --- 13. transcript upload -----------------------------------------------------

echo "transcript upload"
reset
configure_proxy
write_marker
T="$WORK/transcript.jsonl"
printf '{"n":1}\n{"n":2}\n{"n":3}\n' > "$T"
run upload-transcript "$T"
expect_rc "upload exits 0" 0
expect "upload prints nothing" "" "$OUT"
expect "an upload request, then a PUT" "POST PUT" "$(jq -r '.method' "$RECEIVED" | tr '\n' ' ' | sed 's/ $//')"
expect "the upload request declares the size" "$(wc -c < "$T" | tr -d ' ')" "$(sed -n 1p "$RECEIVED" | jq -r '.body | fromjson | .size')"
expect "X-Session-Id is sent to /v1/uploads" sess-abc-123 "$(sed -n 1p "$RECEIVED" | jq -r '.headers["x-session-id"]')"
expect "no auth header when proxy-injected" null "$(sed -n 1p "$RECEIVED" | jq -r '.headers["authorization"]')"
expect "the PUT carries the signed headers" "1,$(wc -c < "$T" | tr -d ' ') 0" \
    "$(sed -n 2p "$RECEIVED" | jq -r '.headers["x-goog-content-length-range"] + " " + .headers["x-goog-if-generation-match"]')"
expect "the whole transcript was uploaded" "$(cat "$T")" "$(puts_cat)"
expect "the offset is recorded against the path" "$T" "$(head -1 "$STATE/transcript.offset")"
expect "the offset is the transcript size" "$(wc -c < "$T" | tr -d ' ')" "$(sed -n 2p "$STATE/transcript.offset")"
if grep -qF "$URL_SENTINEL" "$ARGV_LOG"; then bad "the signed URL appeared in curl's argv"; else ok "the signed URL never appears in curl's argv"; fi

n=$(requests)
run upload-transcript "$T"
expect "an unchanged transcript uploads nothing (idempotent)" "$n" "$(requests)"
expect "...and writes no second object" 1 "$(nputs)"

printf '{"n":4}\n{"n":5}\n' >> "$T"
run upload-transcript "$T"
expect "a grown transcript uploads only the tail" 2 "$(nputs)"
expect "reassembly is concatenation in name order" "$(cat "$T")" "$(puts_cat)"

printf '{"n":6' >> "$T"
n=$(requests)
run upload-transcript "$T"
expect "a half-written last line is withheld" "$n" "$(requests)"
printf '}\n' >> "$T"
run upload-transcript "$T"
expect "...and sent once complete, whole" "$(cat "$T")" "$(puts_cat)"

echo "transcript failures"
reset
configure_proxy
printf '{"n":1}\n' > "$T"
set_mode put "500"
run upload-transcript "$T"
expect_rc "a failed PUT does not fail the caller" 0
if [ ! -f "$STATE/transcript.offset" ]; then ok "a failed PUT does not advance the offset"; else bad "the offset advanced on a failed PUT"; fi
set_mode put "200"
run upload-transcript "$T"
expect "the retry uploads it" "$(cat "$T")" "$(puts_cat)"

set_mode uploads "429 retry-after=60"
printf '{"n":2}\n' >> "$T"
run upload-transcript "$T"
expect "a 429 on /v1/uploads leaves the offset alone" 1 "$(nputs)"
if [ -f "$STATE/retry-until" ]; then ok "...and starts a back-off"; else bad "no back-off after a 429"; fi
rm -f "$STATE/retry-until"
clear_modes

T2="$WORK/other-session.jsonl"
printf '{"other":1}\n' > "$T2"
run upload-transcript "$T2"
expect "a different transcript starts from zero, not the old offset" 2 "$(nputs)"
expect "...and uploads all of it" '{"other":1}' "$(puts_last)"

run upload-transcript "$WORK/missing.jsonl"
expect_rc "a missing transcript exits 0" 0
expect_out "a missing transcript is one stderr line" "cannot read"

echo "transcript, key in the request"
reset
TELEMETRY_INGEST_URL=$STUB_URL
TELEMETRY_INGEST_KEY=$KEY_SENTINEL
export TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY
printf '{"n":1}\n' > "$T"
run upload-transcript "$T"
expect "the key authorises /v1/uploads" "Bearer $KEY_SENTINEL" "$(sed -n 1p "$RECEIVED" | jq -r '.headers["authorization"]')"
expect "the signed PUT carries no key" null "$(sed -n 2p "$RECEIVED" | jq -r '.headers["authorization"]')"
if grep -qF "$KEY_SENTINEL" "$ARGV_LOG" || grep -qF "$URL_SENTINEL" "$ARGV_LOG"; then bad "a key or signed URL appeared in curl's argv"; else ok "neither key nor signed URL appears in curl's argv"; fi

# --- 14. session-end -----------------------------------------------------------

echo "session-end"
reset
configure_proxy
write_marker
printf 'status=degraded\ndegraded=gcloud terraform\nref=main\n' > "$MANIFEST"
run session-end repo=pmgledhill102/agentic-coding-config branch=feat/x issues=431 prs=632 secret=nope
expect_rc "session-end exits 0" 0
expect_out "session-end applies the allowlist" "dropped key 'secret'"
expect "a final ship happened" 1 "$(requests)"
expect "the record goes to /v1/records/session" /v1/records/session "$(last_req .path)"
rec=$(last_req .body)
expect "kind is session" session "$(printf '%s' "$rec" | jq -r .kind)"
expect "the cache verdict is read from the marker" hit "$(printf '%s' "$rec" | jq -r .cache)"
expect "degraded capabilities are read from the manifest" gcloud,terraform "$(printf '%s' "$rec" | jq -r .degraded)"
d=$(printf '%s' "$rec" | jq -r .duration_s)
if [ "$d" -ge 115 ] && [ "$d" -le 140 ]; then ok "duration is derived from the marker (about 120s)"; else bad "duration_s is '$d', want about 120"; fi
expect "caller pairs are kept" "pmgledhill102/agentic-coding-config feat/x 431 632" \
    "$(printf '%s' "$rec" | jq -r '[.repo, .branch, (.issues|tostring), (.prs|tostring)] | join(" ")')"

# --- 15. the Claude hook wrapper -----------------------------------------------

echo "hook wrapper"
reset
configure_proxy
write_marker
printf 'status=ok\nref=main\n' > "$MANIFEST"
OUT=$(printf '{"session_id":"sess-abc-123","source":"startup"}' | "$HOOK" session-start 2>&1) && RC=0 || RC=$?
printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
expect "session-start exits 0" 0 "$RC"
expect "session-start prints nothing (its stdout reaches the agent)" "" "$OUT"
i=0
while [ "$i" -lt 50 ] && [ "$(requests)" -lt 1 ]; do
    sleep 0.2
    i=$((i + 1))
done
expect "session-start records the marker and ships it" /v1/records/session-marker "$(sed -n 1p "$RECEIVED" | jq -r .path)"

reset
configure_proxy
printf '{"n":1}\n' > "$T"
payload=$(printf '{"session_id":"s","transcript_path":"%s"}' "$T")
OUT=$(printf '%s' "$payload" | "$HOOK" stop 2>&1) && RC=0 || RC=$?
printf '%s\n' "$OUT" >> "$ALL_OUTPUT"
expect "stop exits 0" 0 "$RC"
expect "stop prints nothing" "" "$OUT"
i=0
while [ "$i" -lt 50 ] && [ "$(nputs)" -lt 1 ]; do
    sleep 0.2
    i=$((i + 1))
done
expect "stop uploads the transcript tail" 1 "$(nputs)"
printf '{"n":2}\n' >> "$T"
printf '%s' "$payload" | "$HOOK" stop > /dev/null 2>&1
sleep 1
expect "a second stop inside the window does nothing" 1 "$(nputs)"
AGENT_TELEMETRY_STOP_EVERY=0 && export AGENT_TELEMETRY_STOP_EVERY
printf '%s' "$payload" | "$HOOK" stop > /dev/null 2>&1
i=0
while [ "$i" -lt 50 ] && [ "$(nputs)" -lt 2 ]; do
    sleep 0.2
    i=$((i + 1))
done
expect "...and runs again once the window has passed" 2 "$(nputs)"
unset AGENT_TELEMETRY_STOP_EVERY
OUT=$(printf '' | "$HOOK" stop 2>&1) && RC=0 || RC=$?
expect "stop with an empty payload exits 0" 0 "$RC"
OUT=$("$HOOK" nonsense < /dev/null 2>&1) && RC=0 || RC=$?
expect "an unknown hook event exits 0" 0 "$RC"

# --- the secret sweep -----------------------------------------------------------

echo "secret sweep"
if grep -qF "$KEY_SENTINEL" "$ALL_OUTPUT"; then bad "the key reached stdout or stderr"; else ok "the key never reached stdout or stderr"; fi
if grep -qF "$URL_SENTINEL" "$ALL_OUTPUT"; then bad "the signed URL reached stdout or stderr"; else ok "the signed URL never reached stdout or stderr"; fi
if [ -s "$ALL_OUTPUT" ]; then ok "the sweep covered real output"; else bad "the sweep had nothing to search"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
