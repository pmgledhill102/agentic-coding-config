#!/usr/bin/env python3
"""The tool manifest (home/standards/tools.json) is valid, and the sandbox
installer agrees with it (ADR-0020 section 2, #506).

What this protects: the bootstrap holds its own copy of each tool version as a
shell literal. Without a check the manifest is a second opinion that drifts. A
mismatch here is a defect of the same kind as a local version that differs
from CI (ADR-0021 principle 1).

The manifest is deliberately not read by the bootstrap at run time: a sandbox
whose fetch of the manifest fails would lose its toolchain, where a literal
that is asserted equal in CI cannot.

Usage: python3 tests/tool-manifest.py
"""
import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SANDBOX = "ubuntu-ephemeral"
STABLE = re.compile(r"^\d+\.\d+\.\d+$")


def load():
    return json.loads((ROOT / "home/standards/tools.json").read_text())


def resolve(tool):
    """The tool's version: its own, or the one it points at."""
    if tool.get("version_from"):
        path, key = tool["version_from"].split("#")
        node = json.loads((ROOT / "home/standards" / path).read_text())
        for part in key.split("."):
            node = node[part]
        return node
    return tool.get("version")


def literals(var):
    text = (ROOT / "cloud/bootstrap.sh").read_text()
    return re.findall(rf"(?m)^\s*{var}=(\S+)\s*$", text)


def validate(m):
    problems = []
    if m.get("version") != 1:
        problems.append(f"version must be 1, got {m.get('version')!r}")
    surfaces = m.get("surfaces") or {}
    for field in ("standard", "read_from", "unrecorded_surfaces_why", "exclusion_rule"):
        if not m.get(field):
            problems.append(f"no {field}")
    for s in m.get("recorded_surfaces") or []:
        if s not in surfaces:
            problems.append(f"recorded surface {s!r} is not declared")
    seen = set()
    for t in m.get("tools") or []:
        n = t.get("name") or "?"
        if n in seen:
            problems.append(f"{n}: listed twice")
        seen.add(n)
        for f in ("name", "why", "capability", "surfaces"):
            if not t.get(f):
                problems.append(f"{n}: no {f}")
        for s, arm in (t.get("surfaces") or {}).items():
            if s not in surfaces:
                problems.append(f"{n}: unknown surface {s!r}")
            for f in ("source", "on_failure"):
                if not arm.get(f):
                    problems.append(f"{n}.{s}: no {f}")
            if arm.get("on_failure") not in (m.get("on_failure_values") or {}):
                problems.append(f"{n}.{s}: on_failure {arm.get('on_failure')!r} is undefined")
        has_v = t.get("version") is not None
        if has_v and t.get("version_from"):
            problems.append(f"{n}: both version and version_from")
        if not has_v and not t.get("version_from") and not t.get("unpinned_why"):
            problems.append(f"{n}: unpinned with no unpinned_why")
        v = t.get("version") if has_v else None
        if v is not None and not STABLE.match(v):
            problems.append(f"{n}: version {v!r} is not a stable x.y.z")
        if t.get("bootstrap_var") and v is None and not t.get("version_from"):
            problems.append(f"{n}: bootstrap_var with no version to compare")
    for x in m.get("not_installed") or []:
        for f in ("name", "surface", "why"):
            if not x.get(f):
                problems.append(f"not_installed: no {f}")
        if x.get("name") in seen:
            problems.append(f"{x.get('name')}: both installed and not_installed")
    return problems


def agreement(m):
    problems = []
    for t in m["tools"]:
        var = t.get("bootstrap_var")
        if not var:
            continue
        found = literals(var)
        want = resolve(t)
        if found != [want]:
            problems.append(f"{t['name']}: cloud/bootstrap.sh {var} is {found or 'absent'}; manifest says {want}")
    return problems


def main():
    m = load()
    problems = validate(m)
    if problems:
        print("FAIL manifest:\n  " + "\n  ".join(problems))
        return 1
    print(f"ok   manifest valid ({len(m['tools'])} tools)")

    broken = {
        "version 2": lambda s: s.__setitem__("version", 2),
        "duplicate tool": lambda s: s["tools"].append(copy.deepcopy(s["tools"][0])),
        "unexplained tool": lambda s: s["tools"][0].pop("why"),
        "unknown surface": lambda s: s["tools"][0]["surfaces"].__setitem__("amiga", {"source": "x", "on_failure": "degraded"}),
        "undefined on_failure": lambda s: s["tools"][0]["surfaces"][SANDBOX].__setitem__("on_failure", "ignore"),
        "pre-release pin": lambda s: s["tools"][0].__setitem__("version", "1.0.0-rc1"),
        "unpinned without reason": lambda s: [s["tools"][-1].pop("unpinned_why")],
        "both version and version_from": lambda s: s["tools"][5].__setitem__("version", "1.0.0"),
        "installed and not_installed": lambda s: s["not_installed"].append({"name": "gh", "surface": SANDBOX, "why": "x"}),
        "no exclusion rule": lambda s: s.pop("exclusion_rule"),
    }
    missed = [k for k, f in broken.items() if not validate((lambda c: (f(c), c)[1])(copy.deepcopy(m)))]
    if missed:
        print(f"FAIL validator does not catch: {', '.join(missed)}")
        return 1
    print(f"ok   validator catches all {len(broken)} planted faults")

    problems = agreement(m)
    if problems:
        print("FAIL sandbox disagrees with the manifest:\n  " + "\n  ".join(problems))
        return 1
    print("ok   cloud/bootstrap.sh installs the manifest's versions")

    # The agreement check must be able to speak.
    bad = copy.deepcopy(m)
    bad["tools"][0]["version"] = "9.9.9"
    if not agreement(bad):
        print("FAIL agreement check passes a manifest that disagrees with the bootstrap")
        return 1
    print("ok   agreement check catches a version that differs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
