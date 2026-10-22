#!/bin/sh
# Behaviour tests for home/bin/wsl-mnt-guard-claude-hook.
#
# A SessionStart hook in the settings.json every surface reads, so both halves
# matter: on WSL with a cwd under /mnt/<drive> it must speak, and everywhere
# else -- macOS, a cloud sandbox, WSL's own filesystem -- it must print nothing,
# because its stdout lands in the agent's context on every session start.
# Every case must also exit 0: a failing SessionStart hook is a session that
# starts with an error.
#
# The kernel-identity file is faked through WSL_MNT_GUARD_PROC_VERSION, so the
# WSL branch runs on any machine, and the speaking cases double as the
# negative control for every silent one.
#
# Usage: sh tests/wsl-mnt-guard-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/wsl-mnt-guard-claude-hook"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

printf '%s\n' 'Linux version 6.18.40-microsoft-standard-WSL2 (root@x) #1 SMP' > "$WORK/wsl"
printf '%s\n' 'Linux version 6.8.0-45-generic (buildd@lcy02) #45-Ubuntu SMP' > "$WORK/ubuntu"

# run <proc-version-file> <payload> [PATH] -- prints "<exit>:<said|silent>".
run() {
    if [ -n "${3:-}" ]; then
        printf '%s' "$2" | env PATH="$3" WSL_MNT_GUARD_PROC_VERSION="$1" /bin/sh "$HOOK" > "$WORK/out" 2>&1
    else
        printf '%s' "$2" | env WSL_MNT_GUARD_PROC_VERSION="$1" sh "$HOOK" > "$WORK/out" 2>&1
    fi
    _rc=$?
    if [ -s "$WORK/out" ]; then echo "$_rc:said"; else echo "$_rc:silent"; fi
}

# expect <label> <want> <proc> <payload> [PATH]
expect() {
    _got=$(run "$3" "$4" "${5:-}")
    if [ "$_got" = "$2" ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-48s -> %s\n' "$1" "$_got"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-48s -> %s (want %s)\n' "$1" "$_got" "$2"
    fi
}

cwd() { printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$1"; }

echo "--- on WSL, a cwd on the Windows host speaks ---"
expect "under /mnt/c"                   0:said   "$WORK/wsl" "$(cwd /mnt/c/Users/p/dev/repo)"
expect "another drive letter"           0:said   "$WORK/wsl" "$(cwd /mnt/d/work)"
expect "the drive root itself"          0:said   "$WORK/wsl" "$(cwd /mnt/c)"

run "$WORK/wsl" "$(cwd /mnt/c/Users/p/dev/repo)" > /dev/null
if grep -q 'started in /mnt/c/Users/p/dev/repo' "$WORK/out"; then
    PASS=$((PASS + 1)); echo "ok    the message names the directory"
else
    FAIL=$((FAIL + 1)); echo "FAIL  the message names the directory"
fi

echo "--- on WSL, its own filesystem is silent ---"
expect "under ~/dev"                    0:silent "$WORK/wsl" "$(cwd /home/p/dev/repo)"
expect "/mnt/wsl is not a drive"        0:silent "$WORK/wsl" "$(cwd /mnt/wsl/shared)"
expect "a drive path not at the root"   0:silent "$WORK/wsl" "$(cwd /home/p/mnt/c/x)"

echo "--- off WSL it is a no-op, even for a /mnt/c cwd ---"
expect "plain Ubuntu kernel"            0:silent "$WORK/ubuntu" "$(cwd /mnt/c/x)"
expect "no /proc/version (macOS)"       0:silent "$WORK/absent" "$(cwd /mnt/c/x)"

echo "--- fail-open: nothing it cannot read stops a session ---"
expect "empty payload"                  0:silent "$WORK/wsl" ""
expect "payload is not JSON"            0:silent "$WORK/wsl" "not json"
expect "payload has no cwd"             0:silent "$WORK/wsl" '{"hook_event_name":"SessionStart"}'

# A PATH holding grep and nothing else: no jq to find.
mkdir -p "$WORK/nojq"
ln -s "$(command -v grep)" "$WORK/nojq/grep"
expect "no jq on PATH"                  0:silent "$WORK/wsl" "$(cwd /mnt/c/x)" "$WORK/nojq"
# The control: the same stripped PATH plus jq speaks, so the silence above is
# jq's absence and not a PATH too bare to run anything.
mkdir -p "$WORK/withjq"
ln -s "$(command -v grep)" "$WORK/withjq/grep"
ln -s "$(command -v jq)" "$WORK/withjq/jq"
expect "same PATH plus jq (control)"    0:said   "$WORK/wsl" "$(cwd /mnt/c/x)" "$WORK/withjq"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
