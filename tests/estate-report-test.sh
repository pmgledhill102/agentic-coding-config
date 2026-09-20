#!/bin/sh
# estate-report-test — the flag thresholds and the aggregation, without network.
#
# WHY THIS EXISTS. estate-report's whole claim over skill prose is that its
# arithmetic is exact and repeatable. That claim is worth nothing unchecked:
# a wrong threshold produces a plausible table, and a plausible table is what
# someone picks a day's work from.
#
# WHY IT EXTRACTS THE FILTERS RATHER THAN COPYING THEM. A fixture test holding
# its own copy of row.jq tests the copy. Both would have to be edited together,
# nothing would enforce it, and the test would go green against logic that no
# longer ships. So the filters are pulled out of the script itself at run time.
#
# Usage: sh tests/estate-report-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/home/bin/estate-report"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

PASS=0
FAIL=0

command -v jq > /dev/null 2>&1 || { echo "estate-report-test: needs jq" >&2; exit 1; }
[ -f "$SCRIPT" ] || { echo "estate-report-test: $SCRIPT missing" >&2; exit 1; }

# Pull a heredoc'd jq filter out of the shipped script.
extract() {
    awk -v m="$1.jq\" <<" 'index($0, m) { f = 1; next } f && /^JQ$/ { f = 0 } f { print }' \
        "$SCRIPT"
}

extract row    > "$WORK/row.jq"
extract render > "$WORK/render.jq"

for f in row render; do
    [ -s "$WORK/$f.jq" ] || {
        echo "FAIL: could not extract $f.jq from the script — has its heredoc marker changed?"
        exit 1
    }
done

check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1"
        echo "  expected: $2"
        echo "  actual:   $3"
    fi
}

# --- row.jq: aggregation ---------------------------------------------------
# A response carrying both issues and PRs, which is what REST /issues returns.
cat > "$WORK/meta.json" <<'JSON'
{"pushed_at": "2020-01-01T00:00:00Z"}
JSON

cat > "$WORK/mixed.json" <<'JSON'
[
 {"number":1,"title":"crit","labels":[{"name":"P0"}],"created_at":"2020-01-01T00:00:00Z"},
 {"number":2,"title":"high","labels":[{"name":"P1"},{"name":"type: bug"}],"created_at":"2020-01-01T00:00:00Z"},
 {"number":3,"title":"mid","labels":[{"name":"P2"}],"created_at":"2020-01-01T00:00:00Z"},
 {"number":4,"title":"low","labels":[{"name":"P4"}],"created_at":"2020-01-01T00:00:00Z"},
 {"number":5,"title":"bare","labels":[],"created_at":"2020-01-01T00:00:00Z"},
 {"number":6,"title":"typed-only","labels":[{"name":"type: task"}],"created_at":"2020-01-01T00:00:00Z"},
 {"number":7,"title":"human pr","labels":[],"created_at":"2020-01-01T00:00:00Z",
  "pull_request":{},"user":{"login":"pmgledhill102"}},
 {"number":8,"title":"bot pr","labels":[],"created_at":"2020-01-01T00:00:00Z",
  "pull_request":{},"user":{"login":"dependabot[bot]"}}
]
JSON

ROW=$(jq -c --arg repo demo --slurpfile meta "$WORK/meta.json" -f "$WORK/row.jq" "$WORK/mixed.json")

check "PRs excluded from open count"   "6" "$(echo "$ROW" | jq '.open')"
check "P0 counted"                     "1" "$(echo "$ROW" | jq '.p0')"
check "P1 counted"                     "1" "$(echo "$ROW" | jq '.p1')"
check "P2-P4 bucketed together"        "2" "$(echo "$ROW" | jq '.p24')"
check "type: label is not a priority"  "2" "$(echo "$ROW" | jq '.untriaged')"
check "human PR counted"               "1" "$(echo "$ROW" | jq '.human')"
check "bot PR counted"                 "1" "$(echo "$ROW" | jq '.bot')"
check "exceptions carry P0 and P1"     "2" "$(echo "$ROW" | jq '.exceptions | length')"
check "exceptions carry the title"     '"crit"' \
      "$(echo "$ROW" | jq '.exceptions[0].t')"

# Every bucket must account for every issue, or the table silently loses work.
SUM=$(echo "$ROW" | jq '.p0 + .p1 + .p24 + .untriaged')
check "buckets are exhaustive"         "$(echo "$ROW" | jq '.open')" "$SUM"

# --- render.jq: flag thresholds --------------------------------------------
# Defaults are a healthy repo; each case overrides only what it is testing.
flag_for() { # flag_for <json overrides> -- the derived flag
    echo "$1" | jq -c '
      {repo:"r", open:10, p0:0, p1:0, p24:10, untriaged:0,
       human:0, bot:0, oldest_human:0, oldest_bot:0, push_age:1,
       exceptions:[]} * .' \
    | jq -s -r --arg now t --arg scoped no -f "$WORK/render.jq" \
    | sed -n 's/^r  *[0-9].*  \([a-zA-Z0-9]*\)$/\1/p'
}

check "P0 present"          "P0"         "$(flag_for '{"p0":1,"exceptions":[]}')"
check "human PR over 7d"    "blocked"    "$(flag_for '{"human":1,"oldest_human":9}')"
check "human PR under 7d"   ""           "$(flag_for '{"human":1,"oldest_human":3}')"
check "bot backlog"         "automation" "$(flag_for '{"bot":6,"oldest_bot":20}')"
check "bot churn is normal" ""           "$(flag_for '{"bot":2,"oldest_bot":20}')"
check "fresh bot backlog"   ""           "$(flag_for '{"bot":6,"oldest_bot":3}')"
check "P1 and no pushes"    "stalled"    "$(flag_for '{"p1":1,"push_age":40}')"
check "P1 but active"       ""           "$(flag_for '{"p1":1,"push_age":2}')"
check "untriaged over 5"    "untriaged"  "$(flag_for '{"untriaged":6}')"
check "untriaged exactly 5" ""           "$(flag_for '{"untriaged":5}')"

# Precedence: a repo tripping several thresholds reports the most severe only.
check "P0 outranks the rest" "P0" \
      "$(flag_for '{"p0":1,"human":1,"oldest_human":9,"bot":6,"oldest_bot":20,"untriaged":9}')"
check "blocked outranks automation" "blocked" \
      "$(flag_for '{"human":1,"oldest_human":9,"bot":6,"oldest_bot":20}')"

# An active repo with a large but worked backlog must stay unflagged. This is
# the case the whole design rests on: volume alone never raises an alarm.
check "big active backlog is unflagged" "" \
      "$(flag_for '{"open":80,"p1":2,"p24":73,"untriaged":5,"push_age":0}')"

# --- quiet repos are collapsed, not listed as rows --------------------------
QUIET=$(echo '{"repo":"sleepy", "open":0, "p0":0, "p1":0, "p24":0, "untriaged":0,
               "human":0, "bot":0, "oldest_human":0, "oldest_bot":0,
               "push_age":300, "exceptions":[]}' \
        | jq -s -r --arg now t --arg scoped no -f "$WORK/render.jq")
check "quiet repo is collapsed" "1" "$(echo "$QUIET" | grep -c '^quiet (1): sleepy$')"
check "quiet repo has no row"   "0" "$(echo "$QUIET" | grep -c '^sleepy  ')"

# --- enumeration, owner filter and exclusions (stubbed curl) ---------------
# The jq checks above cover the arithmetic. This block covers the shell half --
# which repos are fetched at all -- by putting a fake `curl` on PATH. That is
# the same stubbing approach tests/stub-broker.py takes for the credential
# client, and it closes the gap the script shipped with: enumeration had never
# run under test, only the aggregation downstream of it.

mkdir -p "$WORK/bin" "$WORK/fix"

cat > "$WORK/fix/repos.json" <<'JSON'
[
 {"name":"alpha",          "archived":false, "owner":{"login":"testowner"}},
 {"name":"lifeos",         "archived":false, "owner":{"login":"testowner"}},
 {"name":"lifeos-sandbox", "archived":false, "owner":{"login":"testowner"}},
 {"name":"beta",           "archived":false, "owner":{"login":"testowner"}},
 {"name":"oldthing",       "archived":true,  "owner":{"login":"testowner"}},
 {"name":"someoneelses",   "archived":false, "owner":{"login":"otherorg"}}
]
JSON

cat > "$WORK/fix/meta.json" <<'JSON'
{"pushed_at": "2020-01-01T00:00:00Z"}
JSON

cat > "$WORK/fix/issues.json" <<'JSON'
[{"number":1,"title":"a task","labels":[{"name":"P2"}],"created_at":"2020-01-01T00:00:00Z"}]
JSON

cat > "$WORK/bin/curl" <<'STUB'
#!/bin/sh
# Stand-in for curl: honours -o <file> and -w, ignores the rest, always 200.
out=/dev/null
url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -H|-w|--max-time) shift ;;
        https://*) url="$1" ;;
        *) ;;
    esac
    shift
done
case "$url" in
    */user/repos*) cat "$FIXTURES/repos.json"  > "$out" ;;
    */issues*)     cat "$FIXTURES/issues.json" > "$out" ;;
    *)             cat "$FIXTURES/meta.json"   > "$out" ;;
esac
echo 200
STUB
chmod +x "$WORK/bin/curl"

run_stubbed() { # run_stubbed [args...] -- estate-report against the fixtures
    FIXTURES="$WORK/fix" PATH="$WORK/bin:$PATH" GH_TOKEN=stub \
        sh "$SCRIPT" --owner testowner "$@" 2>&1
}

OUT=$(run_stubbed)

check "excluded repos are not rows"   "0" "$(echo "$OUT" | grep -c '^lifeos')"
check "the exclusions are reported"   "1" \
      "$(echo "$OUT" | grep -c '^excluded (2): lifeos, lifeos-sandbox$')"
check "non-excluded repos survive"    "1" "$(echo "$OUT" | grep -c '^alpha ')"
check "archived repos are dropped"    "0" "$(echo "$OUT" | grep -c '^oldthing')"
check "other owners are dropped"      "0" "$(echo "$OUT" | grep -c '^someoneelses')"

# A stale name in the list must not be reported as though it excluded a repo
# that was never there -- otherwise the count drifts from reality silently.
OUT=$(run_stubbed --exclude beta,doesnotexist)
check "--exclude extends the default" "0" "$(echo "$OUT" | grep -c '^beta ')"
check "absent names are not counted"  "1" \
      "$(echo "$OUT" | grep -c '^excluded (3): lifeos, lifeos-sandbox, beta$')"

# --repos is an explicit instruction and outranks the exclusion list.
OUT=$(run_stubbed --repos lifeos)
check "--repos overrides exclusions"  "1" "$(echo "$OUT" | grep -c '^lifeos ')"
check "nothing excluded via --repos"  "0" "$(echo "$OUT" | grep -c '^excluded')"

# The JSON form has to carry the exclusions too, or a later renderer rebuilds
# the blind spot the table was given the line to avoid.
JOUT=$(run_stubbed --json)
check "json carries excluded names"   '["lifeos","lifeos-sandbox"]' \
      "$(echo "$JOUT" | jq -c '.excluded')"
check "json omits excluded repos"     "0" \
      "$(echo "$JOUT" | jq '[.repos[] | select(.repo | startswith("lifeos"))] | length')"

# --- scoped versus whole-estate runs ---------------------------------------
# A scoped run is a supported mode: a cloud session bound to four or five
# deliberately attached repos gives a real report over them. The danger is not
# that it runs, it is that its table used to render identically to a
# whole-estate one -- so a report omitting thirty-five repos looked exactly
# like one omitting none, with nothing in it appearing wrong.

OUT=$(run_stubbed)
check "enumerated runs are not scoped" "0" "$(echo "$OUT" | grep -c 'SCOPED')"

OUT=$(run_stubbed --repos alpha,beta)
check "--repos labels itself scoped"   "1" \
      "$(echo "$OUT" | head -1 | grep -c '(SCOPED: --repos, not the whole estate)$')"

check "json marks an enumerated run"   "false" \
      "$(run_stubbed --json | jq -c '.scoped')"
check "json marks a scoped run"        "true" \
      "$(run_stubbed --repos alpha --json | jq -c '.scoped')"

# --- the session-binding refusal -------------------------------------------
# An agent sandbox refuses /user/repos upstream of the credential. Blaming the
# token sends the reader after a better PAT that cannot exist at any scope, so
# the message has to name the binding. This is the exact body the proxy returns.
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/sh
out=/dev/null
url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -H|-w|--max-time) shift ;;
        https://*) url="$1" ;;
        *) ;;
    esac
    shift
done
case "$url" in
    */user/repos*)
        printf '%s' '{"message":"This GitHub API path is not available: sessions are bound to their configured repositories. Use repository-scoped endpoints (repos/{owner}/{repo}/...)."}' > "$out"
        echo 403 ;;
    *) cat "$FIXTURES/meta.json" > "$out"; echo 200 ;;
esac
STUB
chmod +x "$WORK/bin/curl"

OUT=$(run_stubbed); RC=$?

check "binding refusal exits 2"        "2"   "$RC"
check "it names the session binding"   "1" \
      "$(echo "$OUT" | grep -c 'bound to its configured repositories')"
check "it does not blame the token"    "1" \
      "$(echo "$OUT" | grep -c 'not the token')"
check "it offers the scoped route"     "1"   "$(echo "$OUT" | grep -c '\-\-repos a,b,c')"
check "it offers the workstation"      "1"   "$(echo "$OUT" | grep -c 'run on a workstation')"

# --- summary ---------------------------------------------------------------
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "estate-report: $FAIL of $((PASS + FAIL)) checks failed"
    exit 1
fi
echo "estate-report: all $PASS checks pass"
