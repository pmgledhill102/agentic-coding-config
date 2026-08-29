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

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

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
    HOME="$1" sh "$BOOTSTRAP" main --a-flag-that-does-not-exist > /dev/null 2>&1
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
HOME="$H" sh "$BOOTSTRAP" main --profile codex-cloud-sandbox --nope > /dev/null 2>&1
if [ -f "$H/.claude/CLAUDE.md" ]; then
    no "codex profile leaves CLAUDE.md alone"
else
    ok "codex profile leaves CLAUDE.md alone"
fi
check "codex profile still gets a banner in AGENTS.md" "1" \
    "$(grep -c 'acc:bootstrap-failed:start' "$H/.agents/AGENTS.md" 2> /dev/null || echo 0)"
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

rm -f "$H/.agents/.bootstrap-manifest"
check "no manifest still means no-manifest, not failed" \
    "state=no-manifest" "$(currency "$H")"
rm -rf "$H"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
