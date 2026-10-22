#!/bin/sh
# Behavioural tests for home/bin/agent-shim, the watched-wait events in
# home/bin/agent-telemetry-claude-hook, and `agent-telemetry session-shape`
# (#625).
#
# What this protects, in order of cost if it breaks:
#
#   1. A SHIM NEVER CHANGES A TOOL'S BEHAVIOUR. Arguments, stdin, stdout,
#      stderr and the exit code are byte-for-byte what the bare tool gives,
#      including with the telemetry helper absent, broken, or unable to write.
#      A shim sits in front of every linter and of git; a bug here breaks
#      commits in every repo in the container.
#   2. A MISSING TOOL IS "NOT FOUND", NOT A LOOP. Even with a second route to
#      the shim directory on PATH.
#   3. THE OVERHEAD STAYS UNDER 10 MS a call, measured.
#   4. THE RECORDS ARE METADATA. A shim event carries duration, exit code, via
#      and blocked_ms, never an argument; via=git-hook is detected from a real
#      pre-commit hook.
#
# Usage: sh tests/agent-shim-test.sh
# Requires: git, jq. Exits non-zero if any case fails.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

PASS=0
FAIL=0

WORK=$(mktemp -d)
HOME="$WORK/home"
export HOME
unset AGENT_TELEMETRY_HOME AGENT_TELEMETRY_MARKER AGENT_TELEMETRY_MANIFEST \
    TELEMETRY_INGEST_URL TELEMETRY_INGEST_KEY CLAUDE_ENV_FILE
CB="$HOME/.claude/bin"
SHIMS="$CB/shims"
REAL="$WORK/real"
STATE="$HOME/.agents/telemetry"
SPOOL="$STATE/spool.jsonl"
MARKER="$HOME/.agents/.session-marker"
mkdir -p "$SHIMS" "$REAL" "$HOME/.agents" "$WORK/out"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

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

# The installed layout: the shim, a symlink per tool, the helper beside them.
install -m 0755 "$ROOT/home/bin/agent-shim" "$CB/agent-shim"
install -m 0755 "$ROOT/home/bin/agent-telemetry-claude-hook" "$CB/agent-telemetry-claude-hook"
ln -s "$ROOT/home/bin/agent-telemetry" "$CB/agent-telemetry"
for t in fake-tool quick absent-tool git; do ln -s ../agent-shim "$SHIMS/$t"; done

cat > "$REAL/fake-tool" << 'EOF'
#!/bin/sh
printf 'argc=%s\n' "$#"
for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
[ -z "${FAKE_STDIN:-}" ] || printf 'stdin=[%s]\n' "$(cat)"
echo "to-stderr" >&2
[ -z "${FAKE_SIG:-}" ] || kill "-$FAKE_SIG" $$
exit "${FAKE_RC:-0}"
EOF
printf '#!/bin/sh\nexit 0\n' > "$REAL/quick"
chmod 0755 "$REAL/fake-tool" "$REAL/quick"

BASE_PATH=$PATH
PATH="$SHIMS:$REAL:$BASE_PATH"
export PATH

# Waits (bounded) for the detached recorder to spool <n> shim events.
shim_events() { if [ -f "$SPOOL" ]; then jq -c 'select(.source == "shim")' "$SPOOL" | wc -l | tr -d ' '; else echo 0; fi; }
wait_events() {
    _i=0
    until [ "$(shim_events)" -ge "$1" ] || [ "$_i" -ge 50 ]; do
        sleep 0.1
        _i=$((_i + 1))
    done
}

# run_both <label> [env assignments are the caller's] -- runs fake-tool bare and
# through the shim with identical arguments and stdin, and compares everything.
compare() { # compare <label> <shim-path-for-tool> -- args...
    _label=$1
    _via=$2
    shift 2
    printf 'line one\nline two' | "$REAL/fake-tool" "$@" > "$WORK/out/d.out" 2> "$WORK/out/d.err"
    _drc=$?
    printf 'line one\nline two' | "$_via" "$@" > "$WORK/out/s.out" 2> "$WORK/out/s.err"
    _src=$?
    expect "$_label: exit code" "$_drc" "$_src"
    if cmp -s "$WORK/out/d.out" "$WORK/out/s.out"; then ok "$_label: stdout identical"; else bad "$_label: stdout differs" "$(diff "$WORK/out/d.out" "$WORK/out/s.out" | head -5)"; fi
    if cmp -s "$WORK/out/d.err" "$WORK/out/s.err"; then ok "$_label: stderr identical"; else bad "$_label: stderr differs" "$(diff "$WORK/out/d.err" "$WORK/out/s.err" | head -5)"; fi
}

NL='
'
ARG_SENTINEL='ARG-SENTINEL-must-not-be-recorded'

# --- 1. behaviour is preserved --------------------------------------------------

echo "preserved behaviour"
expect "the shim is what PATH finds" "$SHIMS/fake-tool" "$(command -v fake-tool)"
FAKE_STDIN=1 FAKE_RC=3 compare "args, stdin, rc 3" fake-tool "two words" "" "x${NL}y" '*' "$ARG_SENTINEL"
FAKE_STDIN=1 FAKE_RC=0 compare "rc 0" fake-tool --flag
# The bare run of this one makes the test's own shell print "Terminated" to
# the console; that line is not the shim's.
FAKE_SIG=TERM compare "a tool killed by a signal" fake-tool
wait_events 3

# --- 2. the record ----------------------------------------------------------------

echo "the record"
first=$(jq -c 'select(.source == "shim")' "$SPOOL" | head -1)
expect "one event per call" 3 "$(shim_events)"
expect "source and name" "shim fake-tool" "$(printf '%s' "$first" | jq -r '"\(.source) \(.name)"')"
expect "exit_code is the tool's" 3 "$(printf '%s' "$first" | jq -r .exit_code)"
expect "via is direct outside a hook" direct "$(printf '%s' "$first" | jq -r .via)"
expect "blocked_ms is present and 0" 0 "$(printf '%s' "$first" | jq -r .blocked_ms)"
expect "duration_ms is a number" number "$(printf '%s' "$first" | jq -r '.duration_ms | type')"
expect "exactly the documented keys" "blocked_ms duration_ms exit_code kind name session_id source ts via" \
    "$(printf '%s' "$first" | jq -r 'keys | join(" ")')"
if grep -q "dropped key" "$WORK/out/s.err"; then bad "a shim key is missing from the allowlist"; else ok "every shim key is allowlisted"; fi
if grep -qF "$ARG_SENTINEL" "$SPOOL"; then bad "an argument reached the spool"; else ok "no argument reaches the spool"; fi
if [ -f "$STATE/shims/first-use/fake-tool" ]; then ok "first use is stamped"; else bad "no first-use stamp"; fi

# --- 3. via=git-hook from a real pre-commit hook ----------------------------------

echo "git hook"
REPO="$WORK/repo"
mkdir -p "$REPO" "$WORK/hooks"
printf '#!/bin/sh\nfake-tool from-hook > /dev/null 2>&1\n' > "$WORK/hooks/pre-commit"
chmod 0755 "$WORK/hooks/pre-commit"
git -C "$REPO" init -q
before=$(shim_events)
GIT_CONFIG_GLOBAL=/dev/null git -C "$REPO" -c core.hooksPath="$WORK/hooks" -c user.name=t -c user.email=t@example.com \
    commit -q --allow-empty -m test
expect "git commit through the shim succeeds" 0 "$?"
wait_events $((before + 1))
expect "the hook's tool call is via=git-hook" git-hook "$(jq -r 'select(.source == "shim") | .via' "$SPOOL" | tail -1)"
i=0
until [ -f "$STATE/shims/first-commit" ] || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
if [ -f "$STATE/shims/first-commit" ]; then ok "the first commit is stamped"; else bad "no first-commit stamp"; fi
expect "git itself emits no event" 0 "$(jq -c 'select(.source == "shim" and .name == "git")' "$SPOOL" | wc -l | tr -d ' ')"

echo "git passthrough"
realgit=$(PATH=$BASE_PATH command -v git)
expect "git --version is unchanged" "$("$realgit" --version)" "$(git --version)"
"$realgit" -C "$REPO" rev-parse --verify no-such-ref > "$WORK/out/d.out" 2>&1
drc=$?
git -C "$REPO" rev-parse --verify no-such-ref > "$WORK/out/s.out" 2>&1
expect "a failing git command keeps its exit code" "$drc" "$?"
if cmp -s "$WORK/out/d.out" "$WORK/out/s.out"; then ok "and its output"; else bad "a failing git command's output differs"; fi
rm -f "$STATE/shims/first-commit"
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m nothing-staged > /dev/null 2>&1
sleep 0.3
if [ -f "$STATE/shims/first-commit" ]; then bad "a failed commit was stamped"; else ok "a failed commit is not stamped"; fi

# --- 4. missing tools -------------------------------------------------------------

echo "missing tool"
ln -s "$SHIMS" "$WORK/shims-alias"
OUT=$(PATH="$SHIMS:$WORK/shims-alias:$REAL:$BASE_PATH" timeout 5 absent-tool 2>&1)
rc=$?
expect "a missing tool exits 127, without looping through a second route to the shims" 127 "$rc"
expect "and says so" "absent-tool: command not found" "$OUT"

# --- 5. a broken telemetry path changes nothing -----------------------------------

echo "broken telemetry"
rm "$CB/agent-telemetry"
FAKE_STDIN=1 FAKE_RC=5 compare "helper absent" fake-tool a "b c"
printf '#!/bin/sh\necho BROKEN\necho BROKEN >&2\nexit 9\n' > "$CB/agent-telemetry"
chmod 0755 "$CB/agent-telemetry"
FAKE_STDIN=1 FAKE_RC=5 compare "helper broken" fake-tool a "b c"
FAKE_STDIN=1 FAKE_RC=5 AGENT_TELEMETRY_HOME=/proc/no/such/dir compare "state unwritable" fake-tool a
rm "$CB/agent-telemetry"
ln -s "$ROOT/home/bin/agent-telemetry" "$CB/agent-telemetry"

# --- 6. overhead ------------------------------------------------------------------

echo "overhead"
# Latency the caller waits, per call. Each shimmed call is allowed to finish
# recording before the next starts: back to back, the detached recorders of
# earlier calls compete for CPU with later ones, which measures the machine's
# core count rather than the shim.
now_ns() { date +%s%N; }
N=20
direct=0
i=0
while [ "$i" -lt "$N" ]; do
    t=$(now_ns); "$REAL/quick"; direct=$((direct + $(now_ns) - t))
    i=$((i + 1))
done
shimmed=0
i=0
before=$(shim_events)
while [ "$i" -lt "$N" ]; do
    t=$(now_ns); quick; shimmed=$((shimmed + $(now_ns) - t))
    i=$((i + 1))
    wait_events $((before + i))
done
expect "every timed call was recorded" $((before + N)) "$(shim_events)"
per=$(((shimmed - direct) / N / 1000))
echo "        overhead per call: ${per} us over $N calls"
if [ "$per" -lt 10000 ]; then ok "shim overhead is under 10 ms a call"; else bad "shim overhead is ${per} us a call, over 10 ms"; fi

# --- 7. hook events ---------------------------------------------------------------

echo "hook events"
OUT=$(printf '{"session_id":"s","prompt":"PROMPT-SENTINEL"}' | "$CB/agent-telemetry-claude-hook" prompt-submit 2>&1)
expect "prompt-submit exits 0" 0 "$?"
expect "prompt-submit prints nothing (its stdout joins the prompt)" "" "$OUT"
i=0
until grep -q '"name":"prompt-submit"' "$SPOOL" 2> /dev/null || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
expect "prompt-submit records hook prompt-submit" 1 "$(jq -c 'select(.source == "hook" and .name == "prompt-submit")' "$SPOOL" | wc -l | tr -d ' ')"
if grep -qF PROMPT-SENTINEL "$SPOOL"; then bad "the prompt reached the spool"; else ok "the prompt never reaches the spool"; fi

AGENT_TELEMETRY_STOP_EVERY=100000
export AGENT_TELEMETRY_STOP_EVERY
date +%s > "$STATE/stop.last"
OUT=$(printf '{"session_id":"s"}' | "$CB/agent-telemetry-claude-hook" stop 2>&1)
expect "stop prints nothing" "" "$OUT"
i=0
until grep -q '"name":"stop"' "$SPOOL" 2> /dev/null || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
expect "stop records hook stop even inside the ship throttle" 1 "$(jq -c 'select(.source == "hook" and .name == "stop")' "$SPOOL" | wc -l | tr -d ' ')"
unset AGENT_TELEMETRY_STOP_EVERY

echo "session-start"
CLAUDE_ENV_FILE="$WORK/env-file"
export CLAUDE_ENV_FILE
: > "$CLAUDE_ENV_FILE"
mkdir -p "$STATE/shims/first-use"
OUT=$(printf '{"session_id":"s","source":"startup"}' | "$CB/agent-telemetry-claude-hook" session-start 2>&1)
expect "session-start prints nothing" "" "$OUT"
if [ -d "$STATE/shims" ]; then bad "the previous session's shim state survived"; else ok "the previous session's shim state is cleared"; fi
got=$(PATH=/usr/bin:/bin sh -c '. "$1"; . "$1"; printf "%s" "$PATH"' _ "$CLAUDE_ENV_FILE")
expect "the env file puts the shims first, once, however often it is sourced" "$SHIMS:/usr/bin:/bin" "$got"
mv "$SHIMS" "$WORK/shims-moved"
: > "$CLAUDE_ENV_FILE"
printf '{}' | "$CB/agent-telemetry-claude-hook" session-start > /dev/null 2>&1
expect "no shims directory, no PATH line" "" "$(cat "$CLAUDE_ENV_FILE")"
mv "$WORK/shims-moved" "$SHIMS"
unset CLAUDE_ENV_FILE

# --- 8. session shape -------------------------------------------------------------

echo "session shape"
start=$(($(date +%s) - 100))
iso=$(date -u -d "@$start" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -r "$start" +%Y-%m-%dT%H:%M:%SZ)
printf 'cache=rebuild\nsession_id=sess-1\nsession_source=resume\nobserved_at=%s\nbootstrap_duration_seconds=80\nsha=abc123\n' "$iso" > "$MARKER"
mkdir -p "$STATE/shims/first-use"
echo $((start + 12)) > "$STATE/shims/first-use/semgrep"
echo $((start + 5)) > "$STATE/shims/first-use/cspell"
echo $((start - 50)) > "$STATE/shims/first-use/stale"
echo $((start + 30)) > "$STATE/shims/first-commit"
OUT=$("$CB/agent-telemetry" session-shape 2>&1)
expect "session-shape is silent" "" "$OUT"
rec=$(jq -c 'select(.source == "session" and .name == "shape")' "$SPOOL" | tail -1)
expect "the shape carries the marker's fields" "rebuild resume abc123 80" \
    "$(printf '%s' "$rec" | jq -r '"\(.cache) \(.session_source) \(.sha) \(.bootstrap_duration_seconds)"')"
expect "first_commit_s is relative to session start" 30 "$(printf '%s' "$rec" | jq -r .first_commit_s)"
expect "first_use_s is in order of use, and ignores an earlier session's stamp" "cspell:5,semgrep:12" \
    "$(printf '%s' "$rec" | jq -r .first_use_s)"
rm -rf "$STATE/shims"
"$CB/agent-telemetry" session-shape > /dev/null 2>&1
rec=$(jq -c 'select(.source == "session" and .name == "shape")' "$SPOOL" | tail -1)
expect "with no commit and no tool use, both are absent" "null null" \
    "$(printf '%s' "$rec" | jq -r '"\(.first_commit_s) \(.first_use_s)"')"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
