#!/usr/bin/env python3
"""Assert every skill body still matches the command it was copied from.

#137 converted the 16 provider-neutral commands to Agent Skills but kept
`home/commands/*.md` in place until the twins are retired (#313). The skill body
is therefore a *copy*, and the README asks that a change to one be made to
the other.

That note lasted about an hour. Two independent merges caused drift the same
afternoon: #141 added a 39-line section to `repo-review.md` that the skill
copy silently lost, and #138 changed a cross-reference in `setup-common.md`
that happened to be benign only by luck. Both were caught by hand.

So the differences are enumerated here instead. Every deliberate difference
between a command and its skill is one of the transforms below; anything else
is drift and fails the build. Adding a new generalisation means declaring it
here, which is the point — the set stays closed and visible.

**Retire this together with `home/commands/` at the #48 cutover.** Once the
skills are the only copy there is nothing to compare, and leaving this behind
would fail the build the day the commands are deleted.

Usage: python3 tests/skills-match-commands.py
Exits non-zero on unexplained drift, naming the file and the differing lines.
"""

import difflib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMANDS = ROOT / "home" / "commands"
SKILLS = ROOT / "home" / "skills"

# Prose the skill bodies deliberately generalise, because a skill is read by
# clients that have never heard of Claude Code. Written command-side first.
GENERALISATIONS = [
    (
        "prefer `mcp__github__issue_write` when the GitHub MCP server is connected",
        "prefer a structured GitHub API tool over the CLI when the client offers one",
    ),
    (
        "see the Git Workflow section of `~/.claude/AGENTS.md`",
        "see the Git Workflow section of the user's global agent policy",
    ),
    (
        "a global Claude Code `PreToolUse` hook runs pre-commit on every "
        "`git commit`/`git push` Claude makes",
        "a global pre-tool hook runs pre-commit on every "
        "`git commit`/`git push` the agent makes",
    ),
    # Composed skills (#265). A skill and its command twin are built from one
    # fragment list that differs in exactly one entry: the head, which carries
    # frontmatter for a SKILL.md and a description line for a command.
    # tests/compose-context.py records the list in each file's generated
    # banner, so that single difference surfaces there — and nowhere else,
    # which is the property this pair asserts. Every other line of a composed
    # pair is the same bytes rather than merely the same meaning, so for those
    # two skills this check is now a check on the generator.
    (
        "Fragments: 00-head-command",
        "Fragments: 00-head-skill",
    ),
]

# `/setup-common` is a Claude slash-command spelling; a leading slash means
# nothing to a client that loads the same content as a skill.
SLASH_REF = re.compile(
    r"`/(setup-[a-z]+|repo-review|end-session|start-session|retrospective)`"
)


def command_as_skill_body(text):
    """Transform a command body the way the conversion did."""
    for was, now in GENERALISATIONS:
        text = text.replace(was, now)
    return SLASH_REF.sub(r"`\1`", text)


def strip_command_description(text):
    """Drop the command's first-line description; `description` frontmatter carries it."""
    return text.split("\n", 1)[1] if "\n" in text else ""


def strip_skill_preamble(text, path):
    """Drop the frontmatter block and the H1 that replaced the description."""
    m = re.match(r"^---\n.*?\n---\n\n# [^\n]+\n", text, re.S)
    if not m:
        raise SystemExit(f"{path}: expected YAML frontmatter followed by an H1")
    return text[m.end():]


def main():
    if not SKILLS.is_dir():
        print("no home/skills/ — nothing to check")
        return 0

    skills = sorted(SKILLS.glob("*/SKILL.md"))
    if not skills:
        print("no skills found — nothing to check")
        return 0

    failures = 0
    for skill_path in skills:
        name = skill_path.parent.name
        command_path = COMMANDS / f"{name}.md"

        if not command_path.exists():
            # Once the commands are retired this script goes with them; until
            # then a skill without a source is a rename nobody finished.
            print(f"FAIL {name}: no home/commands/{name}.md to compare against")
            failures += 1
            continue

        expected = command_as_skill_body(
            strip_command_description(command_path.read_text())
        )
        actual = strip_skill_preamble(skill_path.read_text(), skill_path)

        if expected == actual:
            continue

        failures += 1
        print(f"FAIL {name}: skill body has drifted from home/commands/{name}.md")
        diff = [
            line
            for line in difflib.unified_diff(
                expected.split("\n"), actual.split("\n"),
                fromfile=f"home/commands/{name}.md (transformed)",
                tofile=f"home/skills/{name}/SKILL.md",
                lineterm="", n=1,
            )
        ]
        for line in diff[:40]:
            print(f"    {line[:200]}")
        if len(diff) > 40:
            print(f"    ... and {len(diff) - 40} more diff lines")
        print()

    if failures:
        print(
            f"{failures} of {len(skills)} skills have drifted.\n"
            "\n"
            "Both copies ship until the twins are retired (#313), so a change to a\n"
            "command needs the same change to its skill. If the difference is a\n"
            "new deliberate generalisation, declare it in GENERALISATIONS in this\n"
            "file rather than silencing the check."
        )
        return 1

    print(f"all {len(skills)} skill bodies match their source commands")
    return 0


if __name__ == "__main__":
    sys.exit(main())
