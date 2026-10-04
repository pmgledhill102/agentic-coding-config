#!/bin/sh
# gates-wired.sh — every tests/*.sh is run by CI and listed in CLAUDE.md's
# gate list, or says in its own header why it is not.
#
# A test nothing runs is worse than no test: its presence asserts coverage
# that nobody is checking, and nothing reports the day it stops passing.
# CLAUDE.md and ci.yml can agree with each other perfectly while both omit the
# same file, so the check is file -> both, not doc <-> CI.
#
# "Wired" means invoked: the literal `sh tests/<name>` must appear in
# .github/workflows/ci.yml and in CLAUDE.md. A passing mention in prose does
# not count.
#
# Opting out is a line in the test's own header:
#
#   # gate: not-wired — <reason, and what runs it instead>
#
# The reason is required; a bare marker is reported as unwired.
#
# Every run first proves the check can go red, against a scratch copy with a
# planted unwired test (and no other tests, so a real unwired file is named
# by the real check below rather than tripping a control), so a check that
# silently passes everything cannot report clean.
#
# Usage: sh tests/gates-wired.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# check <root> — print each unwired test; exit 1 if there are any.
check() {
    _ci="$1/.github/workflows/ci.yml"
    _doc="$1/CLAUDE.md"
    _bad=0
    for _t in "$1"/tests/*.sh; do
        [ -f "$_t" ] || continue
        _n=$(basename -- "$_t")
        if grep -Eq '^# gate: not-wired .*[^[:space:]]' "$_t"; then
            continue
        fi
        _missing=""
        grep -Fq "sh tests/$_n" "$_ci" || _missing="ci.yml"
        grep -Fq "sh tests/$_n" "$_doc" || _missing="${_missing:+$_missing, }CLAUDE.md"
        if [ -n "$_missing" ]; then
            echo "unwired: tests/$_n (not invoked in: $_missing)"
            _bad=1
        fi
    done
    return "$_bad"
}

# --- Negative controls: the check must be able to fail. -------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

control_failed=0

# control <label> <expected-exit> <planted-file-body> [wire-into...]
control() {
    _label=$1
    _want=$2
    _body=$3
    shift 3
    rm -rf "$WORK/r"
    mkdir -p "$WORK/r/tests" "$WORK/r/.github/workflows"
    cp "$ROOT/.github/workflows/ci.yml" "$WORK/r/.github/workflows/ci.yml"
    cp "$ROOT/CLAUDE.md" "$WORK/r/CLAUDE.md"
    printf '%s\n' "$_body" > "$WORK/r/tests/zz-planted-test.sh"
    for _w in "$@"; do
        printf '        run: sh tests/zz-planted-test.sh\n' >> "$WORK/r/$_w"
    done
    check "$WORK/r" > /dev/null
    _got=$?
    if [ "$_got" -eq "$_want" ]; then
        printf '  ok    control: %s\n' "$_label"
    else
        printf '  FAIL  control: %s (want exit %s, got %s)\n' "$_label" "$_want" "$_got"
        control_failed=1
    fi
}

PLAIN='#!/bin/sh
exit 0'
control "planted test wired to nothing fails" 1 "$PLAIN"
control "planted test in ci.yml only fails" 1 "$PLAIN" .github/workflows/ci.yml
control "planted test in CLAUDE.md only fails" 1 "$PLAIN" CLAUDE.md
control "planted test wired into both passes" 0 "$PLAIN" .github/workflows/ci.yml CLAUDE.md
control "opt-out with a reason passes" 0 '#!/bin/sh
# gate: not-wired — run by hand only, because reasons
exit 0'
control "opt-out without a reason fails" 1 '#!/bin/sh
# gate: not-wired
exit 0'

if [ "$control_failed" -ne 0 ]; then
    echo "gates-wired: the check itself is broken; not trusting its verdict."
    exit 1
fi

# --- The real check. -------------------------------------------------------
if check "$ROOT"; then
    echo "gates-wired: every tests/*.sh is run by CI and listed in CLAUDE.md."
else
    echo "Wire each into .github/workflows/ci.yml and CLAUDE.md's gate list,"
    echo "or add '# gate: not-wired — <reason>' to its header."
    exit 1
fi
