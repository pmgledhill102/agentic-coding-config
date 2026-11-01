#!/bin/sh
# The bootstrap-absent SessionStart hook (.claude/hooks/bootstrap-absent-check.sh,
# #545): it speaks exactly when a cloud container has neither the bootstrap
# manifest nor ~/.claude/bin, and never fails or prints anything it read.
#
# Usage: sh tests/bootstrap-absent-hook-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/.claude/hooks/bootstrap-absent-check.sh"
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

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# run <remote> <home>: output, then the exit code on the last line.
run() {
  printf '{}' | env -i HOME="$2" CLAUDE_CODE_REMOTE="$1" sh "$HOOK"
  echo "rc=$?"
}

check() { # check <description> <remote> <home> <speaks yes|no>
  _out=$(run "$2" "$3")
  case $_out in *"rc=0") ;; *)
    bad "$1: exit was not 0"
    return
    ;;
  esac
  case $_out in
    *WARNING*) _spoke=yes ;;
    *) _spoke=no ;;
  esac
  if [ "$_spoke" = "$4" ]; then ok "$1"; else bad "$1 (spoke=$_spoke, wanted $4)"; fi
}

mkdir -p "$W/bare" "$W/manifest/.agents" "$W/bin/.claude/bin" "$W/failed/.agents"
: >"$W/manifest/.agents/.bootstrap-manifest"
printf 'status=failed\n' >"$W/failed/.agents/.bootstrap-manifest"

check "cloud, nothing installed: warns" true "$W/bare" yes
check "cloud, manifest present: silent" true "$W/manifest" no
check "cloud, failed-run manifest present: silent (the banner covers it)" true "$W/failed" no
check "cloud, ~/.claude/bin present: silent" true "$W/bin" no
check "not a cloud session: silent even when bare" "" "$W/bare" no
check "cloud, HOME is a missing directory: warns, does not fail" true "$W/nonexistent" yes

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
