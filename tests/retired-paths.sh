#!/bin/sh
# retired-paths.sh — validate home/retired-paths.
#
# The list drives ~/.claude/bin/claude-prune-retired, which deletes every path
# it names from ~/.claude/ after each chezmoi apply, on every machine. A bad
# entry is therefore a delete loop nobody is watching, which is why this runs
# in CI rather than being trusted to review.
#
# The file has two sections with OPPOSITE preconditions:
#
#   above the UNDEPLOYED marker   retired — the path must be GONE from home/
#   below it                      undeployed — the path must STILL be in home/
#
# The inversion is deliberate. An undeployed path is one that must stay in
# home/ for some reason other than deployment, while no longer being delivered
# to ~/.claude/; if it isn't in home/ at all then it is simply retired and the
# entry is on the wrong side. Checking each section for the other's condition
# means neither can quietly absorb the other's mistakes.
#
# Usage: sh tests/retired-paths.sh [path-to-list]
# Exit: 0 if every entry is safe and correctly placed, 1 otherwise.

set -u

root=$(dirname -- "$0")/..
list="${1:-$root/home/retired-paths}"
home_dir="$root/home"

# Validating a list that isn't the repo's own (the test cases below) still has
# to resolve paths against the real home/, since that is what the assertions
# are about.
if [ ! -f "$list" ]; then
    echo "$list not present — nothing to validate."
    exit 0
fi

rc=0
section=retired
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        '# === UNDEPLOYED:'*) section=undeployed; continue ;;
    esac

    path=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
    case "$path" in
        '' | '#'*) continue ;;
    esac

    # Must not escape ~/.claude/. The pruner refuses these too, but failing
    # here means a bad entry never reaches a machine. Both sections.
    case "$path" in
        /* | *..*)
            echo "::error file=home/retired-paths::unsafe entry (absolute or ..): $path"
            rc=1
            continue
            ;;
    esac

    if [ "$section" = retired ]; then
        if [ -e "$home_dir/$path" ]; then
            echo "::error file=home/retired-paths::still present in home/ — retire the file first, move it below the UNDEPLOYED marker, or drop this entry: $path"
            rc=1
        fi
    else
        if [ ! -e "$home_dir/$path" ]; then
            echo "::error file=home/retired-paths::listed as undeployed but absent from home/ — move it above the UNDEPLOYED marker: $path"
            rc=1
        fi
    fi
done < "$list"

if [ "$rc" -eq 0 ]; then
    echo "retired-paths: entries are safe and on the correct side of the UNDEPLOYED marker."
fi
exit "$rc"
