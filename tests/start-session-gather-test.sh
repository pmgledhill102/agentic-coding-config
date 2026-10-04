#!/bin/sh
# GitHub-lane tests for home/bin/start-session-gather-state.
#
# The property under test is #550's: a gh issue section never reports a gh
# failure as data. The skill reads "exit=0 with content" as issue rows, so a
# 403 body under exit=0 is a confident wrong answer. Two lanes are separate:
# repo-scoped REST (the archived probe) and GraphQL (what `gh issue list`
# uses), and the Claude Code proxy can pass the first while blocking the
# second.
#
# `gh` is stubbed on PATH; each lane's outcome is set per case through
# STUB_REST / STUB_GQL / STUB_LIST. The fixture repo's origin is a github.com
# URL that is never reached: the fetch fails and the script carries on, which
# is its normal offline behaviour.
#
# Usage: sh tests/start-session-gather-test.sh

# shellcheck disable=SC2016  # deliberate: each check's script expands its own positional args inside `sh -c`.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GATHER="$ROOT/home/bin/start-session-gather-state"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/bin" "$WORK/repo"
(
    cd "$WORK/repo" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git commit -q --allow-empty -m init
    git remote add origin https://github.com/example-owner/example-repo.git
)

cat >"$WORK/bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2" in
    "api repos/"*)
        [ "${STUB_REST:-ok}" = ok ] || { echo "HTTP 403: Forbidden" >&2; exit 1; }
        echo false ;;
    "api graphql")
        [ "${STUB_GQL:-ok}" = ok ] || { echo "HTTP 403: GraphQL is not available" >&2; exit 1; }
        echo '{"data":{"viewer":{"login":"t"}}}' ;;
    "issue list")
        # issue list rides GraphQL, so a blocked GraphQL lane blocks it too.
        [ "${STUB_GQL:-ok}" = ok ] || { echo "HTTP 403: GraphQL is not available" >&2; exit 1; }
        case "${STUB_LIST:-ok}" in
            ok)
                echo "warning: a notice on stderr that must not reach jq" >&2
                echo '[{"number":7,"title":"Bundle: seven","labels":[{"name":"P2"}]}]' ;;
            *)
                echo "HTTP 502: Bad Gateway" >&2
                exit 1 ;;
        esac ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

pass=0
fail=0

# Run the gather in the fixture with the stub first on PATH. Prints the whole
# sectioned stream; the env assignments carry the per-case lane outcomes.
gather() {
    (cd "$WORK/repo" && PATH="$WORK/bin:$PATH" "$GATHER" 2>/dev/null)
}

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

# --- REST passes, GraphQL blocked: the live Claude Code sandbox shape. -------
STUB_REST=ok STUB_GQL=fail STUB_LIST=fail
export STUB_REST STUB_GQL STUB_LIST
gather >"$out"
for s in gh_ready gh_assigned gh_bundles; do
    check "graphql blocked: $s exits non-zero" \
        grep -q "^===$s (exit=1)===" "$out"
    check "graphql blocked: $s says gh-unauthorized" \
        sh -c 'grep -A1 "^===$2 (exit=1)===" "$1" | grep -qx gh-unauthorized' _ "$out" "$s"
    check "graphql blocked: $s carries no 403 body" \
        sh -c '! grep -A3 "^===$2 (exit=" "$1" | grep -q 403' _ "$out" "$s"
done
check "graphql blocked: repo_archived still answers from REST" \
    sh -c 'grep -A1 "^===repo_archived (exit=" "$1" | grep -qx "state=false"' _ "$out"

# --- Both probes pass, then the list call itself fails. ---------------------
STUB_REST=ok STUB_GQL=ok STUB_LIST=fail
gather >"$out"
for s in gh_ready gh_assigned gh_bundles; do
    check "list fails: $s exits non-zero, not exit=0" \
        sh -c '! grep -q "^===$2 (exit=0)===" "$1" && grep -q "^===$2 (exit=" "$1"' _ "$out" "$s"
    check "list fails: $s shows gh's own error" \
        sh -c 'grep -A3 "^===$2 (exit=" "$1" | grep -q "HTTP 502"' _ "$out" "$s"
done

# --- Everything passes; gh warns on stderr. Rows must still parse. ----------
STUB_REST=ok STUB_GQL=ok STUB_LIST=ok
gather >"$out"
check "healthy: gh_ready exit=0" grep -q "^===gh_ready (exit=0)===" "$out"
check "healthy: gh_ready row parsed" grep -qx "#7|P2|Bundle: seven" "$out"
check "healthy: gh_bundles row parsed" grep -qx "#7|seven" "$out"
check "healthy: stderr warning kept out of the data" \
    sh -c '! grep -q "must not reach jq" "$1"' _ "$out"

# --- REST blocked: nothing measured, so archived is unknown. ----------------
STUB_REST=fail STUB_GQL=ok STUB_LIST=ok
gather >"$out"
check "rest blocked: repo_archived is unknown, never false" \
    sh -c 'grep -A1 "^===repo_archived (exit=" "$1" | grep -qx "state=unknown"' _ "$out"
check "rest blocked: gh_ready says gh-unauthorized" \
    sh -c 'grep -A1 "^===gh_ready (exit=1)===" "$1" | grep -qx gh-unauthorized' _ "$out"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
