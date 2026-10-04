#!/bin/sh
# Repo-resolution tests for home/bin/prepush-guard-claude-hook.
#
# The property under test is the one #404 named: the guard must evaluate the
# repository the push is AIMED AT, not wherever the shell happened to be when
# the hook fired. A PreToolUse hook runs before the command does, so
# `cd /other/clone && git push` is otherwise judged against the starting repo
# -- and because a PreToolUse denial rejects the whole Bash call, a false
# positive discards any heredoc or file write earlier in the same command.
#
# Two fixtures stand in for the estate's normal cross-repo shape: `merged`
# holds a branch whose PR the stub reports MERGED, `live` holds one the stub
# reports as having no PR at all. Blocking is exit 2; allowing is exit 0.
#
# The PR lookup is stubbed rather than mocked at the network layer: the hook
# shells out to `gh`, so a `gh` earlier on PATH is the whole seam.
#
# Usage: sh tests/prepush-guard-test.sh

# shellcheck disable=SC2016  # deliberate: the command strings are payloads fed to the hook, not shell to run.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/prepush-guard-claude-hook"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# --- Fixtures: two repos, on branches the stub answers differently. -------
for r in merged live; do
    mkdir -p "$WORK/$r"
    (
        cd "$WORK/$r" || exit 1
        git init -q .
        git config user.email t@example.com
        git config user.name t
        git commit -q --allow-empty -m init
    ) || { echo "fixture setup failed"; exit 1; }
done
(cd "$WORK/merged" && git checkout -q -b claude/merged-pr)
(cd "$WORK/live" && git checkout -q -b claude/live-pr)

# --- Stub gh: MERGED for the merged branch, "no PR" for anything else. ----
# GH_STUB_MODE=unauth / offline reproduces gh's own failure shapes: exit 4
# with its login prompt, and exit 1 with a network error.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/sh
# Args: pr view <branch> --json ...
case "${GH_STUB_MODE:-}" in
    unauth)
        printf 'To get started with GitHub CLI, please run:  gh auth login\n' >&2
        exit 4
        ;;
    offline)
        printf 'error connecting to api.github.com\n' >&2
        exit 1
        ;;
esac
for a in "$@"; do
    case "$a" in
        claude/merged-pr)
            printf '{"state":"MERGED","number":170,"url":"https://example.invalid/pr/170"}\n'
            exit 0
            ;;
    esac
done
printf 'no pull requests found for branch "%s"\n' "$3" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

PASS=0
FAIL=0

# run <cwd> <command> -> prints the hook's exit code.
run() {
    printf '{"tool_input":{"command":%s},"cwd":%s}\n' \
        "$(printf '%s' "$2" | jq -Rs .)" "$(printf '%s' "$1" | jq -Rs .)" \
        | sh "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

expect() { # label cwd command expected-exit
    got=$(run "$2" "$3")
    if [ "$got" = "$4" ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-46s -> exit %s\n' "$1" "$got"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-46s -> exit %s (want %s)\n' "$1" "$got" "$4"
    fi
}

echo "--- the #404 false positive: push aimed at another repo ---"
expect "cd to a live repo from a merged one" \
    "$WORK/merged" "cd $WORK/live && git push -u origin claude/live-pr" 0
expect "git -C a live repo from a merged one" \
    "$WORK/merged" "git -C $WORK/live push -u origin claude/live-pr" 0
expect "write-then-push keeps the write" \
    "$WORK/merged" "printf x > $WORK/live/note.txt && cd $WORK/live && git push" 0

echo "--- true positives still block, in whichever repo is targeted ---"
expect "plain push on a merged branch" \
    "$WORK/merged" "git push -u origin claude/merged-pr" 2
expect "cd into a merged repo blocks" \
    "$WORK/live" "cd $WORK/merged && git push" 2
expect "git -C into a merged repo blocks" \
    "$WORK/live" "git -C $WORK/merged push" 2

echo "--- conservative skip beats a false positive ---"
expect "unresolvable cd target (variable)" \
    "$WORK/merged" 'cd "$SCRATCH" && git push' 0
expect "unresolvable -C target (substitution)" \
    "$WORK/merged" 'git -C $(mktemp -d) push' 0
expect "cd into a path that is not a repo" \
    "$WORK/merged" "cd $WORK/bin && git push" 0

echo "--- subshell scope and pushd/popd are followed (#558) ---"
expect "( cd merged && git push ) blocks" \
    "$WORK/live" "( cd $WORK/merged && git push )" 2
expect "(cd live && git push) from merged allows" \
    "$WORK/merged" "(cd $WORK/live && git push)" 0
expect "pushd merged && git push blocks" \
    "$WORK/live" "pushd $WORK/merged && git push" 2
expect "pushd live && git push from merged allows" \
    "$WORK/merged" "pushd $WORK/live >/dev/null && git push" 0
# Controls: the subshell's cd does not leak, and popd returns.
expect "control: ( cd live ) && git push blocks" \
    "$WORK/merged" "( cd $WORK/live ) && git push" 2
expect "control: pushd live && popd && push blocks" \
    "$WORK/merged" "pushd $WORK/live && popd && git push" 2

echo "--- existing escape hatches are untouched ---"
expect "--no-verify" \
    "$WORK/merged" "git push --no-verify" 0
expect "branch deletion" \
    "$WORK/merged" "git push origin --delete claude/merged-pr" 0
expect "tag push" \
    "$WORK/merged" "git push origin --tags" 0
expect "not a push at all" \
    "$WORK/merged" "git status" 0

# --- Each stand-down says why, distinctly (#557) ---------------------------
#
# Every skip exits 0, so the exit code cannot tell "the command was worded so
# it could not be checked" from "this machine cannot check". The stderr line
# can. An empty pattern asserts silence: the cases the guard has no business
# with must not add a line to every push.

SH=$(command -v sh)

# Tools the hook needs, without gh: the "gh is not installed" machine.
mkdir -p "$WORK/nogh"
for t in jq cat dirname git sed head mktemp rm tr; do
    ln -s "$(command -v "$t")" "$WORK/nogh/$t"
done
mkdir -p "$WORK/nolib"
cp "$HOOK" "$WORK/nolib/prepush-guard-claude-hook"

# expect_err <label> <hook> <path> <stub-mode> <cwd> <command> <exit> <stderr-grep>
expect_err() {
    _err=$(printf '{"tool_input":{"command":%s},"cwd":%s}\n' \
        "$(printf '%s' "$6" | jq -Rs .)" "$(printf '%s' "$5" | jq -Rs .)" |
        PATH="$3" GH_STUB_MODE="$4" "$SH" "$2" 2>&1 >/dev/null)
    _code=$?
    if [ -z "$8" ]; then
        _match=$([ -z "$_err" ] && echo yes)
    else
        _match=$(printf '%s' "$_err" | grep -q -- "$8" && echo yes)
    fi
    if [ "$_code" = "$7" ] && [ "$_match" = yes ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-46s -> exit %s\n' "$1" "$_code"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-46s -> exit %s (want %s, stderr matching "%s")\n' \
            "$1" "$_code" "$7" "$8"
        printf '      stderr: %s\n' "$_err"
    fi
}

echo "--- each stand-down names its reason (#557) ---"
expect_err "unresolvable path" \
    "$HOOK" "$PATH" "" "$WORK/merged" 'cd "$SCRATCH" && git push' 0 'not checked -- unresolvable path'
expect_err "lib missing" \
    "$WORK/nolib/prepush-guard-claude-hook" "$PATH" "" "$WORK/merged" 'git push' 0 'not checked -- lib missing'
expect_err "gh unavailable" \
    "$HOOK" "$WORK/nogh" "" "$WORK/merged" 'git push' 0 'not checked -- gh unavailable'
expect_err "gh unauthorised" \
    "$HOOK" "$PATH" unauth "$WORK/merged" 'git push' 0 'not checked -- gh unauthorised'
expect_err "gh lookup failed (offline)" \
    "$HOOK" "$PATH" offline "$WORK/merged" 'git push' 0 'not checked -- gh lookup failed'
echo "--- ...and the no-business cases stay silent ---"
expect_err "no PR for the branch: silent" \
    "$HOOK" "$PATH" "" "$WORK/live" 'git push' 0 ''
expect_err "push only mentioned, no gh: silent" \
    "$HOOK" "$WORK/nogh" "" "$WORK/merged" 'grep push notes.md' 0 ''
expect_err "a block still blocks, with its own message" \
    "$HOOK" "$PATH" "" "$WORK/merged" 'git push' 2 'push blocked'

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
