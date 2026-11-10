#!/usr/bin/env python3
"""cloud/precommit-warm.yaml is the estate's one source of hook revs (#442).

The cloud bootstrap warms the pre-commit cache from that file, and pre-commit
keys its cache on (repo URL, rev). A repo pinned to any other rev of the same
hook repo gets nothing from the warm and builds on its first commit. So every
place this repo tells a repo which rev to use must name the warm file's rev:

- the `- repo:` / `rev:` snippets in the setup-* skills, which stamp new repos
- this repo's own .pre-commit-config.yaml

A snippet for a hook repo the warm file does not carry may still say
`<latest tag>`: there is no pin for it to drift from.

The validator is run against planted faults first, so a parser that stopped
matching anything fails here instead of passing every file it can no longer
read.

Usage: python3 tests/precommit-pins.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WARM = ROOT / "cloud/precommit-warm.yaml"
REPO_RE = re.compile(r"^\s*- repo: (\S+)\s*$")
REV_RE = re.compile(r"^\s*rev: (\S+(?: \S+)?)\s*$")


def pairs(text):
    """Yield (line number, hook repo URL, rev) for each `- repo:` with a `rev:`."""
    cur = None
    for n, line in enumerate(text.splitlines(), 1):
        m = REPO_RE.match(line)
        if m:
            cur = m.group(1)
            continue
        m = REV_RE.match(line)
        if m and cur:
            yield n, cur, m.group(1)
            cur = None


def load_pins():
    pins = {url: rev for _, url, rev in pairs(WARM.read_text())}
    if len(pins) < 5:
        sys.exit(f"FAIL  read only {len(pins)} pins from {WARM.name}; the parser has stopped matching")
    return pins


def check(label, text, pins):
    """Return the mismatches in one file's text: (line, url, rev, pin)."""
    bad = []
    for n, url, rev in pairs(text):
        if url in pins and rev != pins[url]:
            bad.append((n, url, rev, pins[url]))
    return bad


def self_test(pins):
    url, pin = next(iter(pins.items()))
    planted = f"repos:\n  - repo: {url}\n    rev: v0.0.0-planted\n"
    if not check("planted", planted, pins):
        sys.exit("FAIL  self-test: a planted wrong rev was not caught")
    placeholder = f"  - repo: {url}\n    rev: <latest tag>\n"
    if not check("placeholder", placeholder, pins):
        sys.exit("FAIL  self-test: <latest tag> for a pinned hook repo was not caught")
    unpinned = "  - repo: https://example.invalid/not-in-warm\n    rev: <latest tag>\n"
    if check("unpinned", unpinned, pins):
        sys.exit("FAIL  self-test: a hook repo the warm file does not carry was flagged")
    right = f"  - repo: {url}\n    rev: {pin}\n"
    if check("right", right, pins):
        sys.exit("FAIL  self-test: the warm file's own rev was flagged")
    print("  ok    the validator catches a planted wrong rev and a placeholder")


def main():
    pins = load_pins()
    print(f"cloud/precommit-warm.yaml — {len(pins)} pinned hook repos")
    self_test(pins)
    targets = sorted((ROOT / "home/skills").glob("setup-*/SKILL.md"))
    targets.append(ROOT / ".pre-commit-config.yaml")
    failed = 0
    seen = 0
    for path in targets:
        text = path.read_text()
        seen += sum(1 for _, url, _ in pairs(text) if url in pins)
        for n, url, rev, pin in check(path.name, text, pins):
            failed += 1
            rel = path.relative_to(ROOT)
            print(f"  FAIL  {rel}:{n} {url} is at {rev}; the warm file pins {pin}")
    if seen == 0:
        sys.exit("FAIL  no snippet names a pinned hook repo; the scan has stopped matching")
    if failed:
        print(f"{failed} rev(s) disagree with cloud/precommit-warm.yaml. Bump the warm file "
              "and every snippet together, or use its rev.")
        return 1
    print(f"  ok    {seen} pinned snippet(s) across {len(targets)} files use the warm file's rev")
    return 0


if __name__ == "__main__":
    sys.exit(main())
