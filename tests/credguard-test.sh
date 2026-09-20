#!/bin/sh
# Classification tests for home/bin/credguard-claude-hook.
#
# The hook fires on EVERY Bash call, so both halves of its behaviour matter:
# the forbidden token-printing forms must block (exit 2), and everything else
# -- including the neighbouring gcloud commands that print no secret -- must
# not. A guard that blocks `gcloud auth list` gets switched off, and then
# guards nothing.
#
# The evasions at the bottom are deliberately recorded as ALLOWED. This is a
# guardrail, not a security boundary (#440), and a test asserting it catches
# eval or variable indirection would be asserting a property it does not have.
# They are here so the limit is visible rather than assumed.
#
# Usage: sh tests/credguard-test.sh

# shellcheck disable=SC2016  # deliberate: the command strings are payloads fed to the hook, not shell to run.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/credguard-claude-hook"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

PASS=0
FAIL=0

run() { # command -> exit code
    printf '{"tool_input":{"command":%s},"cwd":"/tmp"}\n' \
        "$(printf '%s' "$1" | jq -Rs .)" | sh "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

expect() { # label command expected-exit
    got=$(run "$2")
    if [ "$got" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok    %-52s -> exit %s\n' "$1" "$got"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-52s -> exit %s (want %s)\n' "$1" "$got" "$3"
    fi
}

echo "--- the three forbidden gcloud forms block ---"
expect "print-access-token"          'gcloud auth print-access-token'                       2
expect "print-identity-token"        'gcloud auth print-identity-token'                     2
expect "ADC print-access-token"      'gcloud auth application-default print-access-token'   2

echo "--- ... tolerant of whitespace and interleaved flags ---"
expect "leading flag"                'gcloud --quiet auth print-access-token'               2
expect "flag after auth"             'gcloud auth --project=x print-access-token'           2
expect "padded whitespace"           'gcloud   auth    print-access-token'                  2
expect "line continuation"           'gcloud auth \
print-access-token'                                                                         2
expect "inside a substitution"       'curl -H "X: $(gcloud auth print-access-token)" u'     2
expect "piped onward"                'gcloud auth print-access-token | pbcopy'              2

echo "--- a bearer token in argv blocks wherever it appears ---"
expect "curl header"                 'curl -H "Authorization: Bearer $TOKEN" https://x'     2
expect "lowercase spelling"          'curl -H "authorization: bearer abc" https://x'        2
expect "no space after colon"        'curl -H "Authorization:Bearer abc" https://x'         2

echo "--- neighbouring commands that print no secret are untouched ---"
expect "auth list"                   'gcloud auth list'                                     0
expect "config list"                 'gcloud config list'                                   0
expect "describe a service account"  'gcloud iam service-accounts list --project x'         0
expect "ordinary curl"               'curl -sS https://example.com'                         0
expect "the broker skill by name"    'sh ~/.claude/bin/gcp-credentials request'             0

echo "--- accepted false positive: the phrase blocks even in prose ---"
# precommit-claude-hook matches positionally for exactly this reason (#191):
# writing "git commit" into a notes file should not trigger a lint. The trade
# is deliberately the other way here. Telling an echo from an invocation needs
# real parsing, the cost of being wrong is asymmetric -- a blocked echo is
# rephrased, a leaked token is rotated -- and the phrase is rare in prose
# outside the documentation that explains this guard.
expect "the phrase inside an echo"   'echo "never run gcloud auth print-access-token"'      2

echo "--- fails open on what it cannot parse ---"
expect "empty command"               ''                                                     0

echo "--- known-evadable: a guardrail, not a boundary (#440) ---"
expect "variable indirection"        'C=print-access-token; gcloud auth "$C"'               0
expect "eval"                        'eval "gcloud auth print-""access-token"'              0

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
