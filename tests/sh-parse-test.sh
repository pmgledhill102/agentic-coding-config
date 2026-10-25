#!/bin/sh
# Every home/bin script that declares #!/bin/sh must parse under the local sh.
#
# Why this exists: macOS's /bin/sh is bash 3.2, which ends a $(...) at the first
# unbalanced ")" -- including the one closing a case pattern. A script with
#
#     x=$(case "$y" in "" | *[!0-9]*) ... ;; esac)
#
# parses under dash and bash 4+ (Ubuntu, CI) and fails on a Mac, where the helper
# then prints a syntax error and does nothing (agent-telemetry and the push guard
# both did, #687). The portable form opens each pattern with "(".
#
# So this check can only fail on a host whose /bin/sh is bash 3.2. On any other
# host it cannot speak, and says so rather than reporting a pass it did not earn.
#
# Usage: sh tests/sh-parse-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok() {
	PASS=$((PASS + 1))
	printf '  ok    %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$1"
}

# The control: a known-bad snippet. If this sh accepts it, a clean result below
# proves nothing about bash 3.2.
# shellcheck disable=SC2016 # the snippet is deliberately literal: it is parsed, never run
printf '%s\n' 'x=$(case "$y" in "" | *[!0-9]*) echo a ;; esac)' > "$WORK/bad.sh"
CAN_SPEAK=no
if ! sh -n "$WORK/bad.sh" > /dev/null 2>&1; then
	CAN_SPEAK=yes
	ok "control: this sh rejects an unparenthesised case pattern inside \$(...)"
else
	printf '  skip  control: this sh accepts the unbalanced form, so the parse check below\n'
	printf '        cannot catch it here; it only bites where /bin/sh is bash 3.2 (macOS)\n'
fi

# shellcheck disable=SC2016 # literal on purpose, as above
printf '%s\n' 'x=$(case "$y" in ("" | *[!0-9]*) echo a ;; esac)' > "$WORK/good.sh"
if sh -n "$WORK/good.sh" > /dev/null 2>&1; then
	ok "the parenthesised form parses"
else
	bad "the parenthesised form does not parse under this sh"
fi

for f in "$ROOT"/home/bin/*; do
	[ -f "$f" ] || continue
	case "$(head -1 "$f")" in
	'#!/bin/sh'*)
		if sh -n "$f" > /dev/null 2>&1; then
			ok "parses: ${f#"$ROOT"/}"
		else
			bad "does not parse under this sh: ${f#"$ROOT"/}"
		fi
		;;
	esac
done

printf '\n%s passed, %s failed (bash 3.2 coverage: %s)\n' "$PASS" "$FAIL" "$CAN_SPEAK"
[ "$FAIL" -eq 0 ]
