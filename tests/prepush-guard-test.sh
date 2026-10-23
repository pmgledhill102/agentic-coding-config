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
# shells out to `gh api`, so a `gh` earlier on PATH is the whole seam. The
# stub answers the REST pulls listing, which is what the hook must use: cloud
# sandboxes refuse the GraphQL behind `gh pr view` (#317).
#
# Usage: sh tests/prepush-guard-test.sh

# shellcheck disable=SC2016  # deliberate: the command strings are payloads fed to the hook, not shell to run.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/prepush-guard-claude-hook"

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed"
  exit 0
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# --- Fixtures: two repos, on branches the stub answers differently. -------
for r in merged live closed reused noorigin; do
  mkdir -p "$WORK/$r"
  (
    cd "$WORK/$r" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git commit -q --allow-empty -m init
    [ "$r" = noorigin ] || git remote add origin git@github.com:o/r.git
  ) || {
    echo "fixture setup failed"
    exit 1
  }
done
(cd "$WORK/merged" && git checkout -q -b claude/merged-pr)
(cd "$WORK/live" && git checkout -q -b claude/live-pr)
(cd "$WORK/closed" && git checkout -q -b claude/closed-pr)
(cd "$WORK/reused" && git checkout -q -b claude/reused-pr)
(cd "$WORK/noorigin" && git checkout -q -b claude/merged-pr)

# --- Stub gh: the REST pulls listing, keyed on the URL-encoded head. -----
# merged-pr: one merged PR. closed-pr: one closed unmerged. reused-pr: an old
# merged PR plus a newer open one. Anything else: no PR (an empty list).
# GH_STUB_MODE reproduces gh's failure shapes: unauth is exit 4 with its login
# prompt, offline a network error, graphql the sandbox's 403.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/bin/sh
# Args: api repos/o/r/pulls?head=o%3A<branch>&state=all&per_page=100
case "${GH_STUB_MODE:-}" in
    unauth)
        printf 'To get started with GitHub CLI, please run:  gh auth login\n' >&2
        exit 4
        ;;
    offline)
        printf 'error connecting to api.github.com\n' >&2
        exit 1
        ;;
    forbidden)
        printf 'HTTP 403: Access to this path is not permitted through this proxy.\n' >&2
        exit 1
        ;;
esac
[ "$1" = api ] || { echo "stub: unexpected gh $*" >&2; exit 1; }
# A canned response per head, for fixtures whose answer carries real SHAs.
canned="$GH_STUB_DIR/$(printf '%s' "$2" | sed 's/.*head=//; s/&.*//')"
[ -f "$canned" ] && { cat "$canned"; exit 0; }
case "$2" in
    repos/o/r/pulls\?head=o%3Aclaude%2Fmerged-pr\&state=all*)
        printf '[{"number":170,"state":"closed","merged_at":"2026-01-01T00:00:00Z","html_url":"https://example.invalid/pr/170"}]\n' ;;
    repos/o/r/pulls\?head=o%3Aclaude%2Fclosed-pr\&state=all*)
        printf '[{"number":171,"state":"closed","merged_at":null,"html_url":"https://example.invalid/pr/171"}]\n' ;;
    repos/o/r/pulls\?head=o%3Aclaude%2Freused-pr\&state=all*)
        printf '[{"number":180,"state":"open","merged_at":null,"html_url":"https://example.invalid/pr/180"},{"number":172,"state":"closed","merged_at":"2026-01-01T00:00:00Z","html_url":"https://example.invalid/pr/172"}]\n' ;;
    repos/o/r/pulls\?head=*)
        printf '[]\n' ;;
    *)
        echo "stub: unexpected path $2" >&2; exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
GH_STUB_DIR="$WORK/canned"
mkdir -p "$GH_STUB_DIR"
export PATH GH_STUB_DIR

# --- History fixture for the restart rule (#651) ---------------------------
# main: A, then M merging the old PR (head P), then M2. Branches built from it:
#   restart  cut from origin/main at M, plus a new commit   -> allowed
#   stacked  the old head P plus a new commit               -> blocked (orphan)
#   stale    an old head Q that origin/main does not hold   -> blocked
#   closed   restarted like `restart`, but its PR closed unmerged -> blocked
H="$WORK/hist"
mkdir -p "$H"
(
  cd "$H" || exit 1
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
  git remote add origin git@github.com:o/r.git
  git commit -q --allow-empty -m A
  git checkout -q -b old
  git commit -q --allow-empty -m P
  git checkout -q main
  git merge -q --no-ff old -m M
  git update-ref refs/remotes/origin/main main
  git checkout -q -b claude/hist-restart origin/main
  git commit -q --allow-empty -m N
  git checkout -q -b claude/hist-closed origin/main
  git commit -q --allow-empty -m N3
  git checkout -q -b claude/hist-stacked old
  git commit -q --allow-empty -m N2
  git checkout -q -b q main~1
  git commit -q --allow-empty -m Q
  git checkout -q -b claude/hist-stale origin/main
  git commit -q --allow-empty -m N4
  git checkout -q main
  git commit -q --allow-empty -m M2
  git update-ref refs/remotes/origin/main main
) >/dev/null 2>&1 || {
  echo "history fixture setup failed"
  exit 1
}
P=$(git -C "$H" rev-parse old)
Q=$(git -C "$H" rev-parse q)
canned() { # canned <branch> <state: merged|closed> <head-sha>
  _m=null
  [ "$2" = merged ] && _m='"2026-01-01T00:00:00Z"'
  printf '[{"number":190,"state":"closed","merged_at":%s,"html_url":"https://example.invalid/pr/190","head":{"sha":"%s"},"base":{"ref":"main"}}]\n' \
    "$_m" "$3" >"$GH_STUB_DIR/o%3A$(printf '%s' "$1" | sed 's#/#%2F#g')"
}
canned claude/hist-restart merged "$P"
canned claude/hist-stacked merged "$P"
canned claude/hist-stale merged "$Q"
canned claude/hist-closed closed "$P"

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

echo "--- globs, cd options, groups and pipelines (found working #558) ---"
expect "{ cd merged; git push; } blocks" \
  "$WORK/live" "{ cd $WORK/merged; git push; }" 2
expect "cd merged | cat; git push from live allows" \
  "$WORK/live" "cd $WORK/merged | cat; git push" 0
expect "cd -P merged && git push blocks" \
  "$WORK/live" "cd -P $WORK/merged && git push" 2
expect "cd <glob> && git push stands down" \
  "$WORK/live" "cd $WORK/merg* && git push" 0
expect "{ cd live; } | cat; git push stands down" \
  "$WORK/merged" "{ cd $WORK/live; true; } | cat; git push" 0
expect "control: cd merged || exit; git push blocks" \
  "$WORK/live" "cd $WORK/merged || exit 1; git push" 2

echo "--- PR state comes from the REST listing (#317) ---"
expect "closed without merging blocks" \
  "$WORK/closed" "git push" 2
expect "an open PR beats an older merged one" \
  "$WORK/reused" "git push" 0

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
    "$(printf '%s' "$6" | jq -Rs .)" "$(printf '%s' "$5" | jq -Rs .)" \
    | PATH="$3" GH_STUB_MODE="$4" "$SH" "$2" 2>&1 >/dev/null)
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
expect_err "cd - is unresolvable, not \$dir/-" \
  "$HOOK" "$PATH" "" "$WORK/merged" 'cd - && git push' 0 'not checked -- unresolvable path'
expect_err "lib missing" \
  "$WORK/nolib/prepush-guard-claude-hook" "$PATH" "" "$WORK/merged" 'git push' 0 'not checked -- lib missing'
expect_err "gh unavailable" \
  "$HOOK" "$WORK/nogh" "" "$WORK/merged" 'git push' 0 'not checked -- gh unavailable'
expect_err "gh unauthorised" \
  "$HOOK" "$PATH" unauth "$WORK/merged" 'git push' 0 'not checked -- gh unauthorised'
expect_err "gh lookup failed (offline)" \
  "$HOOK" "$PATH" offline "$WORK/merged" 'git push' 0 'not checked -- gh lookup failed'
expect_err "gh lookup failed (proxy 403)" \
  "$HOOK" "$PATH" forbidden "$WORK/merged" 'git push' 0 'not checked -- gh lookup failed: HTTP 403'
expect_err "origin is not on github.com" \
  "$HOOK" "$PATH" "" "$WORK/noorigin" 'git push' 0 'not checked -- origin is not a github.com remote'
echo "--- ...and the no-business cases stay silent ---"
expect_err "no PR for the branch: silent" \
  "$HOOK" "$PATH" "" "$WORK/live" 'git push' 0 ''
expect_err "push only mentioned, no gh: silent" \
  "$HOOK" "$WORK/nogh" "" "$WORK/merged" 'grep push notes.md' 0 ''
expect_err "a block still blocks, with its own message" \
  "$HOOK" "$PATH" "" "$WORK/merged" 'git push' 2 'push blocked: PR #170 for branch claude/merged-pr is already MERGED'
expect_err "a closed PR names its state" \
  "$HOOK" "$PATH" "" "$WORK/closed" 'git push' 2 'is already CLOSED'

echo "--- the restart rule: a merged PR's branch reused for new work (#651) ---"
(cd "$H" && git checkout -q claude/hist-restart)
expect_err "restarted from origin/main: allowed, with a notice" \
  "$HOOK" "$PATH" "" "$H" 'git push -u origin claude/hist-restart' 0 'restarted from origin/main -- allowing'
expect "  ...also with no refspec" \
  "$H" "git push" 0
expect "  ...after main moved on past the restart" \
  "$H" "git push origin HEAD" 0
(cd "$H" && git checkout -q claude/hist-stacked)
expect_err "stacked on the merged head: blocked" \
  "$HOOK" "$PATH" "" "$H" 'git push' 2 'restart it from the latest main'
(cd "$H" && git checkout -q claude/hist-stale)
expect "old head missing from origin/main: blocked" \
  "$H" "git push" 2
(cd "$H" && git checkout -q claude/hist-closed)
expect "restarted, but the PR closed unmerged: blocked" \
  "$H" "git push" 2

echo "--- the target is the refspec, not the checked-out branch ---"
expect "checkout -b new && push new, from a merged branch" \
  "$WORK/merged" "git checkout -b claude/brand-new && git push -u origin claude/brand-new" 0
expect_err "checkout && refspec-less push: not checked" \
  "$HOOK" "$PATH" "" "$WORK/merged" 'git checkout claude/live-pr && git push' 0 'not checked -- branch changes earlier'
expect "pushing a merged branch by name from elsewhere" \
  "$WORK/live" "git push origin claude/merged-pr" 2
expect "HEAD:<live branch> from a merged checkout" \
  "$WORK/merged" "git push origin HEAD:claude/live-pr" 0
expect "HEAD resolves to the checked-out branch" \
  "$WORK/merged" "git push origin HEAD" 2
expect "refs/heads/ prefix is stripped" \
  "$WORK/live" "git push origin HEAD:refs/heads/claude/merged-pr" 2
expect "two refspecs, one merged: blocked" \
  "$WORK/live" "git push origin claude/live-pr claude/merged-pr" 2
expect "a :deletion refspec is not judged" \
  "$WORK/merged" "git push origin :claude/merged-pr" 0
expect_err "a variable refspec: not checked" \
  "$HOOK" "$PATH" "" "$WORK/merged" 'git push origin "$B"' 0 'not checked -- unresolvable refspec'

echo "--- the block message never suggests --no-verify ---"
_msg=$(printf '{"tool_input":{"command":"git push"},"cwd":%s}\n' "$(printf '%s' "$WORK/merged" | jq -Rs .)" \
  | sh "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$_msg" | grep -q -- '--no-verify'; then
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-46s\n' "block message mentions --no-verify"
else
  PASS=$((PASS + 1))
  printf 'ok    %-46s\n' "block message omits --no-verify"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
