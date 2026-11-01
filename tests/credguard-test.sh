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

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed"
  exit 0
}

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
expect "print-access-token" 'gcloud auth print-access-token' 2
expect "print-identity-token" 'gcloud auth print-identity-token' 2
expect "ADC print-access-token" 'gcloud auth application-default print-access-token' 2

echo "--- ... tolerant of whitespace and interleaved flags ---"
expect "leading flag" 'gcloud --quiet auth print-access-token' 2
expect "flag after auth" 'gcloud auth --project=x print-access-token' 2
expect "padded whitespace" 'gcloud   auth    print-access-token' 2
expect "line continuation" 'gcloud auth \
print-access-token' 2
expect "inside a substitution" 'curl -H "X: $(gcloud auth print-access-token)" u' 2
expect "piped onward" 'gcloud auth print-access-token | pbcopy' 2

echo "--- a bearer token in argv blocks wherever it appears ---"
expect "curl header" 'curl -H "Authorization: Bearer $TOKEN" https://x' 2
expect "lowercase spelling" 'curl -H "authorization: bearer abc" https://x' 2
expect "no space after colon" 'curl -H "Authorization:Bearer abc" https://x' 2

expect "token via command substitution" 'curl -H "Authorization: Bearer $(cat tokenfile)" https://x' 2
expect "printf building the header from a token" 'printf "header = \"Authorization: Bearer %s\"\n" "$(cat tokenfile)" > h.conf' 2

echo "--- a header written as text into a file or script is allowed (#691) ---"
# The body of a heredoc fed to cat, tee or an interpreter travels on stdin,
# not in argv, so it is not the /proc exposure the guard exists for.
expect "cat heredoc to a file" 'cat > f <<'"'"'EOF'"'"'
Authorization: Bearer x
EOF' 0
expect "cat heredoc, redirect after" 'cat <<EOF > f
Authorization: Bearer x
EOF' 0
expect "tee heredoc" 'tee f <<EOF
Authorization: Bearer x
EOF' 0
expect "python heredoc patching docs" 'python3 - <<'"'"'PY'"'"'
s = "Authorization: Bearer <token>"
PY' 0
expect "indented terminator with <<-" 'cat <<-EOF > f
	Authorization: Bearer x
	EOF' 0
expect "heredoc after a cd" 'cd d && cat > f <<EOF
Authorization: Bearer x
EOF' 0

echo "--- ... and the carve-out hides nothing that is real ---"
# Each of these has to keep blocking, or the carve-out is a hole rather than a
# rule. The last two pin that the heredoc scan cannot swallow what follows it.
expect "bash heredoc is code, not data" 'bash <<'"'"'EOF'"'"'
curl -H "Authorization: Bearer $(cat tokenfile)" https://x
EOF' 2
expect "path-qualified shell" '/bin/sh <<EOF
curl -H "Authorization: Bearer $T" https://x
EOF' 2
expect "cat piped into a shell" 'cat <<EOF | sh
curl -H "Authorization: Bearer $T" https://x
EOF' 2
expect "curl after a closed heredoc" 'cat > f <<'"'"'EOF'"'"'
harmless
EOF
curl -H "Authorization: Bearer $T" https://x' 2
expect "curl on the heredoc command line" 'cat > f <<EOF; curl -H "Authorization: Bearer $T" https://x
body
EOF' 2
expect "unterminated heredoc is not guessed at" 'cat <<'"'"'EOF'"'"'
curl -H "Authorization: Bearer $T" https://x' 2
expect "here-string is not a heredoc" 'cat <<< foo
curl -H "Authorization: Bearer $T" https://x' 2
expect "gcloud token form stays blocked in a heredoc" 'cat > f <<EOF
gcloud auth print-access-token
EOF' 2

echo "--- neighbouring commands that print no secret are untouched ---"
expect "auth list" 'gcloud auth list' 0
expect "config list" 'gcloud config list' 0
expect "describe a service account" 'gcloud iam service-accounts list --project x' 0
expect "ordinary curl" 'curl -sS https://example.com' 0
expect "the broker skill by name" 'sh ~/.claude/bin/gcp-credentials request' 0

echo "--- accepted false positive: the phrase blocks even in prose ---"
# precommit-claude-hook matches positionally for exactly this reason (#191):
# writing "git commit" into a notes file should not trigger a lint. The trade
# is deliberately the other way here. Telling an echo from an invocation needs
# real parsing, the cost of being wrong is asymmetric -- a blocked echo is
# rephrased, a leaked token is rotated -- and the phrase is rare in prose
# outside the documentation that explains this guard.
expect "the phrase inside an echo" 'echo "never run gcloud auth print-access-token"' 2

echo "--- fails open on what it cannot parse ---"
expect "empty command" '' 0

echo "--- known-evadable: a guardrail, not a boundary (#440) ---"
expect "variable indirection" 'C=print-access-token; gcloud auth "$C"' 0
expect "eval" 'eval "gcloud auth print-""access-token"' 0
expect "python body shelling out to curl" 'python3 - <<'"'"'PY'"'"'
import subprocess
subprocess.run(["curl", "-H", "Authorization: Bearer " + tok, "https://x"])
PY' 0

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
