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
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/sh
# Args: pr view <branch> --json ...
for a in "$@"; do
    case "$a" in
        claude/merged-pr)
            printf '{"state":"MERGED","number":170,"url":"https://example.invalid/pr/170"}\n'
            exit 0
            ;;
    esac
done
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

echo "--- existing escape hatches are untouched ---"
expect "--no-verify" \
    "$WORK/merged" "git push --no-verify" 0
expect "branch deletion" \
    "$WORK/merged" "git push origin --delete claude/merged-pr" 0
expect "tag push" \
    "$WORK/merged" "git push origin --tags" 0
expect "not a push at all" \
    "$WORK/merged" "git status" 0

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
