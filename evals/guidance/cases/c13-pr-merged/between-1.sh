#!/bin/sh
# Between the two prompts someone merges pull request #12 in the web UI:
# main gains a merge commit, the branch is deleted, the PR reads MERGED.
set -e
tmp="$RUN_ROOT/merger"
git clone -q "$RUN_ROOT/origin.git" "$tmp"
cd "$tmp"
git config user.name reviewer
git config user.email reviewer@example.invalid
git merge -q --no-ff origin/feature/greeting-text \
  -m "Merge pull request #12 from example-org/feature/greeting-text"
git push -q origin main
git push -q origin --delete feature/greeting-text
cd "$RUN_ROOT"
rm -rf "$tmp"
sed -i 's/"state": "OPEN"/"state": "MERGED"/; s/"mergedAt": null/"mergedAt": "2026-01-15T10:02:11Z"/; s/"closed": false/"closed": true/' "$RUN_ROOT/gh-state.json"
echo "--- merged ---" >>"$RUN_ROOT/logs/gh.log"
echo "--- merged ---" >>"$RUN_ROOT/logs/phase.log"
