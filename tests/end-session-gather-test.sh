#!/bin/sh
# Multi-repo probe tests for home/bin/end-session-gather-state.
#
# The property under test is #570's: the `repo_candidates` probe must not report
# a merged commit as unpushed just because the local origin/<default> predates
# the merge and the branch's own remote ref is gone — and it must still report a
# commit no remote holds. A probe that can only say zero is no probe.
#
# Every remote is a local bare repo, so the fetch the probe makes on a non-zero
# count works offline and needs no token. The fixtures sit side by side under
# one parent, which is what makes the gather take its `ambiguous` path.
#
# Usage: sh tests/end-session-gather-test.sh

# shellcheck disable=SC2016  # deliberate: each check's script expands its own positional args inside `sh -c`.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GATHER="$ROOT/home/bin/end-session-gather-state"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# Keep the developer's own git config out of the fixtures.
HOME="$WORK/home"
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
mkdir -p "$HOME" "$WORK/remotes" "$WORK/parent" "$WORK/elsewhere"
git config --global init.defaultBranch main

# new_remote <name>: a bare origin with one commit on main.
new_remote() {
    git init -q --bare "$WORK/remotes/$1.git"
    git clone -q "$WORK/remotes/$1.git" "$WORK/elsewhere/$1-seed" 2>/dev/null
    git -C "$WORK/elsewhere/$1-seed" commit -q --allow-empty -m init
    git -C "$WORK/elsewhere/$1-seed" push -q origin main
}

# commit_file <repo> <file>: a commit carrying a real patch, so `git cherry`
# has something to compare.
commit_file() {
    echo "$2" >"$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "add $2"
}

# merged_away <name> <how>: the #570 shape. A branch is pushed, merged on the
# remote by someone else (<how> = merge | squash), and its remote branch is
# deleted. The local clone never fetches afterwards, so its origin/main is
# stale, and its record of origin/feat is dropped as a prune would drop it.
merged_away() {
    new_remote "$1"
    git clone -q "$WORK/remotes/$1.git" "$WORK/parent/$1"
    git -C "$WORK/parent/$1" checkout -q -b feat
    commit_file "$WORK/parent/$1" "$1.txt"
    git -C "$WORK/parent/$1" push -q origin feat 2>/dev/null

    other="$WORK/elsewhere/$1-merger"
    git clone -q "$WORK/remotes/$1.git" "$other"
    case "$2" in
        merge) git -C "$other" merge -q --no-ff -m "Merge feat" origin/feat ;;
        squash) git -C "$other" cherry-pick origin/feat >/dev/null ;;
    esac
    git -C "$other" push -q origin main
    git -C "$other" push -q origin --delete feat 2>/dev/null

    git -C "$WORK/parent/$1" update-ref -d refs/remotes/origin/feat
}

merged_away merged merge
merged_away squashed squash

# A commit on a branch that was never pushed anywhere.
new_remote unpushed
git clone -q "$WORK/remotes/unpushed.git" "$WORK/parent/unpushed"
git -C "$WORK/parent/unpushed" checkout -q -b wip
commit_file "$WORK/parent/unpushed" wip.txt

# The same, but the remote is unreachable, so the count cannot be verified.
new_remote offline
git clone -q "$WORK/remotes/offline.git" "$WORK/parent/offline"
git -C "$WORK/parent/offline" checkout -q -b wip
commit_file "$WORK/parent/offline" wip.txt
git -C "$WORK/parent/offline" remote set-url origin "$WORK/remotes/gone.git"

# Nothing unpushed and an unreachable remote: a zero takes no network, so it
# stays a plain zero rather than being labelled unfetched.
new_remote clean
git clone -q "$WORK/remotes/clean.git" "$WORK/parent/clean"
git -C "$WORK/parent/clean" remote set-url origin "$WORK/remotes/gone.git"

pass=0
fail=0

check() {
    desc=$1
    shift
    if "$@"; then
        pass=$((pass + 1))
    else
        echo "FAIL: $desc"
        fail=$((fail + 1))
    fi
}

out="$WORK/out"

# Precondition: the fixture really is the #570 shape — before the gather
# fetches, the offline count calls the merged commits unpushed. Without this
# the merged cases below could pass against a probe that never looked.
for r in merged squashed; do
    check "precondition: $r reads as unpushed offline" \
        sh -c '[ "$(git -C "$1" log --branches --not --remotes --oneline | grep -c .)" -gt 0 ]' _ "$WORK/parent/$r"
done

(cd "$WORK/parent" && "$GATHER" 2>/dev/null) >"$out"
status=$?

check "gather takes the ambiguous path (exit 2)" [ "$status" -eq 2 ]
check "repo_candidates section is emitted" grep -q '^===repo_candidates (exit=2)===' "$out"
check "merge-merged branch with stale origin/main is not unpushed" \
    grep -q "^candidate=$WORK/parent/merged dirty=0 unpushed=0 stashes=0\$" "$out"
check "squash-merged branch with stale origin/main is not unpushed" \
    grep -q "^candidate=$WORK/parent/squashed dirty=0 unpushed=0 stashes=0\$" "$out"
check "a genuinely unpushed commit still reports non-zero" \
    grep -q "^candidate=$WORK/parent/unpushed dirty=0 unpushed=1 stashes=0\$" "$out"
check "a failed fetch labels the count instead of clearing it" \
    grep -q "^candidate=$WORK/parent/offline dirty=0 unpushed=1 (refs unfetched) stashes=0\$" "$out"
check "a zero count is reported plainly, with no fetch to fail" \
    grep -q "^candidate=$WORK/parent/clean dirty=0 unpushed=0 stashes=0\$" "$out"

[ "$fail" -eq 0 ] || cat "$out"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
