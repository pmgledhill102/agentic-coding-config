#!/bin/sh
# Behaviour tests for home/bin/env-conformance and home/conformance/matrix.conf.
#
# The suite exists to catch the platform moving, and a check that reports a
# confident wrong answer is worse than none: a false FAIL invites someone to rip
# out a working mechanism, a false pass hides the drift it was written for.
# So every status is driven here from a stub whose answer is known:
#
#   pass / FAIL / unproven / unknown / not-applicable / invalid, and each exit
#   code, through stubbed curl and gh on PATH -- offline, no token
#
# Three properties carry the weight:
#
#   1. A pass needs a control that observed something else. The unproven case
#      is the negative control for that rule.
#   2. A FAIL names what it invalidates.
#   3. The runner writes nothing, to HOME or cwd, and never prints the value
#      of a variable it checks -- the one it exists for holds a bearer token.
#
# The real matrix is also validated: every stanza complete, every control
# through its probe's own function, no id twice.
#
# Usage: sh tests/env-conformance-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/home/bin/env-conformance"
REAL_MATRIX="$ROOT/home/conformance/matrix.conf"

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }

eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi
}

has() { # has <label> <needle> -- in $WORK/out
    if grep -qF -- "$2" "$WORK/out"; then ok "$1"; else no "$1 (no '$2' in output)"; sed 's/^/      | /' "$WORK/out"; fi
}

lacks() {
    if grep -qF -- "$2" "$WORK/out"; then no "$1 ('$2' present)"; sed 's/^/      | /' "$WORK/out"; else ok "$1"; fi
}

# --- stubs --------------------------------------------------------------------
#
# curl answers from $STUB/curl.map: "<url> <http_code> <http_connect>". An
# unmapped URL behaves like no network: 000 000 and a non-zero exit.
# gh answers from $STUB/gh.map: "<endpoint> ok|<status>"; unmapped = no
# network, an error with no HTTP status in it.

STUB="$WORK/stub"
mkdir -p "$STUB/bin"

cat > "$STUB/bin/curl" << 'EOF'
#!/bin/sh
for a in "$@"; do url=$a; done
line=$(grep -F -- "$url " "$STUB/curl.map" 2> /dev/null | head -1)
if [ -z "$line" ]; then printf '000 000'; exit 7; fi
set -- $line
printf '%s %s' "$2" "$3"
EOF

cat > "$STUB/bin/gh" << 'EOF'
#!/bin/sh
[ "$1" = api ] || exit 2
line=$(grep -F -- "$2 " "$STUB/gh.map" 2> /dev/null | head -1)
[ -n "$line" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
set -- $line
[ "$2" = ok ] && { echo 1; exit 0; }
echo "gh: stubbed refusal (HTTP $2)" >&2
exit 1
EOF

cat > "$STUB/bin/conformance-fake-tool" << 'EOF'
#!/bin/sh
EOF
chmod +x "$STUB/bin/"*

: > "$STUB/curl.map"
: > "$STUB/gh.map"

FHOME="$WORK/home"
mkdir -p "$FHOME"

# run <matrix> [args...] -- runner with stubs first on PATH, fixture HOME and
# surface; output to $WORK/out, exit code echoed.
run() {
    _m=$1
    shift
    (cd "$WORK" && env PATH="$STUB/bin:$PATH" STUB="$STUB" HOME="$FHOME" \
        CONFORMANCE_SURFACE=test CONFORMANCE_TIMEOUT=2 \
        sh "$SCRIPT" --matrix "$_m" "$@") > "$WORK/out" 2>&1
    echo $?
}

# entry <id> <mode> <probe> <expect> <control> [surface] -- one stanza.
entry() {
    printf '[%s]\nmode=%s\nsurface=%s\nprobe=%s\nexpect=%s\ncontrol=%s\n' \
        "$1" "$2" "${6:-test}" "$3" "$4" "$5"
    printf 'measured=2026-10-20\nclaim=claim for %s\ndepends=DEPENDANT-%s\n\n' "$1" "$1"
}

M="$WORK/m.conf"

# --- egress: pass, FAIL, unproven, unknown ------------------------------------

printf '%s\n' 'https://up.test/ 200 000' 'https://refused.test/ 000 403' > "$STUB/curl.map"

entry egress-up fast 'egress https://up.test/' reached 'egress https://refused.test/' > "$M"
rc=$(run "$M")
eq "pass: reached host with a refused control exits 0" "$rc" 0
has "pass: reported as pass" "pass     egress-up"
has "pass: control observation shown" "control=blocked"

entry egress-down fast 'egress https://refused.test/' reached 'egress https://up.test/' > "$M"
rc=$(run "$M")
eq "FAIL: a refused host expected reachable exits 1" "$rc" 1
has "FAIL: reported as FAIL with both values" "observed=blocked expected=reached"
has "FAIL: names what it invalidates" "invalidates: DEPENDANT-egress-down"
has "FAIL: says when it last held" "last measured 2026-10-20"
rc=$(run "$M" --brief)
eq "FAIL --brief: exit 1" "$rc" 1
has "FAIL --brief: state=mismatch" "state=mismatch"
has "FAIL --brief: dependants still printed" "invalidates: DEPENDANT-egress-down"

# The control matching the expectation is the negative control for "pass
# means something": the same observation with a control that cannot fail.
entry egress-blind fast 'egress https://up.test/' reached 'egress https://up.test/' > "$M"
rc=$(run "$M")
eq "unproven: control that also matches exits 2" "$rc" 2
has "unproven: reported, never as pass" "unproven egress-blind"
lacks "unproven: no pass line" "pass     egress-blind"

entry egress-nonet fast 'egress https://unmapped.test/' reached 'egress https://refused.test/' > "$M"
rc=$(run "$M" --brief)
eq "unknown: no network is exit 0, not a failure" "$rc" 0
has "unknown: all-unknown run is state=unknown, not ok" "state=unknown"
has "unknown: reported per entry" "unknown  egress-nonet"

# A control that could not run proves nothing either.
entry egress-ctl-nonet fast 'egress https://up.test/' reached 'egress https://unmapped.test/' > "$M"
rc=$(run "$M")
eq "unproven: unknown control exits 2" "$rc" 2

# --- gh lanes -----------------------------------------------------------------

printf '%s\n' 'graphql 403' 'repos/o/allowed ok' 'repos/o/hidden 403' 'repos/o/gone 404' > "$STUB/gh.map"
{
    entry gql fast 'gh_lane graphql' blocked 'gh_lane rest o/allowed'
    entry rest fast 'gh_lane rest o/allowed' ok 'gh_lane rest o/gone'
} > "$M"
rc=$(run "$M" --brief)
eq "gh: graphql 403 reads blocked, REST ok reads ok" "$rc" 0
has "gh: both pass" "pass=2 fail=0"

entry rest-hidden fast 'gh_lane rest o/hidden' ok 'gh_lane rest o/gone' > "$M"
rc=$(run "$M")
eq "gh: a 403 on REST is a FAIL" "$rc" 1
has "gh: observed blocked" "observed=blocked expected=ok"

entry rest-nonet fast 'gh_lane rest o/unmapped' ok 'gh_lane rest o/gone' > "$M"
rc=$(run "$M" --brief)
eq "gh: an error with no HTTP status is unknown" "$rc" 0
has "gh: state=unknown" "state=unknown"

# --- local probes -------------------------------------------------------------

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$WORK/os-release"
{
    entry os fast "os $WORK/os-release" ubuntu-24.04 'os /dev/null'
    entry tool-there fast 'tool conformance-fake-tool' present 'tool conformance-no-such-tool'
    entry tool-gone fast 'tool conformance-no-such-tool' absent 'tool conformance-fake-tool'
} > "$M"
rc=$(run "$M" --brief)
eq "local: os and tool probes pass" "$rc" 0
has "local: three passes" "pass=3 fail=0"

# The variable checked is printed by name only. The sentinel is what would
# leak if the probe ever echoed a value.
entry tok fast 'env_set CONFORMANCE_TEST_TOKEN' set 'env_set CONFORMANCE_NO_SUCH_VAR' > "$M"
rc=$(CONFORMANCE_TEST_TOKEN=sentinel-bearer-value run "$M")
eq "env_set: a set variable passes" "$rc" 0
lacks "env_set: its value never reaches output" "sentinel-bearer-value"
rc=$(run "$M")
eq "env_set: unset is a FAIL" "$rc" 1

# --- hook marker --------------------------------------------------------------

mkdir -p "$FHOME/.agents" "$FHOME/.claude"
echo '{"hooks":{"SessionStart":[{"command":"~/.claude/bin/session-cache-verdict"}]}}' \
    > "$FHOME/.claude/settings.json"
printf 'cache=rebuild\nsession_id=sess-1\n' > "$FHOME/.agents/.session-marker"
entry hook fast 'hook_fired ~/.agents/.session-marker ~/.claude/settings.json session-cache-verdict' \
    this-session 'hook_fired ~/.agents/no-marker ~/.claude/settings.json session-cache-verdict' > "$M"
rc=$(CLAUDE_CODE_SESSION_ID=sess-1 run "$M")
eq "hook: marker naming this session passes" "$rc" 0
rc=$(CLAUDE_CODE_SESSION_ID=sess-2 run "$M")
eq "hook: a snapshot's marker for another session is a FAIL" "$rc" 1
has "hook: observed other-session" "observed=other-session"
# CLAUDE_CODE_SESSION_ID is set in a real session's own environment, so the
# no-id case forces it empty rather than relying on it being absent.
rc=$(CLAUDE_CODE_SESSION_ID='' run "$M" --brief)
eq "hook: no session id is unknown" "$rc" 0
has "hook: state=unknown" "state=unknown"

# --- agent observations -------------------------------------------------------
#
# The agent quotes from its context; the probe compares the quote with the file
# it should have come from. The control names a heading or skill that exists
# nowhere, so the only honest answer to it is `absent`.

# shellcheck disable=SC2016 # literal backticks: policy markdown, not a substitution
printf '# Policy\n\n## Some heading\n\nThe first paragraph, with `code` and a comma,\ncontinues on a second line.\n\nA later paragraph.\n' \
    > "$WORK/policy.md"
mkdir -p "$WORK/skill"
printf -- "---\nname: demo\ndescription: 'Do the demo thing cleanly: tidy every part of it.'\n---\n\n# Demo\n" \
    > "$WORK/skill/SKILL.md"
{
    entry pol agent "agent policy pol $WORK/policy.md Some heading" present \
        "agent policy pol-ctl $WORK/policy.md No such heading"
    entry skl agent "agent skill skl $WORK/skill/SKILL.md" present \
        "agent skill skl-ctl $WORK/no-skill/SKILL.md"
} > "$M"

rc=$(run "$M" --agent --answer 'pol=The first paragraph, with code and a comma continues' \
    --answer pol-ctl=absent --answer 'skl=Do the demo thing cleanly' --answer skl-ctl=absent)
eq "agent: true quotes with absent controls pass" "$rc" 0
has "agent: both pass" "pass=2 fail=0"

rc=$(run "$M" --agent --answer 'pol=THE FIRST PARAGRAPH WITH CODE AND A' \
    --answer pol-ctl=Absent --answer 'skl=do the demo thing, cleanly' --answer skl-ctl=ABSENT --brief)
eq "agent: case and punctuation are ignored" "$rc" 0

# The negative control for the control: an agent that quotes text for a
# heading that does not exist is answering from expectation.
rc=$(run "$M" --agent --answer 'pol=The first paragraph, with code and a comma' \
    --answer 'pol-ctl=There is some text under this heading' \
    --answer 'skl=Do the demo thing cleanly' --answer skl-ctl=absent)
eq "agent: a quote for the absent control is unproven, exit 2" "$rc" 2
has "agent: the policy check is unproven, not pass" "unproven pol "
rc=$(run "$M" --agent --answer 'pol=The first paragraph, with code and a comma' --answer pol-ctl=absent \
    --answer 'skl=Do a different thing entirely now' --answer skl-ctl=absent)
eq "agent: a wrong quote is a FAIL" "$rc" 1
has "agent: observed wrong" "observed=wrong expected=present"
rc=$(run "$M" --agent --answer pol=absent --answer pol-ctl=absent \
    --answer 'skl=Do the demo thing cleanly' --answer skl-ctl=absent)
eq "agent: policy reported absent is a FAIL" "$rc" 1
has "agent: observed absent" "observed=absent expected=present"
rc=$(run "$M" --agent --answer 'pol=The first paragraph' --answer pol-ctl=absent \
    --answer 'skl=Do the demo thing cleanly' --answer skl-ctl=absent)
eq "agent: a quote under five words cannot pass" "$rc" 1
rc=$(run "$M" --agent --answer 'pol=A later paragraph is here now' --answer pol-ctl=absent \
    --answer 'skl=Do the demo thing cleanly' --answer skl-ctl=absent)
eq "agent: only the first paragraph under the heading counts" "$rc" 1

rc=$(run "$M" --agent --brief)
eq "agent: no answers is unknown, exit 0" "$rc" 0
has "agent: state=unknown" "state=unknown"
rc=$(run "$M" --brief)
eq "agent: entries are skipped without --agent" "$rc" 0
has "agent: both skipped" "skipped=2"

rc=$( (sh "$SCRIPT" --answer 'no-equals-sign') > "$WORK/out" 2>&1; echo $?)
eq "agent: a malformed --answer exits 64" "$rc" 64

# --- selection ----------------------------------------------------------------

{
    entry fast-one fast 'tool conformance-fake-tool' present 'tool conformance-no-such-tool'
    entry full-one full 'tool conformance-no-such-tool' present 'tool conformance-fake-tool'
} > "$M"
rc=$(run "$M" --fast --brief)
eq "--fast: a failing full entry is not run" "$rc" 0
has "--fast: it counts as skipped" "pass=1 fail=0 unproven=0 unknown=0 skipped=1"
rc=$(run "$M")
eq "full mode runs it" "$rc" 1

entry elsewhere fast 'tool conformance-no-such-tool' present 'tool conformance-fake-tool' other-surface > "$M"
rc=$(run "$M" --brief)
eq "surface: another surface's entry is skipped, exit 0" "$rc" 0
has "surface: nothing applicable is not-applicable, not ok" "state=not-applicable"

# --- malformed matrix ---------------------------------------------------------

printf '[half]\nmode=fast\nsurface=test\nprobe=tool sh\nexpect=present\n' > "$M"
rc=$(run "$M" --brief)
eq "invalid: a stanza missing keys exits 3" "$rc" 3
has "invalid: names what is missing" "missing: control measured claim depends"

entry crossed fast 'tool sh' present 'egress https://refused.test/' > "$M"
rc=$(run "$M")
eq "invalid: a control through another function exits 3" "$rc" 3
has "invalid: says they must match" "they must match"

entry bogus fast 'nosuchprobe x' present 'nosuchprobe y' > "$M"
rc=$(run "$M")
eq "invalid: an unknown probe function exits 3" "$rc" 3

# Invalid is reported even for an entry this surface would skip: a stanza that
# drops out silently is an assertion nobody is making any more.
printf '[half]\nmode=fast\nsurface=other-surface\nprobe=tool sh\n' > "$M"
rc=$(run "$M")
eq "invalid: checked before the surface filter" "$rc" 3

rc=$(run "$WORK/no-such-matrix")
eq "unreadable matrix exits 3" "$rc" 3

rc=$( (sh "$SCRIPT" --bogus) > "$WORK/out" 2>&1; echo $?)
eq "unknown argument exits 64" "$rc" 64

# --- the real matrix ----------------------------------------------------------

# Validation runs before the surface filter, so a surface nothing matches
# checks every stanza while probing none.
rc=$(env CONFORMANCE_SURFACE=no-such-surface sh "$SCRIPT" --matrix "$REAL_MATRIX" --brief > "$WORK/out" 2>&1; echo $?)
eq "real matrix: every stanza is well-formed" "$rc" 0
has "real matrix: and none applies to a made-up surface" "state=not-applicable"

dups=$(sed -n 's/^\[\(.*\)\][[:space:]]*$/\1/p' "$REAL_MATRIX" | sort | uniq -d)
eq "real matrix: no id appears twice" "$dups" ""

n=$(grep -c '^\[' "$REAL_MATRIX")
nfast=$(grep -c '^mode=fast$' "$REAL_MATRIX")
if [ "$n" -gt 0 ] && [ "$nfast" -gt 0 ]; then ok "real matrix: has entries ($n, $nfast fast)"; else no "real matrix: empty or no fast subset"; fi

# --- env-conformance-stamp ----------------------------------------------------
#
# The suite's one writer. It must change measured= in the named stanzas and
# nothing else, and write nothing at all when any id is wrong.

STAMP="$ROOT/home/bin/env-conformance-stamp"
SM="$WORK/stamp.conf"
{
    printf '# header comment, kept\n\n'
    entry one fast 'tool sh' present 'tool conformance-no-such-tool'
    entry two fast 'tool sh' present 'tool conformance-no-such-tool'
    entry three full 'tool sh' present 'tool conformance-no-such-tool'
} > "$SM"
cp "$SM" "$WORK/stamp.orig"

rc=$( (sh "$STAMP" "$SM" 2026-11-02 one three) > "$WORK/out" 2>&1; echo $?)
eq "stamp: named entries exit 0" "$rc" 0
has "stamp: reports what it stamped" "stamped three measured=2026-11-02"
eq "stamp: exactly the two named measured= lines changed" \
    "$(diff "$WORK/stamp.orig" "$SM" | grep -c '^>')" 2
eq "stamp: and to the new date" "$(grep -c '^measured=2026-11-02$' "$SM")" 2
eq "stamp: the unnamed entry keeps its date" \
    "$(sed -n '/^\[two\]/,/^$/s/^measured=//p' "$SM")" 2026-10-20
eq "stamp: comments and other keys untouched" \
    "$(diff "$WORK/stamp.orig" "$SM" | grep '^[<>]' | grep -vc 'measured=')" 0

cp "$SM" "$WORK/stamp.before"
rc=$( (sh "$STAMP" "$SM" 2026-12-01 two no-such-id) > "$WORK/out" 2>&1; echo $?)
eq "stamp: an unknown id exits 1" "$rc" 1
has "stamp: names it" "no such entries: no-such-id"
eq "stamp: and writes nothing, not even the known id" "$(cmp -s "$WORK/stamp.before" "$SM" && echo same)" same

rc=$( (sh "$STAMP" "$SM" 'next week' one) > "$WORK/out" 2>&1; echo $?)
eq "stamp: a malformed date exits 64" "$rc" 64
rc=$( (sh "$STAMP" "$SM" 2026-12-01) > "$WORK/out" 2>&1; echo $?)
eq "stamp: no ids exits 64" "$rc" 64
eq "stamp: leaves no temp file beside the matrix" "$(find "$WORK" -name 'stamp.conf.stamp.*' | wc -l | tr -d ' ')" 0

# The stamped matrix is still one the runner accepts.
rc=$(env CONFORMANCE_SURFACE=no-such-surface sh "$SCRIPT" --matrix "$SM" --brief > "$WORK/out" 2>&1; echo $?)
eq "stamp: the result still validates" "$rc" 0

# --- writes nothing -----------------------------------------------------------

# The real matrix under the stubs, as the real surface, in full mode: every
# probe function runs. HOME and cwd must be byte-for-byte as they were.
snap() { (cd "$1" && find . -exec ls -ld {} + 2> /dev/null | sort); }
before_home=$(snap "$FHOME")
before_cwd=$(snap "$WORK")
(cd "$WORK" && env PATH="$STUB/bin:$PATH" STUB="$STUB" HOME="$FHOME" \
    CONFORMANCE_SURFACE=claude-cloud CONFORMANCE_TIMEOUT=2 CLAUDE_CODE_SESSION_ID=sess-1 \
    sh "$SCRIPT" --matrix "$REAL_MATRIX") > /dev/null 2>&1
eq "writes nothing to HOME" "$(snap "$FHOME")" "$before_home"
eq "writes nothing to cwd" "$(snap "$WORK")" "$before_cwd"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
