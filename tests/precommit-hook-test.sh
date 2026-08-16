#!/bin/sh
# Classification tests for home/bin/precommit-claude-hook.
#
# The hook fires on EVERY Bash call Claude makes, so what it does and does not
# classify as a commit/push is the whole of its cost. It used to match by
# substring, which meant any command merely *containing* "git commit" -- writing
# the phrase into a notes file, an issue body, this very file -- triggered a
# full pre-commit run (#191).
#
# The hook exits 0 both when it declines to act and when the lint passes, so
# these tests observe classification indirectly: they run it in a directory
# with no .pre-commit-config.yaml, where a *classified* command reaches the
# config check and exits 0 quietly, and an unclassified one exits earlier. To
# tell those apart the hook is run with `sh -x` and its trace inspected for
# whether `stage` was ever set.
#
# Usage: sh tests/precommit-hook-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/precommit-claude-hook"

PASS=0
FAIL=0

# classify <command> -> prints the stage the hook acted on, or nothing.
#
# `stage` is assigned *before* the --no-verify escape hatch is evaluated, so the
# assignment alone does not mean the hook acted. The repo-root lookup is the
# first thing past the escape hatch, so its presence in the trace is what
# distinguishes "classified and proceeding" from "classified then bailed".
classify() {
    _trace=$(printf '{"tool_input":{"command":%s},"cwd":"%s"}\n' \
        "$(printf '%s' "$1" | jq -Rs .)" "$ROOT" | sh -x "$HOOK" 2>&1)
    printf '%s' "$_trace" | grep -q 'show-toplevel' || return 0
    printf '%s' "$_trace" | sed -n 's/^+* *stage=\(pre-[a-z]*\)$/\1/p' | tail -1
}

expect() { # label command expected
    got=$(classify "$2")
    [ -n "$got" ] || got="none"
    if [ "$got" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-52s -> %s\n' "$1" "$got"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-52s -> %s (want %s)\n' "$1" "$got" "$3"
    fi
}

echo "--- commands that should be linted ---"
expect "plain commit"            'git commit -m "x"'                       pre-commit
expect "commit after cd"         'cd /tmp && git commit -m "x"'            pre-commit
expect "commit with -C"          'git -C /tmp commit -m "x"'               pre-commit
expect "commit with -c config"   'git -c user.name=x commit -m "y"'        pre-commit
expect "plain push"              'git push -u origin main'                 pre-push
expect "push after &&"           'git add -A && git push'                  pre-push
expect "commit wins over push"   'git commit -m "x" && git push'           pre-commit
expect "semicolon separated"     'echo hi; git commit -m "x"'              pre-commit

echo "--- the #191 false trigger: a mention, not an invocation ---"
expect "phrase in echo"          'echo "run git commit later" >> notes.md' none
expect "phrase in a heredoc-ish" 'printf "%s" "git push origin main"'      none
expect "phrase in a grep"        'grep -n "git commit" docs/*.md'          none
expect "phrase in a filename"    'cat ./git-commit-notes.md'               none

echo "--- other git subcommands are not our business ---"
expect "git status"              'git status --porcelain'                  none
expect "git log"                 'git log --oneline -5'                    none
expect "git add only"            'git add -A'                              none
expect "not git at all"          'ls -la'                                  none

echo "--- escape hatch still honoured ---"
expect "commit --no-verify"      'git commit --no-verify -m "x"'           none
expect "push --no-verify"        'git push --no-verify'                    none

echo ""
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
