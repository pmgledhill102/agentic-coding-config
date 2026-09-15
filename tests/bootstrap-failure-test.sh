#!/bin/sh
# Failure-reporting tests for cloud/bootstrap.sh.
#
# The invariant these guard: a run that does not finish must leave something a
# later session can find. Before #345 it left nothing -- the manifest is written
# only at the end of a successful run, and the setup script's `exit 0` (correct:
# a non-zero setup script fails the whole session) meant a container came up
# looking clean with half a toolkit in it. A sandbox ran for a day that way.
#
# The banner half is not redundant with the manifest half. `start-session` reads
# the manifest, but `start-session` is installed near the END of the bootstrap,
# so a failure early enough removes the only thing able to report the manifest.
# The banner goes into the policy files, which are read whether or not any skill
# survived -- so the two artefacts cover opposite ends of the same script.
#
# Usage: sh tests/bootstrap-failure-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOTSTRAP="$ROOT/cloud/bootstrap.sh"

# Which ref the fetching cases pull Tier 1 content from.
#
# `main` is correct once a change has merged and wrong while one is in flight.
# The bootstrap fetches its skills, policy and helper scripts BY REF, so a
# local script that names a file the branch adds 404s against main -- and the
# failure arrives as `status=failed`, which reads as a broken bootstrap rather
# than as content that has not merged yet. #430 added the first helper to hit
# this, and the test reported six unrelated assertions failing.
#
# So prefer the branch under test when origin has it, and fall back to main.
# GITHUB_HEAD_REF is set on a pull_request run; a local run asks git.
#
# The honest limit: this resolves against the REMOTE, so a commit that adds a
# helper has to be pushed before this test can pass. Running it on a dirty tree
# tests the last pushed state of any fetched file, not the working copy.
BOOTSTRAP_TEST_REF=${BOOTSTRAP_TEST_REF:-}
if [ -z "$BOOTSTRAP_TEST_REF" ]; then
    _branch=${GITHUB_HEAD_REF:-$(git -C "$ROOT" branch --show-current 2> /dev/null || true)}
    if [ -n "$_branch" ] &&
        git -C "$ROOT" ls-remote --exit-code --heads origin "$_branch" > /dev/null 2>&1; then
        BOOTSTRAP_TEST_REF=$_branch
    else
        BOOTSTRAP_TEST_REF=main
    fi
fi

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

count() {
    # count <pattern> <file> -- 0 when the file is absent OR has no match.
    # `grep -c` prints 0 and exits 1 on no match, so a bare `|| echo 0` emits
    # two lines and every comparison against it fails. Capturing rather than
    # piping through `head -1`: head exits after its line, and the `echo` then
    # takes EPIPE and dash reports "echo: I/O error" into the CI log.
    _n=$(grep -c "$1" "$2" 2> /dev/null) || _n=0
    [ -n "$_n" ] || _n=0
    echo "$_n"
}

check() {
    # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else
        no "$1"
        printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
    fi
}

# --with-gcloud etc. are never reached: every run here dies in the argument
# loop, which is deliberately the EARLIEST failure the script can have. If the
# trap covers that, it covers everything later. It did not always -- the trap
# used to be installed below the loop, so a usage error reported nothing.
run_failing_bootstrap() {
    HOME="$1" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --a-flag-that-does-not-exist > /dev/null 2>&1
    echo $?
}

echo "cloud/bootstrap.sh — reporting a run that did not finish"

# --- 1. the manifest -------------------------------------------------------
H=$(mktemp -d)
rc=$(run_failing_bootstrap "$H")
check "a failing run exits non-zero" "1" "$rc"

M="$H/.agents/.bootstrap-manifest"
if [ -f "$M" ]; then
    ok "a failing run writes a manifest"
    check "  status names the failure" "failed" "$(sed -n 's/^status=//p' "$M")"
    check "  exit_code is recorded" "1" "$(sed -n 's/^exit_code=//p' "$M")"
    check "  failed_step names the step" \
        "unknown argument: --a-flag-that-does-not-exist" \
        "$(sed -n 's/^failed_step=//p' "$M")"
    # A reader sent to a log that is not there is worse off than one told
    # nothing, so the path is recorded rather than assumed.
    check "  log path is recorded" "/tmp/bootstrap.log" "$(sed -n 's/^log=//p' "$M")"
else
    no "a failing run writes a manifest"
fi
rm -rf "$H"

# --- 2. the banner ---------------------------------------------------------
#
# Claude reads ~/.claude/CLAUDE.md and Codex reads AGENTS.md, and neither knows
# to look for the other's file, so a claude-* profile writes both.
H=$(mktemp -d)
run_failing_bootstrap "$H" > /dev/null
for f in "$H/.claude/CLAUDE.md" "$H/.agents/AGENTS.md"; do
    if grep -q 'acc:bootstrap-failed:start' "$f" 2> /dev/null; then
        ok "banner reaches $(basename "$(dirname "$f")")/$(basename "$f")"
    else
        no "banner reaches $(basename "$(dirname "$f")")/$(basename "$f")"
    fi
done
rm -rf "$H"

# A codex container has nothing that ever rewrites ~/.claude/CLAUDE.md, so a
# banner left there would outlive the failure it describes.
H=$(mktemp -d)
HOME="$H" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox --nope > /dev/null 2>&1
if [ -f "$H/.claude/CLAUDE.md" ]; then
    no "codex profile leaves CLAUDE.md alone"
else
    ok "codex profile leaves CLAUDE.md alone"
fi
check "codex profile still gets a banner in AGENTS.md" "1" \
    "$(count 'acc:bootstrap-failed:start' "$H/.agents/AGENTS.md")"
rm -rf "$H"

# --- 3. repeated failures, and real policy underneath ----------------------
#
# A cloud environment re-runs its setup script on a schedule, so a container
# that fails once fails repeatedly. Stacking a banner per run would bury the
# policy under its own warnings; dropping the policy would be worse still.
H=$(mktemp -d)
mkdir -p "$H/.claude"
printf '<!-- GENERATED -->\nPOLICY-CANARY-A\nPOLICY-CANARY-B\n' > "$H/.claude/CLAUDE.md"
run_failing_bootstrap "$H" > /dev/null
run_failing_bootstrap "$H" > /dev/null
run_failing_bootstrap "$H" > /dev/null
check "three failures leave one banner" "1" \
    "$(grep -c 'acc:bootstrap-failed:start' "$H/.claude/CLAUDE.md")"
check "  and the matching end marker" "1" \
    "$(grep -c 'acc:bootstrap-failed:end' "$H/.claude/CLAUDE.md")"
check "existing policy survives underneath" "2" \
    "$(grep -c 'POLICY-CANARY' "$H/.claude/CLAUDE.md")"
rm -rf "$H"

# --- 4. pip_install's fallback chain ---------------------------------------
#
# Three attempts, and the third is not a louder version of the second. A
# package that must UPGRADE an apt-installed dependency fails on pip's inability
# to uninstall it ("Cannot uninstall packaging 24.0, RECORD file not found") --
# missing dpkg metadata, not the PEP 668 marker that --break-system-packages
# bypasses. The two read alike in a log and only --ignore-installed clears the
# first. checkov against the sandbox image is the case that took the whole
# bootstrap down (#344).
#
# Stubbed rather than run for real: the failure needs an apt-installed
# `packaging` to reproduce, which a CI runner may or may not have, and a test
# that quietly stops testing anything is worse than no test.
H=$(mktemp -d)
mkdir -p "$H/stub"
for n in pip pip3; do
    cat > "$H/stub/$n" << 'STUB'
#!/bin/sh
echo "$*" >> "$LOGF"
case "$*" in
    *--ignore-installed*) exit 0 ;;
    *) echo "ERROR: Cannot uninstall packaging 24.0, RECORD file not found." >&2; exit 1 ;;
esac
STUB
    chmod +x "$H/stub/$n"
done

sed -n '/^pip_install() {/,/^}$/p' "$BOOTSTRAP" > "$H/fn.sh"
check "pip_install was extractable from the script" "1" \
    "$(grep -c '^pip_install() {' "$H/fn.sh")"

PATH="$H/stub:$PATH" LOGF="$H/calls.log" sh -c '. "$0/fn.sh"; pip_install checkov' "$H"
check "pip_install recovers on the third attempt" "0" "$?"
check "  it tried three times" "3" "$(wc -l < "$H/calls.log" | tr -d ' ')"
check "  bare install first" "1" \
    "$(sed -n 1p "$H/calls.log" | grep -c -- '--quiet --no-input checkov')"
check "  then --break-system-packages" "1" \
    "$(sed -n 2p "$H/calls.log" | grep -cv -- '--ignore-installed')"
check "  --ignore-installed only as a last resort" "1" \
    "$(sed -n 3p "$H/calls.log" | grep -c -- '--ignore-installed')"
rm -rf "$H"

# --- 5. the gather script reads what the bootstrap writes ------------------
#
# The two halves ship in different files and are deployed by different
# mechanisms, so nothing but a test holds them to the same field names.
GATHER="$ROOT/home/bin/start-session-gather-state"
H=$(mktemp -d)
mkdir -p "$H/.agents/skills"
cat > "$H/.agents/.bootstrap-manifest" << 'EOF'
status=failed
exit_code=1
failed_step=could not install checkov from PyPI
failed_at=2026-08-29T06:38:00Z
ref=main
profile=claude-cloud-sandbox
log=/tmp/bootstrap.log
EOF
currency() {
    HOME="$1" "$GATHER" 2> /dev/null |
        sed -n '/^===bootstrap_currency/,/^===[a-z]/p' | sed -n '2p'
}
check "gather reports state=failed with the step" \
    "state=failed step=could not install checkov from PyPI" "$(currency "$H")"

# A manifest predating the status field can only have been written by a run
# that reached the end, so its absence must keep meaning what it used to.
cat > "$H/.agents/.bootstrap-manifest" << 'EOF'
ref=main
ref_kind=pin
sha=abc123
installed_at=2026-08-20T00:00:00Z
EOF
check "a manifest with no status= is not read as failed" \
    "state=pinned ref=main sha=abc123 installed_at=2026-08-20T00:00:00Z" \
    "$(currency "$H")"

# A behind container must be told BOTH halves. Reporting only the re-run is
# what makes the drift recur: it fixes the session in front of you and leaves
# the next one restoring the same snapshot (#347).
cat > "$H/.agents/.bootstrap-manifest" << 'EOF'
status=ok
ref=main
ref_kind=ref
sha=0000000000000000000000000000000000000000
installed_at=2026-08-01T00:00:00Z
EOF
behind=$(HOME="$H" "$GATHER" 2> /dev/null |
    sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
check "a behind container gets the in-session remedy" "1" \
    "$(printf '%s\n' "$behind" | grep -c '^remedy=re-run the bootstrap')"
check "  and the recurrence half (bump Rev:)" "1" \
    "$(printf '%s\n' "$behind" | grep -c '^recurrence=.*Rev:')"

rm -f "$H/.agents/.bootstrap-manifest"
check "no manifest still means no-manifest, not failed" \
    "state=no-manifest" "$(currency "$H")"
rm -rf "$H"

# --- 6. tiering: the toolkit runs before any capability -------------------
#
# The ordering is the fix, not a side effect of it: every toolkit section is a
# curl and a file write, and every capability is a toolchain download, so the
# cheap valuable work must not sit behind the expensive fragile work (#346).
# Asserted on the log's own ordering rather than on line numbers, which drift.
H=$(mktemp -d)
LOG="$H/run.log"
HOME="$H" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --no-gcloud --no-precommit --no-hooks --no-terraform \
    > "$LOG" 2>&1
check "a toolkit-only run succeeds" "0" "$?"

first_line_of() { grep -n "$1" "$LOG" 2> /dev/null | head -1 | cut -d: -f1; }
skills_at=$(first_line_of 'skill   -> .*start-session')
policy_at=$(first_line_of 'policy  ->')
manifest_at=$(first_line_of 'manifst ->')
if [ -n "$skills_at" ] && [ -n "$policy_at" ] && [ -n "$manifest_at" ]; then
    ok "toolkit sections ran (policy, skills, manifest all logged)"
    if [ "$policy_at" -lt "$skills_at" ]; then
        ok "  policy lands before skills"
    else
        no "  policy lands before skills"
    fi
    if [ "$skills_at" -lt "$manifest_at" ]; then
        ok "  manifest is written last"
    else
        no "  manifest is written last"
    fi
else
    no "toolkit sections ran (policy, skills, manifest all logged)"
fi
check "a clean run records status=ok" "ok" \
    "$(sed -n 's/^status=//p' "$H/.agents/.bootstrap-manifest")"
check "  and an empty degraded list" "" \
    "$(sed -n 's/^degraded=//p' "$H/.agents/.bootstrap-manifest")"
check "  and leaves no failure banner" "0" \
    "$(count 'acc:bootstrap-failed' "$H/.claude/CLAUDE.md")"
rm -rf "$H"

# --- 7. a capability that cannot install degrades, it does not abort -------
#
# The whole point of the tier split. gh is the cheapest capability to fail on
# purpose: pointing its download at an unresolvable host makes `fetch` fail the
# way a blocked egress or a moved release asset would, and the `die` inside
# cap_gh then has to exit the SUBSHELL rather than the run.
#
# The second sed is what makes this run the same everywhere. cap_gh short
# circuits on `command -v gh`, and a GitHub Actions runner ships gh
# pre-installed -- so on CI the section logged "already present, left alone",
# never attempted a download, and nothing degraded. Neutering the guard forces
# the install path on any host. PATH cannot do this instead: gh lives in a
# system directory the rest of the script also needs.
H=$(mktemp -d)
LOG="$H/run.log"
sed -e 's#https://github.com/cli/cli/releases#https://bootstrap-test.invalid/cli#' \
    -e 's#if command -v gh > /dev/null 2>&1; then#if false; then#' \
    "$BOOTSTRAP" > "$H/bootstrap.sh"
check "the gh fixture neutered the already-present guard" "0" \
    "$(count 'command -v gh > /dev/null 2>&1; then' "$H/bootstrap.sh")"
HOME="$H" sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --with-gh --no-gcloud --no-precommit --no-hooks \
    > "$LOG" 2>&1
check "a failing capability does not fail the run" "0" "$?"

M="$H/.agents/.bootstrap-manifest"
check "the manifest is still written" "1" "$([ -f "$M" ] && echo 1 || echo 0)"
check "  status is degraded, not failed" "degraded" "$(sed -n 's/^status=//p' "$M")"
check "  and it names the capability" "gh" "$(sed -n 's/^degraded=//p' "$M")"
# A degraded container is not a broken one: the banner is for a dead run only,
# or every sandbox without gh would come up shouting.
check "  no failure banner for a degraded run" "0" \
    "$(count 'acc:bootstrap-failed' "$H/.claude/CLAUDE.md")"
# The toolkit must still be complete -- that is what the tier split buys.
check "  the skills still installed" "1" \
    "$([ -f "$H/.agents/skills/start-session/SKILL.md" ] && echo 1 || echo 0)"
check "  the policy still installed" "1" \
    "$([ -f "$H/.claude/CLAUDE.md" ] && echo 1 || echo 0)"
check "the run says DEGRADED out loud" "1" "$(grep -c 'DEGRADED' "$LOG")"

# And start-session must surface it without calling the container broken.
mkdir -p "$H/.agents/skills"
cur=$(HOME="$H" "$GATHER" 2> /dev/null |
    sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
check "gather emits a degraded= line" "degraded=gh" \
    "$(printf '%s\n' "$cur" | sed -n 's/^\(degraded=.*\)$/\1/p')"
check "  and does NOT report state=failed" "0" \
    "$(printf '%s\n' "$cur" | grep -c 'state=failed')"
rm -rf "$H"

# --- 8. the pre-commit warm ------------------------------------------------
#
# The invariant: a fresh container must not meet a cold pre-commit cache on its
# first commit. Cold, the estate's hook set is ~2 minutes of Go builds, and that
# is paid inside precommit-claude-hook's 120 s timeout -- a gate that times out
# and lets the commit through, or a commit killed for a reason unrelated to its
# content (#441).
#
# The pinned file first, because the warm is only worth anything if its revs are
# the ones the estate's configs actually carry.
echo
echo "cloud/precommit-warm.yaml — the pinned estate hook set"

WARM_YAML="$ROOT/cloud/precommit-warm.yaml"
check "the warm config exists" "1" "$([ -f "$WARM_YAML" ] && echo 1 || echo 0)"
check "  and declares repos:" "1" "$(count '^repos:' "$WARM_YAML")"

# pre-commit keys its cache on (repo URL, rev), so an unpinned rev warms
# nothing a later run can hit. Every repo entry must carry one.
repo_lines=$(count '^  - repo: https://' "$WARM_YAML")
rev_lines=$(count '^    rev: ' "$WARM_YAML")
check "every repo carries a rev" "$repo_lines" "$rev_lines"
check "  and none of them float" "0" \
    "$(count '^    rev: \(main\|master\|HEAD\)$' "$WARM_YAML")"

# The three that make this file worth having. If a rename or a bump ever drops
# one, the file still warms something and the two minutes come back.
for r in gitleaks actionlint pre-commit-shfmt; do
    check "  warms $r (language: golang)" "1" "$(count "/$r\$" "$WARM_YAML")"
done

# semgrep is #316's, provisioned as a system binary. Its pre-commit hook clones
# the whole monorepo -- 1.1 G of cache and ~190 s -- which would not fit the
# snapshot budget and would cache something the estate decided not to use.
check "  and does not warm semgrep" "0" \
    "$(count '^  - repo: .*semgrep' "$WARM_YAML")"

echo
echo "cloud/bootstrap.sh — warming the cache at bootstrap time"

# The function is exercised directly, the way pip_install is in §4: a real
# bootstrap run would have to install pre-commit, shellcheck, actionlint and
# markdownlint-cli2 first, and the warm is what is under test.
H=$(mktemp -d)
{
    for fn in precommit_home cap_precommit_warm fetch now_s record_timing capability; do
        sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
    done
} > "$H/fn.sh"
for f in precommit_home cap_precommit_warm fetch capability; do
    check "$f was extractable from the script" "1" "$(count "^$f() {" "$H/fn.sh")"
done

# The harness the extracted functions expect. `die` is the real contract --
# write the reason where capability() reads it, then leave the subshell.
cat > "$H/harness.sh" << 'HARNESS'
set -eu
log() { echo "[bootstrap] $*"; }
die() {
    if [ -n "${FAIL_FILE:-}" ]; then echo "$*" > "$FAIL_FILE" 2> /dev/null || true; fi
    echo "[bootstrap] error: $*" >&2
    exit 1
}
CURL_RETRY_OPTS=
DEGRADED=
TIMINGS=
. "$FNS"
HARNESS

# A config with one small python hook repo. The point here is the MECHANISM --
# fetch, scratch repo, cache, count, manifest field -- and a golang hook would
# spend two minutes proving nothing this does not.
mkdir -p "$H/raw/cloud"
cat > "$H/raw/cloud/precommit-warm.yaml" << 'CFG'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
CFG

# --- 8a. no pre-commit, no complaint ---------------------------------------
#
# cap_precommit names itself in `degraded=` when the install fails. One root
# cause reported under two names makes that list harder to act on, so the warm
# stands down instead of dying.
# A PATH holding nothing but a shell: emptying it entirely would take `sh`
# with it and the 127 would look like the stand-down under test.
mkdir -p "$H/t8a" "$H/nopc"
ln -sf "$(command -v sh)" "$H/nopc/sh"
out=$(TMP="$H/t8a" FAIL_FILE="$H/t8a.fail" RAW="file://$H/raw" REF=test \
    FNS="$H/fn.sh" PATH="$H/nopc" \
    sh -c '. "$0"; cap_precommit_warm' "$H/harness.sh" 2>&1)
check "with no pre-commit on PATH the warm stands down" "0" "$?"
check "  and says so rather than failing silently" "1" \
    "$(printf '%s\n' "$out" | grep -c 'nothing to warm')"

# --- 8b. the real thing, from a directory that is not a checkout ------------
#
# The gotcha this guards: `pre-commit install-hooks` shells out to git and
# refuses outside a work tree ("Is it installed, and are you in a Git repository
# directory?", exit 1). A setup script's cwd belongs to the harness and is
# frequently not a checkout, so the function makes its own scratch repo. Before
# it did, the warm failed on every container whose cwd happened to be /.
if command -v pre-commit > /dev/null 2>&1; then
    mkdir -p "$H/t8b" "$H/notarepo" "$H/cache"
    # A planted checkout for mechanism 2, with the same cheap config, so the
    # exact-match half is asserted rather than assumed.
    mkdir -p "$H/ws/repo-a"
    git -C "$H/ws/repo-a" init -q 2> /dev/null
    cp "$H/raw/cloud/precommit-warm.yaml" "$H/ws/repo-a/.pre-commit-config.yaml"

    log8b="$H/t8b.log"
    ( cd "$H/notarepo" && TMP="$H/t8b" FAIL_FILE="$H/t8b.fail" RAW="file://$H/raw" \
        REF=test FNS="$H/fn.sh" HOME="$H/ws" PRE_COMMIT_HOME="$H/cache" \
        sh -c '. "$0"; cap_precommit_warm' "$H/harness.sh" ) > "$log8b" 2>&1
    check "a warm from a non-checkout cwd succeeds" "0" "$?"
    check "  it warmed the estate hook set" "1" \
        "$(count 'warm    -> estate hook set' "$log8b")"
    check "  and the checkout it found in the workspace" "1" \
        "$(count 'warm    -> .*repo-a/.pre-commit-config.yaml' "$log8b")"

    # The acceptance criterion this file exists to hold: cache present after the
    # bootstrap, asserted from the cache rather than inferred from an exit code.
    envs=$(find "$H/cache" -maxdepth 1 -type d -name 'repo*' 2> /dev/null | wc -l | tr -d ' ')
    if [ "${envs:-0}" -gt 0 ]; then
        ok "the cache really holds a hook environment ($envs)"
    else
        no "the cache really holds a hook environment"
    fi
    # And the same number reaches the manifest, through the file that carries it
    # out of capability()'s subshell.
    check "  the count reaches the manifest field" "$envs" \
        "$(cat "$H/t8b/warm-envs" 2> /dev/null || echo missing)"

    # A hook that runs without building anything is the whole point.
    ( cd "$H/ws/repo-a" && PRE_COMMIT_HOME="$H/cache" \
        pre-commit run --all-files ) > "$H/t8b-run.log" 2>&1 || true
    check "  a later run builds no environment" "0" \
        "$(count 'Installing environment' "$H/t8b-run.log")"
else
    no "pre-commit is not on PATH — the warm assertions did not run"
    echo "        install it (pip install pre-commit); CI does this deliberately"
fi

# --- 8c. a warm that cannot run degrades, it does not abort ----------------
#
# Tier 2, and the reason the warm is its own capability rather than part of
# cap_precommit: without pre-commit there is no gate, while without the warm the
# gate is present and the first commit pays for it. Those are different
# failures and `degraded=` has to be able to say which.
mkdir -p "$H/t8c"
cat > "$H/t8c-run.sh" << 'RUN'
set -eu
FAIL_FILE="$TMP/fail-reason"
. "$HARNESS_PATH"
FAIL_FILE="$TMP/fail-reason"
capability 1 precommit-warm cap_precommit_warm
echo "SURVIVED"
echo "degraded=$DEGRADED"
echo "timings=$TIMINGS"
RUN
out=$(TMP="$H/t8c" RAW="file://$H/raw-does-not-exist" REF=test FNS="$H/fn.sh" \
    HARNESS_PATH="$H/harness.sh" PRE_COMMIT_HOME="$H/cache-8c" \
    sh "$H/t8c-run.sh" 2>&1) || true
check "a warm that cannot fetch its config does not kill the run" "1" \
    "$(printf '%s\n' "$out" | grep -c '^SURVIVED$')"
check "  it names itself in degraded=" "1" \
    "$(printf '%s\n' "$out" | grep -c '^degraded=precommit-warm$')"
check "  and it is timed even though it failed" "1" \
    "$(printf '%s\n' "$out" | grep -c '^timings=precommit-warm=')"
rm -rf "$H"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
