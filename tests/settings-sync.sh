#!/bin/sh
# settings-sync.sh — home/settings.json must not change without
# home/settings.json.md changing with it.
#
# JSON carries no comments, so settings.json.md is the only place a rule's
# rationale lives. A rule — or a hook, which the .md documents too — landing
# in settings.json with no matching .md change is a rule nobody can later
# justify or safely remove.
#
# The check is one-directional on purpose. A .md-only change is always fine:
# it is a rationale being improved while settings.json is byte-identical, and
# a gate that rejected it would make leaving the rationale stale cheaper than
# fixing it.
#
# The comparison is against the merge base (`BASE...HEAD`), so a local run
# against an origin/main that has moved on sees only this branch's changes,
# and a CI run against the PR's base SHA sees the same thing. It compares
# commits, so uncommitted edits are not seen: commit, then run it.
#
# Every run first proves the verdict can go red, against a scratch repository,
# so a check that silently passes everything cannot report clean.
#
# Usage: sh tests/settings-sync.sh [BASE]   (BASE defaults to origin/main)

set -u

JSON=home/settings.json
MD=home/settings.json.md

# verdict <base> — exit 1 when settings.json changed and the .md did not.
# Runs in the current directory's repository.
verdict() {
    changed=$(git diff --name-only "$1"...HEAD -- "$JSON" "$MD") || return 2
    json=no
    md=no
    for f in $changed; do
        case "$f" in
            "$JSON") json=yes ;;
            "$MD") md=yes ;;
        esac
    done
    if [ "$json" = yes ] && [ "$md" = no ]; then
        echo "$JSON changed and $MD did not."
        echo "Every rule or hook change in settings.json needs its rationale in settings.json.md."
        return 1
    fi
    echo "settings.json changed: $json; settings.json.md changed: $md — sync OK."
    return 0
}

# --- Negative controls: the verdict must be able to fail. -----------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

control_failed=0

# control <label> <expected-exit> <files-to-touch...>
control() {
    label=$1
    want=$2
    shift 2
    (
        cd "$WORK" || exit 9
        rm -rf repo
        mkdir -p repo/home
        cd repo || exit 9
        git init -q .
        printf '{}\n' > "$JSON"
        printf '# notes\n' > "$MD"
        git add -A
        git -c user.email=t@example.com -c user.name=t commit -q -m base
        git branch -q base
        for f in "$@"; do printf 'x\n' >> "$f"; done
        git add -A
        git -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m change
        verdict base > /dev/null
    )
    got=$?
    if [ "$got" -eq "$want" ]; then
        printf '  ok    control: %s\n' "$label"
    else
        printf '  FAIL  control: %s (want exit %s, got %s)\n' "$label" "$want" "$got"
        control_failed=1
    fi
}

control "settings.json alone fails" 1 "$JSON"
control "both files pass" 0 "$JSON" "$MD"
control "settings.json.md alone passes" 0 "$MD"
control "neither file passes" 0

if [ "$control_failed" -ne 0 ]; then
    echo "settings-sync: the check itself is broken; not trusting its verdict."
    exit 1
fi

# --- The real check. -------------------------------------------------------
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BASE=${1:-origin/main}
cd "$ROOT" || exit 1

if ! git rev-parse --verify --quiet "$BASE^{commit}" > /dev/null; then
    echo "settings-sync: base ref '$BASE' does not resolve; fetch it or pass one."
    exit 2
fi

verdict "$BASE"
