#!/bin/sh
# Behaviour tests for home/bin/session-cache-verdict.
#
# The script answers one question — did this session rebuild its environment or
# restore a cached snapshot — and the answer is used to decide whether deferring
# a tool install buys anything (#430, #323). A wrong answer is worse than none,
# because it would be acted on.
#
# Two properties carry the weight, and each has a negative control here:
#
#   1. The EXACT method must beat the heuristic whenever the bootstrap recorded
#      a session id, since clock arithmetic is ambiguous and an id is not.
#   2. Every failure mode must exit 0 and leave the session alone. This runs as
#      a SessionStart hook; a non-zero exit or a hang is a session that will not
#      start, which is a far worse outcome than an unmeasured one.
#
# Usage: sh tests/session-cache-verdict-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/home/bin/session-cache-verdict"

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }

# eq <label> <actual> <expected>. An `if` rather than `A && B || C`, which is
# not if-then-else: when the ok branch fails, the no branch runs as well.
eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi
}

# truthy <label> <value> -- asserts non-empty.
truthy() {
    if [ -n "$2" ]; then ok "$1"; else no "$1 (empty)"; fi
}

# absent <label> <path> -- asserts the path does not exist.
absent() {
    if [ ! -e "$2" ]; then ok "$1"; else no "$1 ($2 exists)"; fi
}

# run <home> <payload-json> -- run the script with HOME pointed at a fixture,
# echoing the exit code. The script promises 0 in every case.
run() {
    _home="$1"
    printf '%s' "${2:-}" | env HOME="$_home" sh "$SCRIPT" > "$WORK/out" 2>&1
    echo $?
}

marker_field() { sed -n "s/^$2=//p" "$1/.agents/.session-marker" 2> /dev/null; }

# fixture <name> <installed_at> <built_in_session> -- a HOME with a manifest.
fixture() {
    _h="$WORK/$1"
    mkdir -p "$_h/.agents"
    {
        echo "status=ok"
        echo "ref=main"
        echo "sha=abc123"
        echo "installed_at=$2"
        echo "duration_seconds=68"
        if [ -n "${3:-}" ]; then echo "built_in_session=$3"; fi
    } > "$_h/.agents/.bootstrap-manifest"
    echo "$_h"
}

# iso_ago <seconds> -- an ISO timestamp that many seconds in the past.
# GNU first, BSD second, the estate's usual pattern for date.
iso_ago() {
    _n=$(date -u +%s)
    _t=$((_n - $1))
    date -u -d "@$_t" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null ||
        date -u -r "$_t" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null
}

echo "--- exact method: the bootstrap recorded which session it built for ---"

H=$(fixture exact-rebuild "$(iso_ago 60)" "session_AAA")
rc=$(run "$H" '{"session_id":"session_AAA","source":"startup"}')
eq "exit 0" "$rc" 0
eq "same session id -> rebuild" "$(marker_field "$H" cache)" rebuild
eq "reports method=exact" "$(marker_field "$H" method)" exact

H=$(fixture exact-hit "$(iso_ago 60)" "session_AAA")
run "$H" '{"session_id":"session_BBB","source":"startup"}' > /dev/null
eq "different session id -> hit" "$(marker_field "$H" cache)" hit

# The case that motivates the exact method existing at all. A session starting a
# minute after another rebuilt the cache restores a snapshot whose install is a
# minute old -- which the clock must call a rebuild and the id must not.
H=$(fixture exact-beats-clock "$(iso_ago 30)" "session_AAA")
run "$H" '{"session_id":"session_BBB","source":"startup"}' > /dev/null
eq "fresh install, foreign session -> hit, not rebuild" \
    "$(marker_field "$H" cache)" hit

echo "--- heuristic fallback: no session id was available at build time ---"

H=$(fixture heur-rebuild "$(iso_ago 45)" "unknown")
run "$H" '{"session_id":"session_AAA","source":"startup"}' > /dev/null
eq "recent install -> rebuild" "$(marker_field "$H" cache)" rebuild
eq "reports method=heuristic, so a reader can discount it" \
    "$(marker_field "$H" method)" heuristic

H=$(fixture heur-hit "$(iso_ago 86400)" "unknown")
run "$H" '{"session_id":"session_AAA","source":"startup"}' > /dev/null
eq "day-old install -> hit" "$(marker_field "$H" cache)" hit

echo "--- the marker is written once per session ---"

# A resume fires SessionStart again. Recomputing then would compare a days-old
# install against a fresh clock and turn a rebuild into a hit, so the first
# observation has to stand. The manifest is rewritten between the two runs to
# prove the second run did not recompute rather than merely agreeing.
H=$(fixture resume "$(iso_ago 30)" "session_AAA")
run "$H" '{"session_id":"session_AAA","source":"startup"}' > /dev/null
first=$(marker_field "$H" observed_at)
sed 's/^installed_at=.*/installed_at=2020-01-01T00:00:00Z/' \
    "$H/.agents/.bootstrap-manifest" > "$WORK/m.tmp"
mv "$WORK/m.tmp" "$H/.agents/.bootstrap-manifest"
run "$H" '{"session_id":"session_AAA","source":"resume"}' > /dev/null
eq "resume does not overwrite the first verdict" \
    "$(marker_field "$H" cache)" rebuild
eq "observed_at is the first observation" \
    "$(marker_field "$H" observed_at)" "$first"

echo "--- evidence is recorded, not just the verdict ---"

H=$(fixture evidence "$(iso_ago 60)" "session_AAA")
run "$H" '{"session_id":"session_AAA","source":"startup"}' > /dev/null
truthy "records the age it judged on" "$(marker_field "$H" bootstrap_age_seconds)"
eq "carries the bootstrap duration through" \
    "$(marker_field "$H" bootstrap_duration_seconds)" 68
eq "carries the ref" "$(marker_field "$H" ref)" main
eq "records the session source" "$(marker_field "$H" session_source)" startup

echo "--- never the reason a session fails to start ---"

# A workstation: no manifest. Must leave without writing anything, and without
# needing jq -- which is why the manifest check comes before any parsing.
H="$WORK/workstation"
mkdir -p "$H"
rc=$(run "$H" '{"session_id":"session_AAA"}')
eq "no manifest -> exit 0" "$rc" 0
absent "no manifest -> writes no marker" "$H/.agents/.session-marker"

H=$(fixture no-payload "$(iso_ago 60)" "session_AAA")
rc=$(run "$H" '')
eq "empty stdin -> exit 0" "$rc" 0

H=$(fixture bad-json "$(iso_ago 60)" "session_AAA")
rc=$(run "$H" 'not json at all')
eq "malformed payload -> exit 0" "$rc" 0

H=$(fixture bad-date "not-a-timestamp" "unknown")
rc=$(run "$H" '{"session_id":"session_AAA"}')
eq "unparseable install time -> exit 0" "$rc" 0
eq "unparseable install time -> cache=unknown, not a guess" \
    "$(marker_field "$H" cache)" unknown

echo "--- prints nothing: a SessionStart hook's stdout reaches the context ---"

H=$(fixture quiet "$(iso_ago 60)" "session_AAA")
run "$H" '{"session_id":"session_AAA","source":"startup"}' > /dev/null
if [ -s "$WORK/out" ]; then
    no "no output on the happy path (got: $(cat "$WORK/out"))"
else
    ok "no output on the happy path"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
