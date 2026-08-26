#!/bin/sh
# retired-paths-test.sh — check that tests/retired-paths.sh rejects what it
# should and accepts what it should.
#
# A validator nobody has seen fail is a validator nobody knows works. The
# section logic in particular has two mirror-image assertions, and getting one
# of them backwards would still pass on the real list — which is currently
# empty below the marker, so it exercises neither branch.
#
# Usage: sh tests/retired-paths-test.sh

set -u

DIR=$(dirname -- "$0")
VALIDATOR="$DIR/retired-paths.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

passed=0
failed=0

# A path that really is in home/, and one that really is not. Both are
# resolved by the validator against the repo's own home/, so these have to be
# true statements about the tree rather than invented names.
PRESENT="bin/claude-prune-retired"
ABSENT="commands/bd-modernize.md"

check() {
    desc=$1
    want=$2
    body=$3
    printf '%s\n' "$body" > "$TMP/list"
    out=$(sh "$VALIDATOR" "$TMP/list" 2>&1)
    got=$?
    if [ "$got" -eq "$want" ]; then
        printf '  ok    %s\n' "$desc"
        passed=$((passed + 1))
    else
        printf '  FAIL  %s (want exit %s, got %s)\n' "$desc" "$want" "$got"
        printf '        %s\n' "$out"
        failed=$((failed + 1))
    fi
}

MARKER='# === UNDEPLOYED: still in home/, no longer deployed to ~/.claude/ ==='

echo "retired-paths validator:"

check "empty list passes" 0 "# nothing here"
check "retired entry that is gone from home/ passes" 0 "$ABSENT"
check "retired entry still in home/ fails" 1 "$PRESENT"

check "undeployed entry still in home/ passes" 0 "$MARKER
$PRESENT"
check "undeployed entry missing from home/ fails" 1 "$MARKER
$ABSENT"

check "both sections, both correct, passes" 0 "$ABSENT
$MARKER
$PRESENT"
check "both sections, entries swapped, fails" 1 "$PRESENT
$MARKER
$ABSENT"

check "absolute path refused above the marker" 1 "/etc/passwd"
check "absolute path refused below the marker" 1 "$MARKER
/etc/passwd"
check "parent traversal refused" 1 "../../.ssh/id_rsa"
check "comments and blanks ignored" 0 "# a comment

$ABSENT
"

# The real list must pass, and must be the thing CI actually validates.
if sh "$VALIDATOR" > /dev/null 2>&1; then
    printf '  ok    the repo'"'"'s own home/retired-paths passes\n'
    passed=$((passed + 1))
else
    printf '  FAIL  the repo'"'"'s own home/retired-paths does not pass\n'
    failed=$((failed + 1))
fi

printf '\npassed: %s   failed: %s\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
