#!/usr/bin/env python3
"""Assert every helper invocation in home/commands/ is covered by an allow rule.

WHY: a permission rule that doesn't match fails invisibly. Nothing errors --
the user just gets a prompt, and a prompt looks like normal life. #237 found
all four session-lifecycle rules missing the command form the docs tell agents
to run, and it had been that way since #139 without anyone noticing.

The failure is always the same shape: the rule and the command drift apart
because they live in different files and nothing compares them. This does.

SCOPE: only invocations of scripts this repo ships in home/bin/. A blanket
"every line in a fenced block is a command" check drowns in false positives --
those blocks also hold sample output, .gitignore bodies and prose. Narrowing to
our own helpers gives a set with no ambiguity about what is a command.

MATCHING: Bash rules are literal text with `*` as the only wildcard, matched
against the command BEFORE shell expansion. So a rule that means to cover
`${VAR:-default}/bin/foo` has to contain those literal characters -- expanding
the variable in your head is exactly the mistake #237 was.

WHAT THIS CANNOT CHECK, and it matters: the permissions reference documents `*`
as the only wildcard and says nothing about `{`, `}`, `$` or `[`. Treating them
as literal is therefore an inference, and this file models that inference. If
Claude Code's matcher turns out to give braces meaning, these rules would fail
in a real session while this test stays green -- the same silent-mismatch shape
it exists to catch, one level up. There is no documented dry-run permission
check to settle it, so the empirical check in a live session is not optional.

Usage: python3 tests/allowlist-covers-commands.py
Exits non-zero listing any invocation no rule covers.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "home" / "settings.json"
COMMANDS = ROOT / "home" / "commands"
BIN = ROOT / "home" / "bin"

# Invocations that are MEANT to prompt. Each one is a deliberate omission from
# the allowlist, not an oversight, and home/settings.json.md says why. Keeping
# them here rather than silently skipping means the set stays visible: adding
# an entry is a decision someone has to write a reason for.
EXEMPT = [
    ("gcp-credentials request", "posts an approval card and pings a human"),
    ("gcp-credentials wait", "blocks on a human decision; pairs with request"),
    ("gcp-credentials renew", "mints a token; deliberately not unattended"),
    ("gcp-credentials refresh", "started by request, not invoked directly"),
    ("gcp-credentials revoke", "ends a grant a human granted"),
]

FENCE = re.compile(r"^\s*```")
# A trailing ` # explanation` is for the reader, not part of what gets run.
TRAILING_COMMENT = re.compile(r"\s+#\s.*$")


def bash_patterns():
    """The Bash(...) rule bodies from the allowlist."""
    data = json.loads(SETTINGS.read_text())
    rules = data.get("permissions", {}).get("allow", [])
    out = []
    for rule in rules:
        if rule.startswith("Bash(") and rule.endswith(")"):
            out.append(rule[len("Bash(") : -1])
    return out


def covers(pattern, command):
    """True if a Bash rule pattern matches a command string.

    `*` is the only wildcard; everything else is literal. Anchored both ends,
    so `Bash(foo bar)` is exact and `Bash(foo bar *)` is the prefix form.
    """
    regex = "".join(".*" if part == "*" else re.escape(part)
                    for part in re.split(r"(\*)", pattern))
    return re.fullmatch(regex, command) is not None


def invocations():
    """(file, line number, command) for every home/bin/ script call in a fence."""
    scripts = sorted((p.name for p in BIN.iterdir() if p.is_file()), key=len, reverse=True)
    # Line must START with the invocation: an optional path prefix, the script
    # name, then whitespace or end of line. That last part is what keeps sample
    # output like `gcp-credentials: a live grant already exists...` out -- the
    # colon means it is prose about the tool, not a call to it.
    starters = [re.compile(r"^(\S*/)?" + re.escape(s) + r"(?=\s|$)") for s in scripts]

    found = []
    for path in sorted(COMMANDS.glob("*.md")):
        inside = False
        for n, raw in enumerate(path.read_text().splitlines(), 1):
            if FENCE.match(raw):
                inside = not inside
                continue
            if not inside:
                continue
            line = TRAILING_COMMENT.sub("", raw.strip())
            if any(p.match(line) for p in starters):
                found.append((path.name, n, line))
    return found


def main():
    patterns = bash_patterns()
    if not patterns:
        print("no Bash(...) rules found in home/settings.json", file=sys.stderr)
        return 1

    calls = invocations()
    if not calls:
        print("no home/bin/ invocations found in home/commands/ -- check the parser",
              file=sys.stderr)
        return 1

    uncovered, exempted = [], 0
    for name, line, command in calls:
        if any(reason for prefix, reason in EXEMPT if prefix in command):
            exempted += 1
            continue
        if not any(covers(p, command) for p in patterns):
            uncovered.append((name, line, command))

    if uncovered:
        print("allowlist coverage FAILED -- these would prompt:\n")
        for name, line, command in uncovered:
            print(f"  home/commands/{name}:{line}")
            print(f"    {command}")
        print("\nBash rules are literal text with `*` as the only wildcard, matched")
        print("before shell expansion. A rule covering a command that contains")
        print("`${VAR:-default}` must contain those characters literally.")
        return 1

    print(f"allowlist covers all {len(calls) - exempted} helper invocations "
          f"({exempted} deliberately exempt)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
