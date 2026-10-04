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
expect "commit in a subshell"    '(git commit -m "x")'                     pre-commit
expect "push ending a subshell"  '(cd /tmp && git push)'                   pre-push

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

# --- Stage 3: lint the repo the command targets, not the payload cwd (#519) -
#
# Two fixture repos, the shape of tests/prepush-guard-test.sh: LINTED has a
# .pre-commit-config.yaml, BARE has none. The stubbed pre-commit records the
# directory it ran in, so each case asserts WHERE the lint ran (or that it did
# not), plus the exit code and stderr.

git init -q "$WORK/linted" || exit 1
: > "$WORK/linted/.pre-commit-config.yaml"
git init -q "$WORK/bare" || exit 1
LINTED=$(cd "$WORK/linted" && pwd -P)
BARE=$(cd "$WORK/bare" && pwd -P)
mkdir -p "$WORK/where-bin"
cat > "$WORK/where-bin/pre-commit" <<STUB
#!/bin/sh
pwd -P > "$WORK/ran-in"
exit 0
STUB
chmod 0755 "$WORK/where-bin/pre-commit"

# expect_where <label> <hook> <cwd> <command> <want-ran-in|none> <want-exit> <stderr-grep>
# An empty stderr pattern asserts silence.
expect_where() {
    rm -f "$WORK/ran-in"
    _err=$(printf '{"tool_input":{"command":%s},"cwd":"%s"}\n' \
        "$(printf '%s' "$4" | jq -Rs .)" "$3" |
        PATH="$WORK/where-bin:$PATH" sh "$2" 2>&1 >/dev/null)
    _code=$?
    _ran=none
    [ -f "$WORK/ran-in" ] && _ran=$(cat "$WORK/ran-in")
    if [ -z "$7" ]; then
        _match=$([ -z "$_err" ] && echo yes)
    else
        _match=$(printf '%s' "$_err" | grep -q "$7" && echo yes)
    fi
    if [ "$_ran" = "$5" ] && [ "$_code" = "$6" ] && [ "$_match" = yes ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-52s -> ran in %s, exit %s\n' "$1" "${_ran##*/}" "$_code"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-52s -> ran in %s, exit %s (want %s, exit %s, stderr matching "%s")\n' \
            "$1" "$_ran" "$_code" "$5" "$6" "$7"
        printf '      stderr: %s\n' "$_err"
    fi
}

echo ""
echo "--- lint the repo the command targets, not the payload cwd (#519) ---"
expect_where "control: plain commit lints cwd"         "$HOOK" "$LINTED" 'git commit -m x'               "$LINTED" 0 ''
expect_where "cd <configured> && commit, from bare"    "$HOOK" "$BARE"   "cd $LINTED && git commit -m x" "$LINTED" 0 ''
expect_where "git -C <configured> commit, from bare"   "$HOOK" "$BARE"   "git -C $LINTED commit -m x"    "$LINTED" 0 ''
expect_where "relative cd is joined onto cwd"          "$HOOK" "$WORK"   'cd linted && git commit -m x'  "$LINTED" 0 ''
expect_where "git -C <configured> push, from bare"     "$HOOK" "$BARE"   "git -C $LINTED push"           "$LINTED" 0 ''
expect_where "cd <bare> && commit does not lint cwd"   "$HOOK" "$LINTED" "cd $BARE && git commit -m x"   none      0 ''
expect_where "git -C <bare> commit does not lint cwd"  "$HOOK" "$LINTED" "git -C $BARE commit -m x"      none      0 ''

echo "--- unresolvable path: not checked, and said so (#519 decision) ---"
# shellcheck disable=SC2016  # literal $: the hook must see an unexpanded variable.
expect_where "cd \"\$VAR\" && commit"                  "$HOOK" "$LINTED" 'cd "$REPO" && git commit -m x' none      0 'not checked'
# shellcheck disable=SC2016
expect_where "git -C \$VAR commit"                     "$HOOK" "$LINTED" 'git -C $REPO commit -m x'      none      0 'not checked'
# shellcheck disable=SC2016
expect_where "cd \$(subst) && push"                    "$HOOK" "$LINTED" 'cd $(mktemp -d) && git push'   none      0 'not checked'
# shellcheck disable=SC2016
expect_where "unresolvable cd AFTER the commit is moot" "$HOOK" "$LINTED" 'git commit -m x && cd "$X"'   "$LINTED" 0 ''

echo "--- subshell scope and pushd/popd are followed (#558) ---"
expect_where "( cd <configured> && commit ), from bare" "$HOOK" "$BARE"   "( cd $LINTED && git commit -m x )" "$LINTED" 0 ''
expect_where "(cd <configured> && push), from bare"     "$HOOK" "$BARE"   "(cd $LINTED && git push)"          "$LINTED" 0 ''
expect_where "pushd <configured> && push, from bare"    "$HOOK" "$BARE"   "pushd $LINTED && git push"         "$LINTED" 0 ''
expect_where "pushd <bare> && commit does not lint cwd" "$HOOK" "$LINTED" "pushd $BARE && git commit -m x"    none      0 ''
# shellcheck disable=SC2016
expect_where "pushd \"\$VAR\" && commit -> not checked" "$HOOK" "$LINTED" 'pushd "$R" && git commit -m x'     none      0 'not checked'
# Controls: the scope ends at `)` and popd returns, so these resolve to the
# start dir -- a fix that merely stripped the parens would fail them.
expect_where "control: ( cd <bare> ) && commit"         "$HOOK" "$LINTED" "( cd $BARE ) && git commit -m x"   "$LINTED" 0 ''
expect_where "control: pushd <bare> && popd && commit"  "$HOOK" "$LINTED" "pushd $BARE && popd && git commit -m x" "$LINTED" 0 ''

echo "--- globs, cd options, groups and pipelines (found working #558) ---"
# shellcheck disable=SC2016
expect_where "cd <glob> && commit -> not checked"       "$HOOK" "$BARE"   "cd $WORK/lint* && git commit -m x" none     0 'not checked'
expect_where "cd -P <configured> && commit"             "$HOOK" "$BARE"   "cd -P $LINTED && git commit -m x" "$LINTED" 0 ''
expect_where "cd - && commit -> not checked"            "$HOOK" "$LINTED" 'cd - && git commit -m x'          none      0 'not checked'
expect_where "cd -e <path> && commit -> not checked"    "$HOOK" "$LINTED" "cd -e $BARE && git commit -m x"   none      0 'not checked'
expect_where "{ cd <configured>; commit; }, from bare"  "$HOOK" "$BARE"   "{ cd $LINTED; git commit -m x; }" "$LINTED" 0 ''
expect_where "cd <bare> | cat; commit: stage is scoped" "$HOOK" "$LINTED" "cd $BARE | cat; git commit -m x"  "$LINTED" 0 ''
expect_where "{ cd <bare>; make; } | tee; commit"       "$HOOK" "$LINTED" "{ cd $BARE; make; } | tee log; git commit -m x" none 0 'not checked'
expect_where "control: cd <configured> >/dev/null"      "$HOOK" "$BARE"   "cd $LINTED >/dev/null && git commit -m x" "$LINTED" 0 ''
expect_where "control: cd <configured> || exit; commit" "$HOOK" "$BARE"   "cd $LINTED || exit 1; git commit -m x" "$LINTED" 0 ''

echo "--- classification does not glob against the hook's cwd ---"
# Run from the repo root, where docs/* expands to several files: with
# globbing on, the second file landed in the subcommand position. The glob
# also makes the path unresolvable, so the hook stops before the toplevel
# lookup classify() keys on; the stage assignment in the trace is the signal.
got=$(cd "$ROOT" && printf '{"tool_input":{"command":"git -C docs/* commit -m x"},"cwd":"%s"}\n' "$ROOT" |
    sh -x "$HOOK" 2>&1 | sed -n 's/^+* *stage=\(pre-[a-z]*\)$/\1/p' | tail -1)
if [ "$got" = "pre-commit" ]; then
    PASS=$((PASS + 1))
    printf 'ok    %-52s -> %s\n' "git -C <glob> commit classifies" "$got"
else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-52s -> %s (want pre-commit)\n' "git -C <glob> commit classifies" "${got:-none}"
fi

echo "--- a missing shared lib fails open, aloud, never exit 2 ---"
mkdir -p "$WORK/nolib"
cp "$HOOK" "$WORK/nolib/precommit-claude-hook"
expect_where "lib absent -> not checked, exit 0"       "$WORK/nolib/precommit-claude-hook" "$LINTED" 'git commit -m x' none 0 'missing'

echo ""
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
