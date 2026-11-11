#!/bin/sh
# toolchain-start and the git hook that waits on it (#631): the deferred
# toolchain starts once, restarts when its process died, and a commit that
# arrives before it finishes waits or fails loudly, never passes unchecked.
#
# The deferred run is faked: a bootstrap.sh that records each launch, sleeps,
# and writes the outcome the case asks for. The git hook is extracted from
# cloud/bootstrap.sh itself, so the test runs the text that ships.
#
# Usage: sh tests/toolchain-start-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
START="$ROOT/home/bin/toolchain-start"
PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  printf '  ok    %s\n' "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1"
}
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else
    bad "$1"
    printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
  fi
}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# fixture <name> <sleep> <outcome>: a toolchain dir whose fake run sleeps and
# then writes <outcome> to the state file.
fixture() {
  _d="$W/$1"
  mkdir -p "$_d"
  printf '%s\n' 0123abcd --toolchain=run >"$_d/args"
  cat >"$_d/bootstrap.sh" <<EOF
echo launched >>"$_d/launches"
sleep $2
echo $3 >"$_d/state.tmp" && mv -f "$_d/state.tmp" "$_d/state"
EOF
  echo pending >"$_d/state"
  cp "$START" "$_d/start"
  chmod +x "$_d/start"
  echo "$_d"
}
launches() { grep -c launched "$1/launches" 2>/dev/null || echo 0; }
# The launcher returns as soon as it has forked, so the detached fake run may
# not have written its first line yet. Give it up to 3 s.
await_launch() {
  _i=0
  while [ "$(launches "$1")" -lt 1 ] && [ "$_i" -lt 30 ]; do
    sleep 0.1
    _i=$((_i + 1))
  done
}

echo "toolchain-start"

# Nothing deferred: every mode is a silent no-op.
D="$W/none"
mkdir -p "$D"
check "no args file: --status says none" "none" "$(TOOLCHAIN_DIR=$D sh "$START" --status)"
out=$(printf '{"x":1}' | TOOLCHAIN_DIR=$D sh "$START" --hook 2>&1)
check "no args file: --hook prints nothing and exits 0" "0:" "$?:$out"
check "no args file: --wait returns at once" "0" "$(TOOLCHAIN_DIR=$D sh "$START" --wait 5)"

# pending -> one launch, and --wait sees it finish.
D=$(fixture ok 1 "done")
out=$(printf '{}' | TOOLCHAIN_DIR=$D sh "$START" --hook 2>&1)
check "--hook prints nothing and exits 0" "0:" "$?:$out"
await_launch "$D"
check "--hook launched the deferred run once" "1" "$(launches "$D")"
check "  and the state says running while it runs" "running" "$(TOOLCHAIN_DIR=$D sh "$START" --status)"
TOOLCHAIN_DIR=$D sh "$START" --hook </dev/null
check "a second --hook while it runs does not launch again" "1" "$(launches "$D")"
TOOLCHAIN_DIR=$D sh "$START" --wait 10 >/dev/null
check "--wait returns 0 once the run is done" "0" "$?"
check "  and the run was still launched only once" "1" "$(launches "$D")"
TOOLCHAIN_DIR=$D sh "$START" --hook </dev/null
check "a finished install is never relaunched" "1" "$(launches "$D")"

# running with a dead pid: reported as dead, and restarted.
D=$(fixture dead 0 "done")
echo running >"$D/state"
sh -c 'exit 0' &
echo "$!" >"$D/pid"
wait
check "running with a dead pid reads as dead" "dead" "$(TOOLCHAIN_DIR=$D sh "$START" --status)"
TOOLCHAIN_DIR=$D sh "$START" --wait 10 >/dev/null
check "a dead run is restarted, and --wait then succeeds" "0:1" "$?:$(launches "$D")"

# failed and degraded outcomes.
D=$(fixture failed 0 failed)
TOOLCHAIN_DIR=$D sh "$START" --wait 10 >/dev/null
check "--wait exits 1 when the run failed" "1" "$?"
D=$(fixture degraded 0 degraded)
TOOLCHAIN_DIR=$D sh "$START" --wait 10 >/dev/null
check "--wait exits 0 when the run finished degraded" "0" "$?"

# Still running at the deadline.
D=$(fixture slow 30 "done")
TOOLCHAIN_DIR=$D sh "$START" --wait 1 >/dev/null
check "--wait exits 2 when the run is still going at the deadline" "2" "$?"
kill "$(cat "$D/pid")" 2>/dev/null || true

# A lock left by a starter that died is broken after 30 s, not obeyed forever.
D=$(fixture stale 0 "done")
mkdir "$D/lock"
touch -d '@1' "$D/lock" 2>/dev/null || touch -t 197001010000 "$D/lock"
TOOLCHAIN_DIR=$D sh "$START" --wait 10 >/dev/null
check "a stale start lock is broken" "0:1" "$?:$(launches "$D")"

echo
echo "the global git hook (extracted from cloud/bootstrap.sh)"

HOOK="$W/pre-commit-hook"
sed -n "/<<'HOOK'\$/,/^HOOK\$/p" "$ROOT/cloud/bootstrap.sh" | sed '1d;$d' \
  | sed "s#@TOOLCHAIN_DIR@#$W/hook-default#g" >"$HOOK"
check "the hook was extractable" "1" "$(grep -c '^exec pre-commit run --hook-stage pre-commit$' "$HOOK")"

REPO="$W/repo"
mkdir -p "$REPO"
: >"$REPO/.pre-commit-config.yaml"
# A PATH with no pre-commit on it, so the hook's own decisions are what is tested.
NOPC="$W/nopc"
mkdir -p "$NOPC"
for t in sh cat date sleep mkdir rmdir stat kill grep sed nohup setsid dirname rm readlink mv; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NOPC/$t"
done

D=$(fixture hookslow 30 "done")
out=$(cd "$REPO" && TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=1 PATH=$NOPC sh "$HOOK" 2>&1)
rc=$?
check "a commit during the install is stopped, not passed" "1" "$rc"
check "  and says it was NOT checked" "1" "$(printf '%s\n' "$out" | grep -c 'NOT checked')"
kill "$(cat "$D/pid")" 2>/dev/null || true

D=$(fixture hookdone 0 "done")
out=$(cd "$REPO" && TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=10 PATH=$NOPC sh "$HOOK" 2>&1)
check "install done but pre-commit absent: the commit is reported NOT CHECKED" "0:1" \
  "$?:$(printf '%s\n' "$out" | grep -c 'NOT CHECKED')"

# A session's PATH puts the toolchain shims first, and they include
# pre-commit. A shim with nothing behind it must not count as an install.
SHIMS="$W/shims"
mkdir -p "$SHIMS"
ln -sf "$ROOT/home/bin/agent-shim" "$W/agent-shim"
ln -sf ../agent-shim "$SHIMS/pre-commit"
out=$(cd "$REPO" && TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=10 PATH=$SHIMS:$NOPC sh "$HOOK" 2>&1)
check "a pre-commit shim with nothing behind it is reported NOT CHECKED, not run" "0:1" \
  "$?:$(printf '%s\n' "$out" | grep -c 'NOT CHECKED')"

# With a real pre-commit behind the shim, the hook runs it, through the shim.
REALPC="$W/realpc"
mkdir -p "$REALPC"
printf '#!/bin/sh\necho "real pre-commit ran: $*"\n' >"$REALPC/pre-commit"
chmod +x "$REALPC/pre-commit"
out=$(cd "$REPO" && HOME="$W/home" TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=10 PATH=$SHIMS:$REALPC:$NOPC sh "$HOOK" 2>&1)
check "a real pre-commit behind the shim is run" "0:1" \
  "$?:$(printf '%s\n' "$out" | grep -c 'real pre-commit ran: run --hook-stage pre-commit')"

out=$(cd "$REPO" && TOOLCHAIN_DIR=$W/none PATH=$NOPC sh "$HOOK" 2>&1)
check "nothing deferred and no pre-commit: silent, as before" "0:" "$?:$out"

out=$(cd "$W" && TOOLCHAIN_DIR=$D PATH=$NOPC sh "$HOOK" 2>&1)
check "a repo with no pre-commit config is left alone" "0:" "$?:$out"

echo
echo "agent-shim: a tool not installed yet waits for the deferred install"

# The fake run installs the tool after a second, then reports done. The shim
# must wait for it rather than fail as absent, then run the real tool. A
# recording helper beside the shim dir captures the blocked_ms it reports.
D=$(fixture shimwait 1 "done")
LATE="$W/late-bin"
mkdir -p "$LATE"
printf '#!/bin/sh\necho "latetool ran: $*"\n' >"$W/latetool.src"
{
  echo "echo launched >>\"$D/launches\""
  echo "sleep 1"
  echo "cp \"$W/latetool.src\" \"$LATE/latetool\""
  echo "chmod +x \"$LATE/latetool\""
  echo "echo done >\"$D/state.tmp\" && mv -f \"$D/state.tmp\" \"$D/state\""
} >"$D/bootstrap.sh"
SB="$W/shimbin"
mkdir -p "$SB/shims"
cp "$ROOT/home/bin/agent-shim" "$SB/agent-shim"
ln -sf ../agent-shim "$SB/shims/latetool"
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$W/telemetry.log" >"$SB/agent-telemetry"
chmod +x "$SB/agent-shim" "$SB/agent-telemetry"
out=$(HOME="$W/home" TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=10 PATH="$SB/shims:$LATE:$PATH" \
  "$SB/shims/latetool" hello 2>&1)
check "a shimmed tool installed late runs once the install is done" "0:1" \
  "$?:$(printf '%s\n' "$out" | grep -c '^latetool ran: hello$')"
check "  and said it was waiting" "1" \
  "$(printf '%s\n' "$out" | grep -c 'waiting for the background toolchain install')"
i=0
while [ ! -s "$W/telemetry.log" ] && [ "$i" -lt 30 ]; do
  sleep 0.1
  i=$((i + 1))
done
bms=$(sed -n 's/.*blocked_ms=\([0-9]*\).*/\1/p' "$W/telemetry.log" | head -1)
check "  and recorded a non-zero blocked_ms" "1" "$([ "${bms:-0}" -gt 0 ] && echo 1 || echo 0)"

D=$(fixture shimnever 0 degraded)
out=$(HOME="$W/home" TOOLCHAIN_DIR=$D TOOLCHAIN_WAIT_S=10 PATH="$SB/shims:$PATH" \
  "$SB/shims/latetool" 2>&1)
check "a tool the finished install never provided exits 127 and says so" "127:1" \
  "$?:$(printf '%s\n' "$out" | grep -c 'not installed: the background toolchain install has not provided it')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
