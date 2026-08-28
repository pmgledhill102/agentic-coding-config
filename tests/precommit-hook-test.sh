#!/bin/sh
# Classification tests for home/bin/precommit-claude-hook.
#
# The hook fires on EVERY Bash call Claude makes, so what it does and does not
# classify as a commit/push is the whole of its cost. The invariant these tests
# guard: matching is not by substring, so a command merely *containing* "git
# commit" -- writing the phrase into a notes file, an issue body, this very
# file -- must not trigger a full pre-commit run (#191).
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


# --- Stage 2: a hook that could not RUN is not a finding (#335) -----------
#
# The push stage runs the whole suite --all-files, so on a surface missing an
# optional toolchain it fails hooks whose binary is simply absent. Blocking on
# that made --no-verify the ending of every push, which is how a guard stops
# being a guard.
#
# These run the hook end-to-end against a throwaway repo with `pre-commit`
# stubbed on PATH, so what is asserted is the hook's real exit code -- 2 blocks
# the tool call, 0 lets it through -- rather than a trace.

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
git init -q "$WORK/repo" || exit 1
: > "$WORK/repo/.pre-commit-config.yaml"
mkdir -p "$WORK/bin"

# run_with_stub <fixture-file> <stub-exit> -> prints "<hook exit>|<stderr>"
run_with_stub() {
    cat > "$WORK/bin/pre-commit" <<STUB
#!/bin/sh
cat "$1"
exit $2
STUB
    chmod 0755 "$WORK/bin/pre-commit"
    _err=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}\n' "$WORK/repo" |
        PATH="$WORK/bin:$PATH" sh "$HOOK" 2>&1 >/dev/null)
    _code=$?
    printf '%s|%s' "$_code" "$_err"
}

expect_push() { # label fixture stub-exit expected-code expected-stderr-grep
    got=$(run_with_stub "$2" "$3")
    code=${got%%|*}
    err=${got#*|}
    # An empty pattern asserts silence: grep finds nothing in nothing, so the
    # "hook said nothing" case cannot be expressed as a match.
    if [ -z "$5" ]; then
        _match=$([ -z "$err" ] && echo yes)
    else
        _match=$(printf '%s' "$err" | grep -q "$5" && echo yes)
    fi
    if [ "$code" = "$4" ] && [ "$_match" = yes ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-52s -> exit %s\n' "$1" "$code"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-52s -> exit %s (want %s, stderr matching "%s")\n' \
            "$1" "$code" "$4" "$5"
        printf '      stderr: %s\n' "$err"
    fi
}

cat > "$WORK/absent.txt" <<'FIXTURE'
trim trailing whitespace.................................................Passed
Terraform fmt............................................................Failed
- hook id: terraform_fmt
- exit code: 127
Neither Terraform nor OpenTofu binary could be found.
Terraform validate with tflint...........................................Failed
- hook id: terraform_tflint
- exit code: 127
Command 'tflint --init' failed: tflint: command not found
go fmt...................................................................Passed
markdownlint.............................................................Passed
FIXTURE

cat > "$WORK/real.txt" <<'FIXTURE'
trim trailing whitespace.................................................Passed
markdownlint.............................................................Failed
- hook id: markdownlint-cli2
- exit code: 1
docs/foo.md:3:1 MD009/no-trailing-spaces Trailing spaces
FIXTURE

cat > "$WORK/mixed.txt" <<'FIXTURE'
Terraform fmt............................................................Failed
- hook id: terraform_fmt
- exit code: 127
Neither Terraform nor OpenTofu binary could be found.
markdownlint.............................................................Failed
- hook id: markdownlint-cli2
- exit code: 1
docs/foo.md:3:1 MD009/no-trailing-spaces Trailing spaces
FIXTURE

cat > "$WORK/clean.txt" <<'FIXTURE'
trim trailing whitespace.................................................Passed
Terraform fmt........................................(no files to check)Skipped
markdownlint.............................................................Passed
FIXTURE

echo ""
echo "--- a missing binary is not a finding (#335) ---"
expect_push "all failures tool-absent -> allowed"   "$WORK/absent.txt" 1 0 'Not checked'
expect_push "...and names what went unchecked"      "$WORK/absent.txt" 1 0 'Terraform fmt'
expect_push "genuine finding -> still blocked"      "$WORK/real.txt"   1 2 'blocked'
expect_push "mixed -> blocked, absence reported"    "$WORK/mixed.txt"  1 2 'Not checked'
expect_push "everything passes -> silent allow"     "$WORK/clean.txt"  0 0 ''

echo ""
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
