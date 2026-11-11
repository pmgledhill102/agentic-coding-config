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
  _branch=${GITHUB_HEAD_REF:-$(git -C "$ROOT" branch --show-current 2>/dev/null || true)}
  if [ -n "$_branch" ] \
    && git -C "$ROOT" ls-remote --exit-code --heads origin "$_branch" >/dev/null 2>&1; then
    BOOTSTRAP_TEST_REF=$_branch
  else
    BOOTSTRAP_TEST_REF=main
  fi
fi

# The full runs below take this copy, which skips the golangci-lint capability.
# It is unconditional, so every full run would download it for a reason none of
# those cases is about. Section 10 tests the capability itself, and section 11
# runs it against a fixture.
BOOTSTRAP_FULL=$(mktemp)
# shellcheck disable=SC2016 # $TC_TOOLS is a literal the sed matches
sed 's/^capability "\$TC_TOOLS" golangci cap_golangci$/capability 0 golangci cap_golangci/' \
  "$BOOTSTRAP" >"$BOOTSTRAP_FULL"
trap 'rm -f "$BOOTSTRAP_FULL"' EXIT

# Every full run below takes the copy under test as it is. Without this the
# self-check would find the remote's copy of the script different from the
# local one and run that instead, which tests nothing about the change. Section
# 6b unsets it where the hand-over itself is the subject.
BOOTSTRAP_REEXEC=1
export BOOTSTRAP_REEXEC

PASS=0
FAIL=0

# real_tool <name> [path] -- the first <name> on path (default PATH) that is not
# an agent shim.
#
# `command -v` resolves to ~/.claude/bin/shims/<name> in a sandbox that has the
# shims installed, and a shim finds the real tool by searching the rest of
# PATH. Symlinked alone into a restricted PATH farm it has nothing to find and
# exits 127, so the farm must hold the real binary. A shim is a symlink whose
# target is named agent-shim.
real_tool() {
  _rt_ifs=$IFS
  IFS=:
  set -f
  for _rt_d in ${2:-$PATH}; do
    _rt_c="$_rt_d/$1"
    [ -f "$_rt_c" ] && [ -x "$_rt_c" ] || continue
    case $(readlink "$_rt_c" 2>/dev/null) in */agent-shim | agent-shim) continue ;; esac
    set +f
    IFS=$_rt_ifs
    printf '%s\n' "$_rt_c"
    return 0
  done
  set +f
  IFS=$_rt_ifs
  return 1
}

ok() {
  PASS=$((PASS + 1))
  printf '  ok    %s\n' "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1"
}

count() {
  # count <pattern> <file> -- 0 when the file is absent OR has no match.
  # `grep -c` prints 0 and exits 1 on no match, so a bare `|| echo 0` emits
  # two lines and every comparison against it fails. Capturing rather than
  # piping through `head -1`: head exits after its line, and the `echo` then
  # takes EPIPE and dash reports "echo: I/O error" into the CI log.
  _n=$(grep -c "$1" "$2" 2>/dev/null) || _n=0
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
  HOME="$1" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --a-flag-that-does-not-exist >/dev/null 2>&1
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
# The banner goes in the one policy file the profile's agent reads: CLAUDE.md
# for a claude-* profile, which no longer ships an AGENTS.md at all (#310).
H=$(mktemp -d)
run_failing_bootstrap "$H" >/dev/null
check "banner reaches .claude/CLAUDE.md" "1" \
  "$(count 'acc:bootstrap-failed:start' "$H/.claude/CLAUDE.md")"
if [ -f "$H/.agents/AGENTS.md" ]; then
  no "claude profile writes no .agents/AGENTS.md"
else
  ok "claude profile writes no .agents/AGENTS.md"
fi
rm -rf "$H"

# A codex container has nothing that ever rewrites ~/.claude/CLAUDE.md, so a
# banner left there would outlive the failure it describes.
H=$(mktemp -d)
HOME="$H" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox --nope >/dev/null 2>&1
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
printf '<!-- GENERATED -->\nPOLICY-CANARY-A\nPOLICY-CANARY-B\n' >"$H/.claude/CLAUDE.md"
run_failing_bootstrap "$H" >/dev/null
run_failing_bootstrap "$H" >/dev/null
run_failing_bootstrap "$H" >/dev/null
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
  cat >"$H/stub/$n" <<'STUB'
#!/bin/sh
echo "$*" >> "$LOGF"
case "$*" in
    *--ignore-installed*) exit 0 ;;
    *) echo "ERROR: Cannot uninstall packaging 24.0, RECORD file not found." >&2; exit 1 ;;
esac
STUB
  chmod +x "$H/stub/$n"
done

sed -n '/^pip_install() {/,/^}$/p' "$BOOTSTRAP" >"$H/fn.sh"
check "pip_install was extractable from the script" "1" \
  "$(grep -c '^pip_install() {' "$H/fn.sh")"

PATH="$H/stub:$PATH" LOGF="$H/calls.log" sh -c '. "$0/fn.sh"; pip_install checkov' "$H"
check "pip_install recovers on the third attempt" "0" "$?"
check "  it tried three times" "3" "$(wc -l <"$H/calls.log" | tr -d ' ')"
check "  bare install first" "1" \
  "$(sed -n 1p "$H/calls.log" | grep -c -- '--quiet --no-input checkov')"
check "  then --break-system-packages" "1" \
  "$(sed -n 2p "$H/calls.log" | grep -cv -- '--ignore-installed')"
check "  --ignore-installed only as a last resort" "1" \
  "$(sed -n 3p "$H/calls.log" | grep -c -- '--ignore-installed')"
rm -rf "$H"

# --- 4b. python_cli_install in the system layout: uv first, pip behind it ---
#
# pip spends ~64s resolving checkov where uv takes ~10s (#608). uv must be
# given BIN_DIR, or the shim lands in ~/.local/bin rather than where pip's
# console script went, and pip must still be reached when uv fails or is absent.
H=$(mktemp -d)
mkdir -p "$H/stub" "$H/nouv"
cat >"$H/stub/pip" <<'STUB'
#!/bin/sh
echo "pip $*" >> "$LOGF"
STUB
cat >"$H/stub/uv" <<'STUB'
#!/bin/sh
echo "uv $* UV_TOOL_BIN_DIR=${UV_TOOL_BIN_DIR:-}" >> "$LOGF"
exit "${UV_RC:-0}"
STUB
chmod +x "$H/stub/pip" "$H/stub/uv"
ln -s "$H/stub/pip" "$H/nouv/pip"
for t in sh cat; do ln -s "$(command -v "$t")" "$H/nouv/$t"; done

for fn in pip_install python_cli_install; do
  sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
done >"$H/fn.sh"
check "python_cli_install was extractable from the script" "1" \
  "$(count '^python_cli_install() {' "$H/fn.sh")"
run_pci() { # run_pci <path> <uv rc> <log>
  PATH="$1" LOGF="$3" UV_RC="$2" INSTALL_MODE=system BIN_DIR=/sys/bin \
    sh -c 'log() { :; }; . "$0/fn.sh"; python_cli_install checkov' "$H"
}

run_pci "$H/stub:$PATH" 0 "$H/a.log"
check "system layout with uv installs through uv" "0" "$?"
check "  into BIN_DIR, and pip is never called" "1 0" \
  "$(count '^uv tool install checkov UV_TOOL_BIN_DIR=/sys/bin$' "$H/a.log") $(count '^pip ' "$H/a.log")"

run_pci "$H/stub:$PATH" 1 "$H/b.log"
check "a failing uv falls back to pip" "0" "$?"
check "  uv then pip, once each" "1 1" \
  "$(count '^uv ' "$H/b.log") $(count '^pip install' "$H/b.log")"

run_pci "$H/nouv" 0 "$H/c.log"
check "no uv on PATH goes straight to pip" "0 1" \
  "$(count '^uv ' "$H/c.log") $(count '^pip install' "$H/c.log")"
rm -rf "$H"

# --- 5. the gather script reads what the bootstrap writes ------------------
#
# The two halves ship in different files and are deployed by different
# mechanisms, so nothing but a test holds them to the same field names.
GATHER="$ROOT/home/bin/start-session-gather-state"
H=$(mktemp -d)
mkdir -p "$H/.agents/skills"
cat >"$H/.agents/.bootstrap-manifest" <<'EOF'
status=failed
exit_code=1
failed_step=could not install checkov from PyPI
failed_at=2026-08-29T06:38:00Z
ref=main
profile=claude-cloud-sandbox
log=/tmp/bootstrap.log
EOF
currency() {
  HOME="$1" "$GATHER" 2>/dev/null \
    | sed -n '/^===bootstrap_currency/,/^===[a-z]/p' | sed -n '2p'
}
check "gather reports state=failed with the step" \
  "state=failed step=could not install checkov from PyPI" "$(currency "$H")"

# A manifest predating the status field can only have been written by a run
# that reached the end, so its absence must keep meaning what it used to.
cat >"$H/.agents/.bootstrap-manifest" <<'EOF'
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
cat >"$H/.agents/.bootstrap-manifest" <<'EOF'
status=ok
ref=main
ref_kind=ref
sha=0000000000000000000000000000000000000000
installed_at=2026-08-01T00:00:00Z
EOF
behind=$(HOME="$H" "$GATHER" 2>/dev/null \
  | sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
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
# A resumed container keeps the neutral AGENTS.md an older run wrote (#310).
mkdir -p "$H/.agents"
printf 'STALE-NEUTRAL-POLICY\n' >"$H/.agents/AGENTS.md"
HOME="$H" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" --no-gcloud --no-precommit --no-hooks --no-terraform \
  >"$LOG" 2>&1
check "a toolkit-only run succeeds" "0" "$?"
check "  the claude profile's policy is a composed CLAUDE.md" "1" \
  "$(head -1 "$H/.claude/CLAUDE.md" 2>/dev/null | grep -c '^<!-- GENERATED')"
check "  and an older run's .agents/AGENTS.md is removed" "0" \
  "$([ -e "$H/.agents/AGENTS.md" ] && echo 1 || echo 0)"

# The telemetry helper arrives with the toolkit and is handed the manifest, so a
# run is on the spool before any ingest exists. Spool-first is the whole point:
# the setup phase cannot authenticate to one (#431).
# Wherever the manifest says the bin dir is: a root run installs system-wide.
TELEM_BIN=$(sed -n 's/^bin_dir=//p' "$H/.agents/.bootstrap-manifest" 2>/dev/null)
check "the telemetry helper is installed" "1" \
  "$([ -x "$TELEM_BIN/agent-telemetry" ] && echo 1 || echo 0)"
check "  and reachable at the path the hooks use" "1" \
  "$([ -x "$H/.claude/bin/agent-telemetry" ] && echo 1 || echo 0)"
check "  and the manifest is on the spool as a bootstrap record" "bootstrap ok" \
  "$(jq -r '.kind + " " + .fields.status' "$H/.agents/telemetry/spool.jsonl" 2>/dev/null | head -1)"

first_line_of() { grep -n "$1" "$LOG" 2>/dev/null | head -1 | cut -d: -f1; }
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
# devknowledge is on by default for claude-cloud-sandbox, the profile this run
# took by default, so the same run registered the server with no flag.
check "  devknowledge is on by profile default" "1" \
  "$(sed -n 's/^devknowledge=//p' "$H/.agents/.bootstrap-manifest")"
check "  and google-developer-knowledge is registered" "http" \
  "$(jq -r '.mcpServers["google-developer-knowledge"].type' "$H/.claude.json" 2>/dev/null)"
rm -rf "$H"

# The default is claude-cloud-sandbox's alone. Codex does not read
# ~/.claude.json, so its profile must not write one.
H=$(mktemp -d)
HOME="$H" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox \
  --no-gcloud --no-precommit --no-hooks --no-terraform >"$H/run.log" 2>&1
check "codex-cloud-sandbox leaves devknowledge off" "0" \
  "$(sed -n 's/^devknowledge=//p' "$H/.agents/.bootstrap-manifest")"
check "  and writes no ~/.claude.json" "0" \
  "$([ -f "$H/.claude.json" ] && echo 1 || echo 0)"
rm -rf "$H"

# --- 6b. one resolved commit per run (#610) --------------------------------
#
# The run resolves its ref to a sha before the first fetch, and a branch or tag
# run whose own copy differs from the sha-addressed one hands over to that copy
# exactly once. BOOTSTRAP_REEXEC is the guard, and it is set for every other
# case in this file so that a full run here tests the copy under test rather
# than whatever the branch carries on the remote.
H=$(mktemp -d)
mkdir -p "$H/stub"
cat >"$H/stub/git" <<EOF
#!/bin/sh
# Fails the one subcommand the resolution uses and passes the rest through.
[ "\${1:-}" = ls-remote ] && exit 128
exec $(command -v git) "\$@"
EOF
chmod +x "$H/stub/git"
HOME="$H" PATH="$H/stub:$PATH" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" \
  --no-gcloud --no-precommit --no-hooks --no-terraform >"$H/run.log" 2>&1
check "an unresolvable ref still completes the run" "0" "$?"
check "  and the manifest says unresolved" "ref_kind=unresolved sha=unresolved" \
  "$(sed -n -e 's/^\(ref_kind=.*\)$/\1/p' -e 's/^\(sha=.*\)$/\1/p' "$H/.agents/.bootstrap-manifest" | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$H"

# A sha-addressed copy that differs from the running one is handed the original
# arguments. The "fresh" copy here is a marker, so nothing else of the run
# happens; RAW is the harness seam that points the self-check at it.
H=$(mktemp -d)
mkdir -p "$H/raw/cloud"
cat >"$H/raw/cloud/bootstrap.sh" <<'EOF'
#!/bin/sh
echo "REEXEC-RAN guard=${BOOTSTRAP_REEXEC:+set} args=$*"
EOF
(
  unset BOOTSTRAP_REEXEC
  HOME="$H" RAW="file://$H/raw" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" \
    --no-gcloud --no-precommit --profile codex-cloud-sandbox
) >"$H/run.log" 2>&1
check "a stale copy re-runs the sha-addressed one once" "1" "$(count '^REEXEC-RAN ' "$H/run.log")"
check "  with the guard set, so the next run cannot re-exec again" "1" \
  "$(count '^REEXEC-RAN guard=set ' "$H/run.log")"
check "  and with the original arguments, in order" "1" \
  "$(count "args=$BOOTSTRAP_TEST_REF --no-gcloud --no-precommit --profile codex-cloud-sandbox\$" "$H/run.log")"
check "  and says so" "1" "$(count 're-running' "$H/run.log")"

# With the guard already set the same difference is ignored.
(
  BOOTSTRAP_REEXEC=1
  export BOOTSTRAP_REEXEC
  HOME="$H" RAW="file://$H/raw" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" \
    --no-gcloud --no-precommit --profile codex-cloud-sandbox
) >"$H/guarded.log" 2>&1
check "a run that was already handed over does not re-exec" "0" \
  "$(count 'REEXEC-RAN\|re-running' "$H/guarded.log")"
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
  -e 's#if command -v gh *> */dev/null 2>&1; then#if false; then#' \
  "$BOOTSTRAP_FULL" >"$H/bootstrap.sh"
# The pattern tolerates both spellings of the redirect (`> /dev/null` and
# shfmt's `>/dev/null`): a pattern that stops matching neutralises nothing,
# and this count would then report 0 for the wrong reason.
check "the gh fixture neutered the already-present guard" "0" \
  "$(count 'if command -v gh *> */dev/null 2>&1; then' "$H/bootstrap.sh")"
HOME="$H" sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --with-gh --no-gcloud --no-precommit --no-hooks \
  >"$LOG" 2>&1
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
cur=$(HOME="$H" "$GATHER" 2>/dev/null \
  | sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
check "gather emits a degraded= line" "degraded=gh" \
  "$(printf '%s\n' "$cur" | sed -n 's/^\(degraded=.*\)$/\1/p')"
check "  and does NOT report state=failed" "0" \
  "$(printf '%s\n' "$cur" | grep -c 'state=failed')"
rm -rf "$H"

# --- 7a. terraform= is the outcome, not the request (#738) -------------------
#
# Terraform installs partway through cap_precommit. A precommit capability that
# dies before that step must not leave the manifest claiming terraform=1. The
# block is extracted from the script itself, so a rename shows up here as an
# extraction failure, not as a test that quietly passes.
H=$(mktemp -d)
sed -n '/^terraform_outcome() {/,/^fi$/p' "$BOOTSTRAP" >"$H/fn.sh"
# shellcheck disable=SC2016 # the $(...) is a literal the grep matches
check "the terraform outcome block was extractable" "1" \
  "$(count '^TERRAFORM_OUTCOME=\$(terraform_outcome)$' "$H/fn.sh")"
# tf_case <with_terraform> <with_precommit> <marker:0|1> -> "<outcome>|<degraded>"
tf_case() {
  rm -f "$H/terraform-installed"
  [ "$3" -eq 0 ] || : >"$H/terraform-installed"
  TMP="$H" WITH_TERRAFORM="$1" WITH_PRECOMMIT="$2" DEGRADED="${4:-}" \
    sh -c '. "$1"; echo "$TERRAFORM_OUTCOME|$DEGRADED"' _ "$H/fn.sh"
}
check "precommit aborted before terraform: terraform=0, degraded names it" \
  "0|precommit terraform" "$(tf_case 1 1 0 precommit)"
check "terraform installed: terraform=1, nothing added" "1|" "$(tf_case 1 1 1)"
check "pc_terraform already named it: not named twice" \
  "0|precommit.terraform" "$(tf_case 1 1 0 precommit.terraform)"
check "--no-terraform: terraform=0, not degraded" "0|" "$(tf_case 0 1 0)"
check "--no-precommit installs nothing, by design: not degraded" "0|" "$(tf_case 1 0 0)"
# The marker must be written by the step it attests to, after the install.
# shellcheck disable=SC2016 # $TMP is a literal the grep matches
check "cap_precommit writes the marker right after the terraform step" "1" \
  "$(sed -n '/step_end precommit.terraform$/,/terraform-installed"$/p' "$BOOTSTRAP" \
    | grep -c ': >"\$TMP/terraform-installed"$')"
rm -rf "$H"

# --- 7c. --toolchain=background: the setup run defers the toolchain (#631) ---
#
# The setup phase installs the toolkit and the git hook, installs no pre-commit
# tool, and leaves what toolchain-start needs to re-run this script at the same
# sha. The deferred run itself installs the real toolchain, which is minutes of
# downloads, so tests/toolchain-start-test.sh covers the launcher and the
# hook's waiting against a fake run instead.
H=$(mktemp -d)
HOME="$H" sh "$BOOTSTRAP_FULL" "$BOOTSTRAP_TEST_REF" --toolchain=background \
  --no-gcloud --no-hooks --no-gh --no-devknowledge >"$H/run.log" 2>&1
check "a background-mode setup run succeeds" "0" "$?"
M="$H/.agents/.bootstrap-manifest"
TCD="$H/.agents/toolchain"
check "  status ok and nothing degraded" "ok|" \
  "$(sed -n 's/^status=//p' "$M")|$(sed -n 's/^degraded=//p' "$M")"
check "  the manifest says the toolchain was deferred" "background" \
  "$(sed -n 's/^toolchain=//p' "$M")"
check "  terraform is deferred, not claimed and not degraded" "deferred" \
  "$(sed -n 's/^terraform=//p' "$M")"
check "  no pre-commit tool was installed by this run" "0" \
  "$(sed -n 's/^timings=//p' "$M" | tr ' ' '\n' | grep -c '^precommit')"
check "  the deferred run is pending" "pending" "$(cat "$TCD/state" 2>/dev/null)"
check "  its launcher and script are in place" "1 1" \
  "$([ -x "$TCD/start" ] && echo 1 || echo 0) $([ -s "$TCD/bootstrap.sh" ] && echo 1 || echo 0)"
check "  args start with a resolved sha and end in --toolchain=run" "1 --toolchain=run" \
  "$(head -1 "$TCD/args" | grep -c '^[0-9a-f]\{40\}$') $(tail -1 "$TCD/args")"
check "  the git hook is installed, pointing at the toolchain dir" "1" \
  "$(count "$TCD" "$H/.config/git/hooks/pre-commit")"
check "  and core.hooksPath points at it" "$H/.config/git/hooks" \
  "$(HOME="$H" git config --global core.hooksPath)"
check "  the launcher reports pending" "pending" \
  "$(TOOLCHAIN_DIR="$TCD" sh "$TCD/start" --status)"
rm -rf "$H"

# --- 7d. background mode shims tools that are not installed yet (#751) -----
#
# cap_shims skips a tool that is not on PATH, which in background mode is
# every deferred tool. They must be shimmed anyway, so the shim can wait for
# the install and record blocked_ms. Eager mode is unchanged. fetch and
# install are stubbed, so this needs no network.
H=$(mktemp -d)
sed -n '/^cap_shims() {/,/^}$/p' "$BOOTSTRAP" >"$H/fn.sh"
check "cap_shims was extractable" "1" "$(count '^cap_shims() {' "$H/fn.sh")"
# shims_for <mode>: the tools cap_shims shimmed, with not-yet-installed absent from PATH.
shims_for() {
  rm -rf "$H/claude"
  mkdir -p "$H/claude/bin"
  TOOLCHAIN="$1" CLAUDE_DIR="$H/claude" TMP="$H" RAW=x REF=x \
    SHIM_TOOLS="not-yet-installed sh" sh -c '
      log() { :; }; die() { exit 1; }
      fetch() { printf "#!/bin/sh\n" >"$2"; }
      . "$1"; cap_shims' _ "$H/fn.sh"
  find "$H/claude/bin/shims" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null \
    | sort | tr '\n' ' ' | sed 's/ $//'
}
check "background mode shims a tool that is not installed yet" \
  "not-yet-installed sh" "$(shims_for background)"
check "eager mode still shims only installed tools" "sh" "$(shims_for eager)"
rm -rf "$H"

# --- 7b. sha256_is: a digest pin that can refuse ----------------------------
#
# hadolint and trivy are installed only when their download matches a pinned
# digest, so the check has to be able to say no.
echo
echo "cloud/bootstrap.sh — sha256_is"
H=$(mktemp -d)
sed -n '/^sha256_is() {/,/^}$/p' "$BOOTSTRAP" >"$H/fn.sh"
check "sha256_is was extractable from the script" "1" "$(count '^sha256_is() {' "$H/fn.sh")"
printf 'payload\n' >"$H/f"
_good=$(sha256sum "$H/f" | cut -d' ' -f1)
check "  accepts the file's own digest" "0" \
  "$(sh -c '. "$1"; sha256_is "$2" "$3"; echo $?' _ "$H/fn.sh" "$H/f" "$_good")"
check "  refuses a different digest" "1" \
  "$(sh -c '. "$1"; sha256_is "$2" "$3"; echo $?' _ "$H/fn.sh" "$H/f" "0000$_good")"
check "  refuses a missing file" "1" \
  "$(sh -c '. "$1"; sha256_is "$2" "$3"; echo $?' _ "$H/fn.sh" "$H/nope" "$_good")"
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

# gitleaks and actionlint stay in the set through their `-system` ids, which
# build nothing (#609). The plain ids are `language: golang` and compile from
# source, ~30 s each, so one creeping back in is the regression to catch.
for r in gitleaks actionlint; do
  check "  lists $r" "1" "$(count "/$r\$" "$WARM_YAML")"
  check "  as $r-system, not the golang id" "1 0" \
    "$(count "id: $r-system\$" "$WARM_YAML") $(count "id: $r\$" "$WARM_YAML")"
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
  for fn in precommit_home warm_install cap_precommit_warm fetch now_s record_timing capability; do
    sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
  done
} >"$H/fn.sh"
for f in precommit_home warm_install cap_precommit_warm fetch capability; do
  check "$f was extractable from the script" "1" "$(count "^$f() {" "$H/fn.sh")"
done

# The harness the extracted functions expect. `die` is the real contract --
# write the reason where capability() reads it, then leave the subshell.
cat >"$H/harness.sh" <<'HARNESS'
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
cat >"$H/raw/cloud/precommit-warm.yaml" <<'CFG'
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
if command -v pre-commit >/dev/null 2>&1; then
  mkdir -p "$H/t8b" "$H/notarepo" "$H/cache"
  # A planted checkout for mechanism 2, under the cwd because $PWD is one of
  # the roots the scan walks. It goes there rather than under a redirected
  # $HOME -- which would be the more obvious way to bound the scan -- because
  # HOME is where Python resolves its user site-packages from, and a
  # `pip install --user pre-commit` (what a non-root CI runner gets) stops
  # being importable the moment HOME moves. That failure is instant and its
  # message is about a missing module, which reads as a broken warm rather
  # than a broken test.
  mkdir -p "$H/notarepo/repo-a"
  git -C "$H/notarepo/repo-a" init -q 2>/dev/null
  cp "$H/raw/cloud/precommit-warm.yaml" "$H/notarepo/repo-a/.pre-commit-config.yaml"

  log8b="$H/t8b.log"
  # WARM_ROOTS bounds the scan to the planted checkout. Without it the scan
  # also walks /home/user and $HOME, and a container holding five clones fills
  # the warm's 5-checkout cap before it reaches repo-a.
  (cd "$H/notarepo" && TMP="$H/t8b" FAIL_FILE="$H/t8b.fail" RAW="file://$H/raw" \
    REF=test FNS="$H/fn.sh" PRE_COMMIT_HOME="$H/cache" WARM_ROOTS="$H/notarepo" \
    sh -c '. "$0"; cap_precommit_warm' "$H/harness.sh") >"$log8b" 2>&1
  warm_rc=$?
  check "a warm from a non-checkout cwd succeeds" "0" "$warm_rc"
  # What the warm said, when it did not work. Without this the whole section
  # reports six expected-1-actual-0 lines and nothing about the cause, which
  # is a CI failure that has to be reproduced before it can be read.
  if [ "$warm_rc" -ne 0 ]; then
    printf '        --- warm output ---\n'
    sed 's/^/        /' "$log8b"
  fi
  if grep -q 'more than 5 checkouts found' "$log8b"; then
    printf '        the warm hit its 5-checkout cap: %s\n' \
      "$(grep 'more than 5 checkouts found' "$log8b" | head -1)"
  fi
  check "  it warmed the estate hook set" "1" \
    "$(count 'warm    -> estate hook set' "$log8b")"
  check "  and the checkout it found in the workspace" "1" \
    "$(count 'warm    -> .*repo-a/.pre-commit-config.yaml' "$log8b")"
  # Per-repo timing: the estate set built pre-commit-hooks from an empty
  # cache, so it is timed along with the clone before it. repo-a uses the same
  # config, finds it cached, and so adds nothing.
  check "  the hook repo it built is timed" "1" \
    "$(count '^warm\.pre-commit-hooks=[0-9][0-9]*s$' "$H/t8b/step-timings")"
  check "  as is the clone before the first build" "1" \
    "$(count '^warm\.clone=[0-9][0-9]*s$' "$H/t8b/step-timings")"
  check "  and a cached checkout adds no entries" "0" \
    "$(count '^warm\.repo-a\.' "$H/t8b/step-timings")"

  # The acceptance criterion this file exists to hold: cache present after the
  # bootstrap, asserted from the cache rather than inferred from an exit code.
  envs=$(find "$H/cache" -maxdepth 1 -type d -name 'repo*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${envs:-0}" -gt 0 ]; then
    ok "the cache really holds a hook environment ($envs)"
  else
    no "the cache really holds a hook environment"
  fi
  # And the same number reaches the manifest, through the file that carries it
  # out of capability()'s subshell.
  check "  the count reaches the manifest field" "$envs" \
    "$(cat "$H/t8b/warm-envs" 2>/dev/null || echo missing)"

  # A hook that runs without building anything is the whole point.
  (cd "$H/notarepo/repo-a" && PRE_COMMIT_HOME="$H/cache" \
    pre-commit run --all-files) >"$H/t8b-run.log" 2>&1 || true
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
cat >"$H/t8c-run.sh" <<'RUN'
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

# --- 8c'. per-tool timings survive the capability subshell -------------------
#
# step_end writes to a file because the capability's own variables die with
# its subshell; capability() has to fold that file into TIMINGS, after the
# capability's own entry, and empty it for the next one.
{
  for fn in now_s record_timing step_begin step_end capability; do
    sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
  done
} >"$H/fn-steps.sh"
mkdir -p "$H/t8e"
cat >"$H/t8e-run.sh" <<'RUN'
set -eu
log() { :; }
TIMINGS=
DEGRADED=
FAIL_FILE="$TMP/fail-reason"
. "$FNS"
fake_cap() {
    step_begin
    step_end fake.one
    PIP_ATTEMPT=2
    STEP_ROUTE=uv
    step_end fake.two
    step_end fake.three
}
capability 1 fake fake_cap
capability 1 other true
echo "timings=$TIMINGS"
RUN
out=$(TMP="$H/t8e" FNS="$H/fn-steps.sh" sh "$H/t8e-run.sh" 2>&1)
check "step timings are folded in after the capability's own entry" \
  "timings=fake=0s fake.one=0s fake.two=0s fake.two.pip-attempt=2 fake.two.route=uv fake.three=0s other=0s" \
  "$(printf '%s\n' "$out" | sed 's/=[0-9]*s/=0s/g' | grep '^timings=')"

# --- 8c''. one pre-commit tool failing costs that tool, not the gate (#631) -----
#
# pc_tool isolates each tool in its own subshell; precommit_retry tries the
# failures once more after the other capabilities; what still fails is named
# precommit.<tool>. The fakes: one fails for good, one fails only the first
# time (a stall that clears), and the tool after them must still install.
{
  for fn in now_s record_timing step_begin step_end capability pc_tool precommit_retry die; do
    sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
  done
} >"$H/fn-pc.sh"
check "pc_tool and precommit_retry were extractable" "2" \
  "$(grep -c '^pc_tool() {\|^precommit_retry() {' "$H/fn-pc.sh")"
mkdir -p "$H/t8f"
cat >"$H/t8f-run.sh" <<'RUN'
set -eu
log() { :; }
TOOLCHAIN=eager
TIMINGS=
DEGRADED=
FAIL_FILE="$TMP/fail-reason"
. "$FNS"
pc_dead() { die "could not download dead"; }
pc_flaky() {
  [ -f "$TMP/flaky-seen" ] || { : >"$TMP/flaky-seen"; die "stalled"; }
  step_end precommit.flaky
}
pc_after() { : >"$TMP/after-ran"; step_end precommit.after; }
fake_precommit() {
  pc_tool dead pc_dead
  pc_tool flaky pc_flaky
  pc_tool after pc_after
}
capability 1 precommit fake_precommit
precommit_retry
echo "SURVIVED"
echo "degraded=$DEGRADED"
echo "timings=$TIMINGS"
echo "after=$([ -f "$TMP/after-ran" ] && echo ran || echo skipped)"
RUN
out=$(TMP="$H/t8f" FNS="$H/fn-pc.sh" sh "$H/t8f-run.sh" 2>&1)
check "a failing tool does not end the run" "1" \
  "$(printf '%s\n' "$out" | grep -c '^SURVIVED$')"
check "  the tool after it still installs" "after=ran" \
  "$(printf '%s\n' "$out" | grep '^after=')"
check "  only the tool that failed twice is degraded" "degraded=precommit.dead" \
  "$(printf '%s\n' "$out" | grep '^degraded=')"
check "  the capability itself is not degraded" "0" \
  "$(printf '%s\n' "$out" | grep '^degraded=' | grep -c 'precommit\( \|$\)')"
check "  first attempts, retries and the capability are each timed" \
  "timings=precommit=0s precommit.dead=0s precommit.flaky=0s precommit.after=0s precommit.dead.retry=0s precommit.flaky.retry=0s" \
  "$(printf '%s\n' "$out" | sed 's/=[0-9]*s/=0s/g' | grep '^timings=')"

# The deferred run (--toolchain=run) retries up to three rounds, with growing
# gaps. sleep is stubbed to record the gaps instead of waiting them out.
cat >"$H/t8g-run.sh" <<'RUN'
set -eu
log() { :; }
sleep() { GAPS="${GAPS:+$GAPS }$1"; }
TOOLCHAIN=run
TIMINGS=
DEGRADED=
GAPS=
FAIL_FILE="$TMP/fail-reason"
. "$FNS"
pc_dead() { die "could not download dead"; }
fake_precommit() { pc_tool dead pc_dead; }
capability 1 precommit fake_precommit
precommit_retry
echo "degraded=$DEGRADED"
echo "gaps=$GAPS"
echo "timings=$TIMINGS"
RUN
mkdir -p "$H/t8g"
out=$(TMP="$H/t8g" FNS="$H/fn-pc.sh" sh "$H/t8g-run.sh" 2>&1)
check "the deferred run retries three rounds, 30, 60 and 120 s apart" "gaps=30 60 120" \
  "$(printf '%s\n' "$out" | grep '^gaps=')"
check "  each attempt has its own timing key" \
  "timings=precommit=0s precommit.dead=0s precommit.dead.retry=0s precommit.dead.retry2=0s precommit.dead.retry3=0s" \
  "$(printf '%s\n' "$out" | sed 's/=[0-9]*s/=0s/g' | grep '^timings=')"
check "  and a tool that never installs is still degraded" "degraded=precommit.dead" \
  "$(printf '%s\n' "$out" | grep '^degraded=')"

# --- 8d. the core.hooksPath claim cloud/README.md now makes ----------------
#
# Not about the warm, but about the mechanism it rides on, and the estate now
# depends on the distinction: `pre-commit install` REFUSES under
# core.hooksPath and exits 1, while `install-hooks` is unaffected. A repo-side
# SessionStart hook that calls the first under `set -e` fails session start in
# exactly the containers the bootstrap got right, so the two have to be called
# separately (#441). It is third-party behaviour, which is why it is asserted
# here rather than trusted to stay true.
if command -v pre-commit >/dev/null 2>&1; then
  mkdir -p "$H/hp/repo" "$H/hp/hooks"
  git -C "$H/hp/repo" init -q 2>/dev/null
  git -C "$H/hp/repo" config core.hooksPath "$H/hp/hooks"
  cp "$H/raw/cloud/precommit-warm.yaml" "$H/hp/repo/.pre-commit-config.yaml"

  (cd "$H/hp/repo" && pre-commit install) >"$H/hp/install.log" 2>&1
  check "pre-commit install refuses under core.hooksPath" "1" "$?"
  check "  in the words the README quotes" "1" \
    "$(count 'Cowardly refusing to install hooks' "$H/hp/install.log")"

  # The other half, and the reason the warm can use it safely: exit 0, and no
  # hook written anywhere. The cache from §8b covers this config already, so
  # this builds nothing.
  (cd "$H/hp/repo" && PRE_COMMIT_HOME="$H/cache" pre-commit install-hooks) \
    >"$H/hp/install-hooks.log" 2>&1
  check "install-hooks is unaffected by it" "0" "$?"
  check "  and writes no hook" "0" \
    "$(find "$H/hp/hooks" -type f 2>/dev/null | wc -l | tr -d ' ')"
fi

# The doc half of the same criterion: the README used to say `pre-commit
# install` "will warn that it is being overridden", which is wrong in the way
# that matters -- a warning is survivable and a non-zero exit is not.
check "cloud/README.md documents the refusal, not a warning" "1" \
  "$(count 'Cowardly refusing to install hooks' "$ROOT/cloud/README.md")"
check "  and no longer calls it a warning" "0" \
  "$(count 'will warn that it is being overridden' "$ROOT/cloud/README.md")"
rm -rf "$H"

# --- 9. --with-devknowledge: one key in ~/.claude.json, nothing else ---------
#
# The invariant: registering the Developer Knowledge MCP server edits exactly
# mcpServers."google-developer-knowledge" and carries everything else in
# ~/.claude.json through untouched -- that file holds account state, and a
# sandbox's other user-scope servers are not this flag's business (#439). It
# writes no key and no header: the environment's API credential supplies it.
echo
echo "cloud/bootstrap.sh — --with-devknowledge"

command -v jq >/dev/null 2>&1 || no "jq is not on PATH — the devknowledge assertions cannot run"

H=$(mktemp -d)
{
  for fn in cap_devknowledge now_s record_timing capability; do
    sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
  done
} >"$H/fn.sh"
check "cap_devknowledge was extractable from the script" "1" \
  "$(count '^cap_devknowledge() {' "$H/fn.sh")"

cat >"$H/harness.sh" <<'HARNESS'
set -eu
log() { echo "[bootstrap] $*"; }
die() {
    if [ -n "${FAIL_FILE:-}" ]; then echo "$*" > "$FAIL_FILE" 2> /dev/null || true; fi
    echo "[bootstrap] error: $*" >&2
    exit 1
}
DEGRADED=
TIMINGS=
. "$FNS"
FAIL_FILE="$TMP/fail-reason"
capability 1 devknowledge cap_devknowledge
echo "SURVIVED"
echo "degraded=$DEGRADED"
HARNESS

run_dk() { # run_dk <home> -- runs the capability through capability(), as the bootstrap does
  mkdir -p "$1/tmp"
  HOME="$1" TMP="$1/tmp" FNS="$H/fn.sh" sh "$H/harness.sh" 2>&1
}
dk_entry='.mcpServers["google-developer-knowledge"]'
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# 9a. No ~/.claude.json yet: created, holding only the one server, 0600.
mkdir -p "$H/a"
out=$(run_dk "$H/a")
check "no ~/.claude.json: the capability succeeds" "degraded=" \
  "$(printf '%s\n' "$out" | grep '^degraded=')"
check "  the entry is type http at the MCP URL" \
  '{"type":"http","url":"https://developerknowledge.googleapis.com/mcp"}' \
  "$(jq -c "$dk_entry" "$H/a/.claude.json" 2>/dev/null)"
check "  and carries no headers, so no key" "null" \
  "$(jq -c "$dk_entry.headers" "$H/a/.claude.json" 2>/dev/null)"
check "  the file is created 0600" "600" "$(file_mode "$H/a/.claude.json")"

# 9b. An existing file: every other key and server survives.
mkdir -p "$H/b"
cat >"$H/b/.claude.json" <<'JSON'
{"userID": "u-123", "oauthAccount": {"emailAddress": "x@example.com"},
 "mcpServers": {"other-server": {"type": "stdio", "command": "other"}},
 "projects": {"/repo": {"mcpServers": {"local-one": {"type": "http", "url": "https://l"}}}}}
JSON
chmod 600 "$H/b/.claude.json"
before=$(jq -S -c "del($dk_entry)" "$H/b/.claude.json")
run_dk "$H/b" >/dev/null
check "existing file: everything but the new entry is unchanged" "$before" \
  "$(jq -S -c "del($dk_entry)" "$H/b/.claude.json" 2>/dev/null)"
check "  the other user-scope server is still there" "other" \
  "$(jq -r '.mcpServers["other-server"].command' "$H/b/.claude.json" 2>/dev/null)"
check "  and the new one was added" "http" \
  "$(jq -r "$dk_entry.type" "$H/b/.claude.json" 2>/dev/null)"
check "  the file stays 0600" "600" "$(file_mode "$H/b/.claude.json")"

# 9c. Idempotent: a second run changes nothing.
once=$(jq -S -c . "$H/b/.claude.json")
run_dk "$H/b" >/dev/null
check "a re-run leaves the file equivalent" "$once" \
  "$(jq -S -c . "$H/b/.claude.json" 2>/dev/null)"
check "  still exactly two user-scope servers" "2" \
  "$(jq '.mcpServers | length' "$H/b/.claude.json" 2>/dev/null)"

# 9d. A file that is not a JSON object is left alone, and the run degrades
# rather than dying. Replacing it would throw away whatever it held.
for bad in 'not json at all' '["an", "array"]'; do
  mkdir -p "$H/d"
  printf '%s\n' "$bad" >"$H/d/.claude.json"
  out=$(run_dk "$H/d")
  check "unusable ~/.claude.json ($bad): the run survives" "1" \
    "$(printf '%s\n' "$out" | grep -c '^SURVIVED$')"
  check "  it names itself in degraded=" "degraded=devknowledge" \
    "$(printf '%s\n' "$out" | grep '^degraded=')"
  check "  and the file is untouched" "$bad" "$(cat "$H/d/.claude.json")"
  check "  with no temp file left beside it" "0" \
    "$(find "$H/d" -maxdepth 1 -name '.claude.json.bootstrap-tmp' | wc -l | tr -d ' ')"
  rm -rf "$H/d"
done

# 9e. The flag parses. A trailing unknown argument makes the run die in the
# argument loop -- the earliest failure there is -- so the reason it records
# says which argument was rejected. Were --with-devknowledge unknown, it would
# be the one named.
mkdir -p "$H/e"
HOME="$H/e" sh "$BOOTSTRAP" "$BOOTSTRAP_TEST_REF" --with-devknowledge --no-devknowledge \
  --a-flag-that-does-not-exist >/dev/null 2>&1
check "--with-devknowledge and --no-devknowledge are accepted arguments" \
  "failed_step=unknown argument: --a-flag-that-does-not-exist" \
  "$(grep '^failed_step=' "$H/e/.agents/.bootstrap-manifest" 2>/dev/null)"

rm -rf "$H"

# --- 10. golangci-lint: unconditional, replaces an old copy, keeps a current one
echo
echo "cloud/bootstrap.sh — golangci-lint"

# Unconditional in every run that installs the toolchain: eager, and the
# deferred run. Only a background setup run, which defers it, skips it.
# shellcheck disable=SC2016 # $TC_TOOLS is a literal the grep matches
check "golangci-lint is installed unconditionally" "1" \
  "$(count '^capability "\$TC_TOOLS" golangci cap_golangci$' "$BOOTSTRAP")"
check "  and the full runs above really did skip it" "1" \
  "$(count '^capability 0 golangci cap_golangci$' "$BOOTSTRAP_FULL")"
check "  the manifest records its version" "1" \
  "$(count 'echo "golangci=' "$BOOTSTRAP")"

# Extracted and run against stubs, so no case downloads anything or writes
# /usr/local/bin. fetch always fails: reaching it at all is the signal that an
# install was attempted, and its failure has to come back as a die.
H=$(mktemp -d)
mkdir -p "$H/stub"
{
  sed -n '/^GCL_VER=/p' "$BOOTSTRAP"
  for fn in golangci_ver cap_golangci; do
    sed -n "/^$fn() {/,/^}\$/p" "$BOOTSTRAP"
  done
  cat <<'FNS'
log() { :; }
die() { echo "$*" > "$DIEF"; exit 1; }
fetch() { echo "$1" >> "$LOGF"; return 1; }
FNS
} >"$H/fn.sh"
check "cap_golangci was extractable from the script" "1" \
  "$(grep -c '^cap_golangci() {' "$H/fn.sh")"
GCL_PIN=$(sed -n 's/^GCL_VER=//p' "$H/fn.sh")

gcl_run() {
  # gcl_run <stubbed --version line, or "" for no golangci-lint on PATH>
  rm -f "$H/stub/golangci-lint" "$H/calls.log" "$H/die"
  if [ -n "$1" ]; then
    printf '#!/bin/sh\necho "%s"\n' "$1" >"$H/stub/golangci-lint"
    chmod +x "$H/stub/golangci-lint"
  fi
  # PATH leaves out /usr/local/bin, where a real copy may live.
  PATH="$H/stub:/usr/bin:/bin" LOGF="$H/calls.log" DIEF="$H/die" TMP="$H" \
    sh -c '. "$0/fn.sh"; cap_golangci' "$H" >/dev/null 2>&1
}

printf '#!/bin/sh\necho "golangci-lint has version 2.5.0 built with go1.25.1 from ff63786c on 2025-09-21T19:04:05Z"\n' \
  >"$H/stub/golangci-lint"
chmod +x "$H/stub/golangci-lint"
check "golangci_ver reads the image's version line" "2.5.0" \
  "$(PATH="$H/stub:/usr/bin:/bin" sh -c '. "$0/fn.sh"; golangci_ver' "$H")"

gcl_run "golangci-lint has version 2.5.0 built with go1.25.1 from ff63786c on 2025-09-21T19:04:05Z"
check "an older copy is replaced: the install fails as a die" "1" "$?"
check "  having fetched the pinned release" "1" \
  "$(count "/download/v${GCL_PIN}/golangci-lint-${GCL_PIN}-linux-amd64.tar.gz\$" "$H/calls.log")"
check "  and the reason names the version" "could not download golangci-lint ${GCL_PIN}" \
  "$(cat "$H/die" 2>/dev/null)"

gcl_run ""
check "a missing copy is installed" "1" "$(count 'golangci-lint' "$H/calls.log")"

gcl_run "golangci-lint has version ${GCL_PIN} built with go1.27.0 from 114493f9 on 2026-09-24T11:07:15Z"
check "a copy at the pin is left alone" "0" "$?"
check "  without a download" "0" "$(count 'golangci-lint' "$H/calls.log")"

gcl_run "golangci-lint has version v99.0.0 built with go1.30.0"
check "a newer copy is left alone, not walked backwards" "0" "$?"
check "  without a download" "0" "$(count 'golangci-lint' "$H/calls.log")"
rm -rf "$H"

# --- 11. where binaries go: one decision, every install follows it ---------
#
# The invariant: an unprivileged run installs everything it can under one
# prefix, reports status=ok rather than degraded for it, and records the bin
# dir -- while a run that can write the system paths lands exactly where it
# always did (#573). Codex Cloud's runner is the unprivileged case.
#
# Root cannot be made to fail `[ -w ]`, so "unprivileged" is simulated by
# rewriting the two SYSTEM_ lines in a copy to a path that does not exist (or,
# for the system case, to one the test owns). Those two lines are the only
# place the script names a system path, which 11a holds it to -- so the
# rewrite moves every install, and the shipped script carries no test seam.
echo
echo "cloud/bootstrap.sh — where binaries go"

# 11a. No install names a system path except through the decision.
stray=$(grep -nE '(^|[ "=])(/usr/local/bin|/opt)([/" ]|$)' "$BOOTSTRAP" \
  | grep -vE '^[0-9]+:[[:space:]]*#' \
  | grep -vE '^[0-9]+:SYSTEM_(BIN|OPT)=')
check "no install hard-codes /usr/local/bin or /opt" "" "$stray"
check "  the two SYSTEM_ lines are the decision's only inputs" "2" \
  "$(count '^SYSTEM_\(BIN\|OPT\)=' "$BOOTSTRAP")"

# with_system <bin> <opt> <src> <dest> -- a copy whose system paths are moved.
with_system() {
  sed -e "s#^SYSTEM_BIN=.*#SYSTEM_BIN=$1#" -e "s#^SYSTEM_OPT=.*#SYSTEM_OPT=$2#" "$3" >"$4"
}
mval() { sed -n "s/^$1=//p" "$2" 2>/dev/null; }

# 11b. System paths unwritable, no --prefix: $HOME/.local, and said so.
H=$(mktemp -d)
with_system "$H/sys/bin" "$H/sys/opt" "$BOOTSTRAP_FULL" "$H/bootstrap.sh"
check "the fixture moved the system paths" "1" "$(count "^SYSTEM_BIN=$H/sys/bin\$" "$H/bootstrap.sh")"
HOME="$H" sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --no-gcloud --no-precommit --no-hooks \
  --no-devknowledge >"$H/run.log" 2>&1
check "unwritable system paths: the run succeeds" "0" "$?"
M="$H/.agents/.bootstrap-manifest"
check "  install_mode=user" "user" "$(mval install_mode "$M")"
check "  bin_dir is \$HOME/.local/bin" "$H/.local/bin" "$(mval bin_dir "$M")"
check "  the helper landed there" "1" \
  "$([ -x "$H/.local/bin/gcp-credentials" ] && echo 1 || echo 0)"
check "  bin_dir_on_path=no is recorded" "no" "$(mval bin_dir_on_path "$M")"
check "  and the log says so loudly" "1" "$(count 'is NOT on PATH' "$H/run.log")"
check "  nothing was created at the system paths" "0" \
  "$([ -e "$H/sys" ] && echo 1 || echo 0)"
rm -rf "$H"

# 11c. System paths writable: the system layout, unchanged. The paths are the
# test's own, so this holds as root and as a CI runner's user alike.
H=$(mktemp -d)
mkdir -p "$H/sys/bin" "$H/sys/opt"
with_system "$H/sys/bin" "$H/sys/opt" "$BOOTSTRAP_FULL" "$H/bootstrap.sh"
HOME="$H" PATH="$H/sys/bin:$PATH" sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" \
  --no-gcloud --no-precommit --no-hooks --no-devknowledge >"$H/run.log" 2>&1
check "writable system paths: the run succeeds" "0" "$?"
M="$H/.agents/.bootstrap-manifest"
check "  install_mode=system" "system" "$(mval install_mode "$M")"
check "  the helper is in the system bin" "1" \
  "$([ -x "$H/sys/bin/gcp-credentials" ] && echo 1 || echo 0)"
check "  and not in \$HOME/.local/bin" "0" \
  "$([ -e "$H/.local/bin/gcp-credentials" ] && echo 1 || echo 0)"
check "  bin_dir_on_path=yes, and no warning" "yes 0" \
  "$(mval bin_dir_on_path "$M") $(count 'NOT on PATH' "$H/run.log")"
rm -rf "$H"

# 11d. The unprivileged Codex shape end to end: --prefix, every capability the
# codex profile turns on plus gh and golangci-lint, nothing pre-installed.
#
# Downloads come from file:// fixtures laid out at each release URL's path, so
# the real fetch, unpack and install code runs against a stand-in archive. PATH
# is a farm of the base utilities only, so no image copy of terraform or
# pre-commit short-circuits an install. npm and uv are stubs that do what the
# real ones do with the flags they are given (npm --prefix, UV_TOOL_BIN_DIR),
# and log those flags -- the flags are this script's half of the contract.
H=$(mktemp -d)
FIX="$H/fix"
pin() { sed -n "s/^[[:space:]]*$1=\([0-9.]*\)\$/\1/p" "$BOOTSTRAP" | head -1; }
AL=$(pin AL_VER) SC=$(pin SC_VER) TF=$(pin TF_VER) TFL=$(pin TFL_VER)
TFG=$(pin TFL_GOOGLE_VER) GHV=$(pin GH_VER) GCL=$(pin GCL_VER) GL=$(pin GL_VER)
HL=$(pin HL_VER) TV=$(pin TV_VER)
check "every pin the fixture needs was found" "10" \
  "$(printf '%s\n' "$AL" "$SC" "$TF" "$TFL" "$TFG" "$GHV" "$GCL" "$GL" "$HL" "$TV" | grep -c .)"

fake() { # fake <path> <version line>
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "%s"\n' "$2" >"$1"
  chmod +x "$1"
}
S="$H/stage"
fake "$S/al/actionlint" "actionlint $AL"
mkdir -p "$FIX/github.com/rhysd/actionlint/releases/download/v$AL"
tar -czf "$FIX/github.com/rhysd/actionlint/releases/download/v$AL/actionlint_${AL}_linux_amd64.tar.gz" -C "$S/al" actionlint
fake "$S/gl/gitleaks" "$GL"
mkdir -p "$FIX/github.com/gitleaks/gitleaks/releases/download/v$GL"
tar -czf "$FIX/github.com/gitleaks/gitleaks/releases/download/v$GL/gitleaks_${GL}_linux_x64.tar.gz" -C "$S/gl" gitleaks
# hadolint and trivy are digest-pinned, so the fixture's own digests replace
# the real ones in the rewritten script below.
mkdir -p "$FIX/github.com/hadolint/hadolint/releases/download/v$HL"
fake "$FIX/github.com/hadolint/hadolint/releases/download/v$HL/hadolint-linux-x86_64" "Haskell Dockerfile Linter $HL"
HL_FIX_SHA=$(sha256sum "$FIX/github.com/hadolint/hadolint/releases/download/v$HL/hadolint-linux-x86_64" | cut -d' ' -f1)
fake "$S/tv/trivy" "Version: $TV"
mkdir -p "$FIX/github.com/aquasecurity/trivy/releases/download/v$TV"
tar -czf "$FIX/github.com/aquasecurity/trivy/releases/download/v$TV/trivy_${TV}_Linux-64bit.tar.gz" -C "$S/tv" trivy
TV_FIX_SHA=$(sha256sum "$FIX/github.com/aquasecurity/trivy/releases/download/v$TV/trivy_${TV}_Linux-64bit.tar.gz" | cut -d' ' -f1)
fake "$S/sc/shellcheck-v$SC/shellcheck" "ShellCheck $SC"
mkdir -p "$FIX/github.com/koalaman/shellcheck/releases/download/v$SC"
tar -cJf "$FIX/github.com/koalaman/shellcheck/releases/download/v$SC/shellcheck-v$SC.linux.x86_64.tar.xz" -C "$S/sc" "shellcheck-v$SC/shellcheck"
fake "$S/tf/terraform" "Terraform v$TF"
mkdir -p "$FIX/releases.hashicorp.com/terraform/$TF"
zip -q -j "$FIX/releases.hashicorp.com/terraform/$TF/terraform_${TF}_linux_amd64.zip" "$S/tf/terraform"
fake "$S/tfl/tflint" "TFLint version $TFL"
mkdir -p "$FIX/github.com/terraform-linters/tflint/releases/download/v$TFL"
zip -q -j "$FIX/github.com/terraform-linters/tflint/releases/download/v$TFL/tflint_linux_amd64.zip" "$S/tfl/tflint"
fake "$S/tfg/tflint-ruleset-google" "ruleset $TFG"
mkdir -p "$FIX/github.com/terraform-linters/tflint-ruleset-google/releases/download/v$TFG"
zip -q -j "$FIX/github.com/terraform-linters/tflint-ruleset-google/releases/download/v$TFG/tflint-ruleset-google_linux_amd64.zip" "$S/tfg/tflint-ruleset-google"
fake "$S/gh/gh_${GHV}_linux_amd64/bin/gh" "gh version $GHV"
mkdir -p "$FIX/github.com/cli/cli/releases/download/v$GHV"
tar -czf "$FIX/github.com/cli/cli/releases/download/v$GHV/gh_${GHV}_linux_amd64.tar.gz" -C "$S/gh" "gh_${GHV}_linux_amd64/bin/gh"
fake "$S/gcl/golangci-lint-$GCL-linux-amd64/golangci-lint" "golangci-lint has version $GCL built with go1.27.0"
mkdir -p "$FIX/github.com/golangci/golangci-lint/releases/download/v$GCL"
tar -czf "$FIX/github.com/golangci/golangci-lint/releases/download/v$GCL/golangci-lint-$GCL-linux-amd64.tar.gz" -C "$S/gcl" "golangci-lint-$GCL-linux-amd64/golangci-lint"
fake "$S/gc/google-cloud-sdk/bin/gcloud" "Google Cloud SDK 999.0.0 (fixture)"
fake "$S/gc/google-cloud-sdk/bin/gsutil" "gsutil fixture"
fake "$S/gc/google-cloud-sdk/install.sh" "fixture install.sh"
mkdir -p "$FIX/dl.google.com/dl/cloudsdk/channels/rapid/downloads"
tar -czf "$FIX/dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz" -C "$S/gc" google-cloud-sdk

# The farm: base utilities by symlink, plus the two stubs. A tool absent from
# this host is skipped; the run then fails loudly on it, which is the signal.
FARM="$H/farm"
mkdir -p "$FARM"
for t in sh cat cp mv rm ln mkdir chmod install mktemp date sed awk grep head tail \
  cut tr wc sort dirname basename find env stat tar gzip xz unzip curl git jq \
  id uname tee touch readlink ls true false sha256sum; do
  _p=$(real_tool "$t") && ln -s "$_p" "$FARM/$t"
done

# Controls for real_tool (#708): it skips a shim, and it still reports a tool
# that is genuinely absent rather than falling back to the shim.
_rt_d=$(mktemp -d)
mkdir -p "$_rt_d/shims" "$_rt_d/bin"
printf '#!/bin/sh\nexit 0\n' >"$_rt_d/agent-shim"
chmod +x "$_rt_d/agent-shim"
ln -s ../agent-shim "$_rt_d/shims/faketool"
if [ "$(real_tool faketool "$_rt_d/shims" || echo none)" = none ]; then
  ok "real_tool: a PATH holding only a shim has no real tool"
else
  no "real_tool: returned a shim as the real tool"
fi
printf '#!/bin/sh\nexit 0\n' >"$_rt_d/bin/faketool"
chmod +x "$_rt_d/bin/faketool"
if [ "$(real_tool faketool "$_rt_d/shims:$_rt_d/bin")" = "$_rt_d/bin/faketool" ]; then
  ok "real_tool: skips the shim and finds the real binary behind it"
else
  no "real_tool: did not skip the shim"
fi
rm -rf "$_rt_d"
cat >"$FARM/npm" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG/npm.log"
prefix= pkg=
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) shift; prefix="$1" ;;
        -*) ;;
        *) pkg="$1" ;;
    esac
    shift
done
[ -n "$prefix" ] || exit 1
name=${pkg%@*}
mkdir -p "$prefix/bin"
printf '#!/bin/sh\necho "%s fixture"\n' "$name" > "$prefix/bin/$name"
chmod +x "$prefix/bin/$name"
STUB
cat >"$FARM/uv" <<'STUB'
#!/bin/sh
echo "$3 UV_TOOL_DIR=${UV_TOOL_DIR:-} UV_TOOL_BIN_DIR=${UV_TOOL_BIN_DIR:-} UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR:-}" >> "$STUB_LOG/uv.log"
[ "$1 $2" = "tool install" ] && [ -n "${UV_TOOL_BIN_DIR:-}" ] || exit 1
mkdir -p "$UV_TOOL_BIN_DIR"
if [ "$3" = pre-commit ]; then
    # install-hooks has to leave a hook environment, or the warm reports
    # that it cached nothing.
    printf '#!/bin/sh\ncase "$1" in\n  install-hooks) mkdir -p "$PRE_COMMIT_HOME/repofixture" ;;\n  *) echo "pre-commit 9.9.9" ;;\nesac\n' \
        > "$UV_TOOL_BIN_DIR/pre-commit"
else
    printf '#!/bin/sh\necho "%s fixture"\n' "$3" > "$UV_TOOL_BIN_DIR/$3"
fi
chmod +x "$UV_TOOL_BIN_DIR/$3"
STUB
chmod +x "$FARM/npm" "$FARM/uv"

# golangci-lint included: the unmodified script, not BOOTSTRAP_FULL.
with_system "$H/sys/bin" "$H/sys/opt" "$BOOTSTRAP" "$H/bs-sys.sh"
sed -e "s#https://github.com/\([^\"]*\)/releases/download/#file://$FIX/github.com/\1/releases/download/#g" \
  -e "s#https://releases.hashicorp.com/#file://$FIX/releases.hashicorp.com/#g" \
  -e "s#https://dl.google.com/#file://$FIX/dl.google.com/#g" \
  -e "s#^\([[:space:]]*\)HL_SHA256=.*#\1HL_SHA256=$HL_FIX_SHA#" \
  -e "s#^\([[:space:]]*\)TV_SHA256=.*#\1TV_SHA256=$TV_FIX_SHA#" \
  "$H/bs-sys.sh" >"$H/bootstrap.sh"
check "the fixture rewrote every release download" "0" \
  "$(grep -cE 'https://(github.com/[^ ]*/releases/download|releases.hashicorp.com|dl.google.com)/' "$H/bootstrap.sh")"

P="$H/tools"
mkdir -p "$H/home" "$H/cwd"
(cd "$H/cwd" && HOME="$H/home" PATH="$FARM" STUB_LOG="$H" PRE_COMMIT_HOME="$H/pc-cache" \
  sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox --with-gh \
  --prefix "$P") >"$H/run.log" 2>&1
p_rc=$?
check "an unprivileged --prefix run succeeds" "0" "$p_rc"
M="$H/home/.agents/.bootstrap-manifest"
check "  status=ok, not degraded" "ok" "$(mval status "$M")"
check "  with nothing degraded" "" "$(mval degraded "$M")"
if [ "$(mval status "$M")" != ok ]; then
  printf '        --- run log (tail) ---\n'
  tail -25 "$H/run.log" | sed 's/^/        /'
fi
check "  install_mode=prefix" "prefix" "$(mval install_mode "$M")"
check "  bin_dir is the prefix's bin" "$P/bin" "$(mval bin_dir "$M")"
check "  bin_dir_on_path=no is recorded" "no" "$(mval bin_dir_on_path "$M")"
missing=
for t in gcp-credentials gcloud gsutil shellcheck actionlint gitleaks hadolint trivy markdownlint-cli2 cspell \
  semgrep terraform tflint checkov pre-commit gh golangci-lint; do
  [ -x "$P/bin/$t" ] || missing="$missing $t"
done
check "  every command landed in the prefix's bin" "" "$missing"
check "  the gcloud SDK is under the prefix" "1" \
  "$([ -x "$P/opt/google-cloud-sdk/bin/gcloud" ] && echo 1 || echo 0)"
check "  the wrapper execs the prefix's SDK" "2" \
  "$(count "$P/opt/google-cloud-sdk/bin/gcloud \"\$@\"" "$P/bin/gcloud")"
check "  and still strips the preset token for a broker grant" "1" \
  "$(count 'exec env -u CLOUDSDK_AUTH_ACCESS_TOKEN' "$P/bin/gcloud")"
check "  the wrapper runs the SDK it names" "Google Cloud SDK 999.0.0 (fixture)" \
  "$(HOME="$H/home" PATH="$FARM" "$P/bin/gcloud" --version 2>/dev/null)"
# The wrapper takes every gcloud prompt's default, because an agent has no tty
# to answer one (#652). Probed through a copy that points at a stub SDK which
# reports the variable it was handed, so what is asserted is what gcloud sees.
mkdir -p "$H/probe-sdk/bin"
# shellcheck disable=SC2016 # the stub must expand it, not this shell
printf '#!/bin/sh\necho "prompts=${CLOUDSDK_CORE_DISABLE_PROMPTS-unset}"\n' >"$H/probe-sdk/bin/gcloud"
chmod +x "$H/probe-sdk/bin/gcloud"
sed "s#$P/opt/google-cloud-sdk#$H/probe-sdk#g" "$P/bin/gcloud" >"$H/probe-gcloud"
chmod +x "$H/probe-gcloud"
check "  the wrapper copy really points at the probe SDK" "0" \
  "$(count "$P/opt/google-cloud-sdk" "$H/probe-gcloud")"
check "  gcloud prompts default to disabled" "prompts=1" \
  "$(HOME="$H/home" PATH="$FARM" "$H/probe-gcloud" 2>/dev/null)"
check "  and a caller can still turn them back on" "prompts=0" \
  "$(HOME="$H/home" PATH="$FARM" CLOUDSDK_CORE_DISABLE_PROMPTS=0 "$H/probe-gcloud" 2>/dev/null)"
# Negative control: without the export the probe must read "unset", or the
# assertions above could be passing for any reason at all.
grep -v 'CLOUDSDK_CORE_DISABLE_PROMPTS' "$H/probe-gcloud" >"$H/probe-gcloud-bare"
chmod +x "$H/probe-gcloud-bare"
check "  control: a wrapper without the export leaves it unset" "prompts=unset" \
  "$(HOME="$H/home" PATH="$FARM" "$H/probe-gcloud-bare" 2>/dev/null)"
check "  uv installed all three Python tools" "3" "$(count . "$H/uv.log")"
check "  each with its tools and Python under the prefix" "3" \
  "$(count "UV_TOOL_DIR=$P/share/uv/tools UV_TOOL_BIN_DIR=$P/bin UV_PYTHON_INSTALL_DIR=$P/share/uv/python\$" "$H/uv.log")"
check "  both npm installs were given the prefix" "2 2" \
  "$(count . "$H/npm.log") $(count "prefix $P " "$H/npm.log")"
check "  an explicit prefix beats the \$HOME/.local default" "0" \
  "$([ -e "$H/home/.local/bin" ] && echo 1 || echo 0)"

# And start-session tells the session its tools are off PATH.
cur=$(HOME="$H/home" "$GATHER" 2>/dev/null \
  | sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
check "gather names a bin dir that is off this session's PATH" "bin_dir_off_path=$P/bin" \
  "$(printf '%s\n' "$cur" | grep '^bin_dir_off_path=')"
cur=$(HOME="$H/home" PATH="$P/bin:$PATH" "$GATHER" 2>/dev/null \
  | sed -n '/^===bootstrap_currency/,/^===[a-z]/p')
check "  and is silent once it is on PATH" "0" \
  "$(printf '%s\n' "$cur" | grep -c '^bin_dir_off_path=')"

# An image that already ships gcloud, as a symlink in the very bin dir the
# wrapper is written to. The SDK must be wrapped rather than skipped, and the
# wrapper must not be written through the symlink into the SDK's own gcloud.
Q="$H/preinstalled"
mkdir -p "$Q/sdk" "$Q/bin" "$H/home2" "$H/cwd2"
cp -R "$S/gc/google-cloud-sdk" "$Q/sdk/"
ln -s "$Q/sdk/google-cloud-sdk/bin/gcloud" "$Q/bin/gcloud"
(cd "$H/cwd2" && HOME="$H/home2" PATH="$Q/bin:$FARM" STUB_LOG="$H" PRE_COMMIT_HOME="$H/pc-cache" \
  sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox \
  --no-precommit --no-hooks --no-terraform --no-devknowledge --prefix "$Q") >"$H/run2.log" 2>&1
check "a preinstalled gcloud run succeeds" "0" "$?"
check "  gcloud is not degraded" "" "$(mval degraded "$H/home2/.agents/.bootstrap-manifest")"
check "  the image's symlink was replaced by the wrapper" "0 1" \
  "$([ -L "$Q/bin/gcloud" ] && echo 1 || echo 0) $(count '^# Installed by agentic-coding-config cloud/bootstrap.sh' "$Q/bin/gcloud")"
check "  the wrapper execs the preinstalled SDK" "2" \
  "$(count "$Q/sdk/google-cloud-sdk/bin/gcloud \"\$@\"" "$Q/bin/gcloud")"
check "  the SDK's own gcloud was not overwritten" "0" \
  "$(count 'Installed by agentic-coding-config' "$Q/sdk/google-cloud-sdk/bin/gcloud")"
check "  nothing was downloaded into the prefix" "0" \
  "$([ -e "$Q/opt/google-cloud-sdk" ] && echo 1 || echo 0)"
check "  the wrapper runs the SDK it names" "Google Cloud SDK 999.0.0 (fixture)" \
  "$(HOME="$H/home2" PATH="$FARM" "$Q/bin/gcloud" --version 2>/dev/null)"
# A second run finds its own wrapper and keeps the SDK it points at.
(cd "$H/cwd2" && HOME="$H/home2" PATH="$Q/bin:$FARM" STUB_LOG="$H" PRE_COMMIT_HOME="$H/pc-cache" \
  sh "$H/bootstrap.sh" "$BOOTSTRAP_TEST_REF" --profile codex-cloud-sandbox \
  --no-precommit --no-hooks --no-terraform --no-devknowledge --prefix "$Q") >"$H/run3.log" 2>&1
check "  a re-run still wraps the same SDK" "2" \
  "$(count "$Q/sdk/google-cloud-sdk/bin/gcloud \"\$@\"" "$Q/bin/gcloud")"
if [ "$FAIL" -gt 0 ]; then
  printf '        --- preinstalled run log (tail) ---\n'
  tail -25 "$H/run2.log" | sed 's/^/        /'
fi
rm -rf "$H"

# --- 12. a read-only $HOME degrades the run, it does not kill it (#575) ----
#
# Codex Cloud runs a task with $HOME and the root filesystem read-only. The
# run used to die at its first `mkdir ~/.claude`, in Tier 1, so no tool was
# installed and no manifest was written. A root user cannot be stopped by a
# mode bit, so for root the read-only home is a read-only tmpfs inside a
# private mount namespace; anyone else is simply chmod'ed out of it.
ro_run() {
  # ro_run <dir> <script> -- runs the bootstrap with <dir>/home read-only.
  _d="$1"
  _s="$2"
  mkdir -p "$_d/home" "$_d/prefix"
  : >"$_d/run.sh"
  if [ "$(id -u)" -eq 0 ]; then
    command -v unshare >/dev/null 2>&1 || return 97
    printf 'mount -t tmpfs tmpfs "%s" && mount -o remount,ro "%s" || exit 99\n' \
      "$_d/home" "$_d/home" >>"$_d/run.sh"
  else
    chmod 555 "$_d/home"
  fi
  {
    printf 'if touch "%s/.probe" 2>/dev/null; then exit 98; fi\n' "$_d/home"
    printf 'HOME="%s" BOOTSTRAP_REEXEC=1 sh "%s" "%s" \\\n' "$_d/home" "$_s" "$BOOTSTRAP_TEST_REF"
    printf '  --profile codex-cloud-sandbox --prefix "%s" \\\n' "$_d/prefix"
    printf '  --no-gcloud --no-precommit --no-hooks --no-terraform --no-devknowledge\n'
  } >>"$_d/run.sh"
  if [ "$(id -u)" -eq 0 ]; then
    unshare -m sh "$_d/run.sh" >"$_d/run.log" 2>&1
  else
    sh "$_d/run.sh" >"$_d/run.log" 2>&1
  fi
}

H=$(mktemp -d)
ro_run "$H" "$BOOTSTRAP_FULL"
rc=$?
# 97-99 mean the environment could not make a read-only home, which says
# nothing about the bootstrap -- and a skipped case that reads as a pass is the
# failure this test exists to prevent.
case "$rc" in
  97 | 98 | 99) no "could not make a read-only HOME here (rc=$rc)" ;;
  *)
    M="$H/prefix/.agent-state/agents/.bootstrap-manifest"
    check "a read-only HOME does not abort the run" "0" "$rc"
    check "  tools still install under the prefix" "1" \
      "$([ -x "$H/prefix/bin/gcp-credentials" ] && echo 1 || echo 0)"
    check "  the manifest is written under the prefix" "1" \
      "$([ -f "$M" ] && echo 1 || echo 0)"
    check "  status is degraded, never ok" "degraded" "$(sed -n 's/^status=//p' "$M")"
    check "  and names what is missing" "policy-and-skills:home-read-only" \
      "$(sed -n 's/^degraded=//p' "$M")"
    check "  and records the policy outcome with its reason" \
      "policy=not-installed reason=home-read-only" "$(grep '^policy=' "$M")"
    check "  and claims no skills it did not install" "" "$(sed -n 's/^skills=//p' "$M")"
    check "  the session scripts relocate with it" "1" \
      "$([ -x "$H/prefix/.agent-state/claude/bin/start-session-gather-state" ] && echo 1 || echo 0)"
    check "  nothing was written to HOME" "0" \
      "$(find "$H/home" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
    ;;
esac
rm -rf "$H"

# Negative control: the same run with the probe forced to answer "writable" is
# the script as it stood before the fix, and it must fail -- otherwise the
# assertions above could be passing for any reason at all.
H=$(mktemp -d)
sed 's/^  HOME_RW=no$/  HOME_RW=yes/' "$BOOTSTRAP_FULL" >"$H/defeated.sh"
check "the control really defeats the probe" "1" "$([ -n "$(diff "$BOOTSTRAP_FULL" "$H/defeated.sh")" ] && echo 1 || echo 0)"
ro_run "$H" "$H/defeated.sh"
rc=$?
check "without the probe, a read-only HOME still fails the run" "1" "$([ "$rc" -ne 0 ] && [ "$rc" -lt 97 ] && echo 1 || echo 0)"
rm -rf "$H"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
