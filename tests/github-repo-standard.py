#!/usr/bin/env python3
"""The repo-settings spec must be valid, self-consistent and safe to apply.

`home/standards/github-repo.json` is the single machine-readable statement of
the estate's GitHub repo standard. `setup-repo` applies it and the estate
audit diffs against it, so a mistake here is applied N times and then reported
as compliant. This validates the properties that matter:

  - every tier's `extends` chain resolves, without cycles
  - each `repository` key is a real GET /repos field, so a typo cannot become
    a silently unchecked setting
  - the invariants the spec declares are true of the spec itself: no
    linear-history rule, an empty bypass list, no shipped status-check
    contexts, auto-merge only alongside a required-checks rule, and merge
    commits available wherever merge methods are asserted
  - every `files` pattern compiles as a Python regex and carries its reason,
    and no file rule demands and forbids the same pattern
  - every prohibition names a tier that exists and a setting that is real
  - no tier names a repository: assignments are private and live elsewhere

Run with no arguments to validate the committed spec. The last section feeds
the validator a deliberately broken copy, so a validator that stops catching
things fails CI rather than passing it.
"""

import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "home" / "standards" / "github-repo.json"

# Fields of GET /repos/{owner}/{repo} that a tier may assert. Anything else in
# a `repository` block is a typo, and a typo is worse than an omission: the
# applier ignores it and the audit never checks it.
REPOSITORY_FIELDS = {
    "allow_merge_commit", "allow_squash_merge", "allow_rebase_merge",
    "allow_auto_merge", "allow_update_branch", "delete_branch_on_merge",
    "merge_commit_title", "merge_commit_message",
    "squash_merge_commit_title", "squash_merge_commit_message",
    "allow_forking", "web_commit_signoff_required",
    "has_issues", "has_wiki", "has_projects", "has_discussions",
}
SECURITY_FIELDS = {"dependency_graph", "vulnerability_alerts", "security_updates"}
RULE_TYPES = {
    "deletion", "non_fast_forward", "pull_request", "required_status_checks",
    "required_linear_history", "required_signatures", "creation", "update",
    "required_deployments", "code_scanning", "workflows", "tag_name_pattern",
    "branch_name_pattern", "commit_message_pattern",
}
PROHIBITED_RULES = {"required_linear_history"}
TIER_KEYS = {
    "applies_to", "extends", "repository", "security", "ruleset",
    "rules_required", "rules_when_ci", "classic_branch_protection",
    "dependabot_secrets", "files",
}
FILE_RULE_KEYS = {"required", "why", "must_match", "must_not_match"}
PROHIBITION_KEYS = {"id", "applies_below_tier", "match", "because"}


def resolve(tiers, name, seen=()):
    """The tier with its ancestors folded in. Child keys win; lists concatenate."""
    if name in seen:
        raise ValueError(f"extends cycle: {' -> '.join(seen + (name,))}")
    tier = tiers[name]
    parent = tier.get("extends")
    base = resolve(tiers, parent, seen + (name,)) if parent else {}
    out = copy.deepcopy(base)
    for key, value in tier.items():
        if key in ("extends", "applies_to"):
            continue
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key].update(value)
        elif isinstance(value, list) and isinstance(out.get(key), list):
            out[key] = out[key] + [v for v in value if v not in out[key]]
        else:
            out[key] = value
    return out


def automerge_file(spec):
    """The one file rule the planted faults below mutate."""
    return next(iter(spec["tiers"]["automerge"]["files"].values()))


def validate_files(name, files):
    """A tier's `files` block: reasons present, patterns real, rules satisfiable.

    A pattern that does not compile is the failure this whole file exists to
    prevent — it is applied across the tier and then reported as compliant.
    """
    problems = []
    if not isinstance(files, dict):
        return [f"{name}: files must be an object keyed by glob"]

    for glob, rule in files.items():
        where = f"{name}: files[{glob!r}]"
        unknown = set(rule) - FILE_RULE_KEYS
        if unknown:
            problems.append(f"{where}: unknown keys {sorted(unknown)}")
        if not rule.get("why"):
            problems.append(f"{where}: no why")

        # A pattern in both lists can never be satisfied, so every repo in the
        # tier reports drift no matter what it carries.
        kind_of = {}
        for kind in ("must_match", "must_not_match"):
            for entry in rule.get(kind, []):
                label = f"{where}.{kind}[{entry.get('id') or '?'}]"
                for field in ("id", "pattern", "why"):
                    if not entry.get(field):
                        problems.append(f"{label}: no {field}")
                pattern = entry.get("pattern")
                if not pattern:
                    continue
                try:
                    re.compile(pattern)
                except re.error as e:
                    problems.append(f"{label}: pattern does not compile: {e}")
                if kind_of.setdefault(pattern, kind) != kind:
                    problems.append(f"{label}: pattern is both required and forbidden")

    return problems


def validate_prohibitions(prohibited, tiers):
    """A prohibition must name a tier that exists and a setting that is real."""
    problems = []
    for index, rule in enumerate(prohibited):
        where = f"prohibited[{rule.get('id') or index}]"
        unknown = set(rule) - PROHIBITION_KEYS
        if unknown:
            problems.append(f"{where}: unknown keys {sorted(unknown)}")
        for field in ("id", "because"):
            if not rule.get(field):
                problems.append(f"{where}: no {field}")
        below = rule.get("applies_below_tier")
        if below not in tiers:
            problems.append(f"{where}: applies_below_tier names unknown tier {below!r}")

        match = rule.get("match") or []
        if not match:
            problems.append(f"{where}: no match entries")
        for entry in match:
            if "file" in entry:
                extra = set(entry) - {"file"}
            elif "setting" in entry:
                extra = set(entry) - {"setting", "value"}
                if entry["setting"] not in REPOSITORY_FIELDS:
                    problems.append(
                        f"{where}: {entry['setting']!r} is not a GET /repos field")
            else:
                problems.append(f"{where}: match entry names neither file nor setting: {entry!r}")
                continue
            if extra:
                problems.append(f"{where}: match entry has unknown keys {sorted(extra)}")

    return problems


def validate(spec):
    """Every problem found, as a list of strings. Empty means valid."""
    problems = []

    if spec.get("version") != 1:
        problems.append(f"version must be 1, got {spec.get('version')!r}")

    tiers = spec.get("tiers") or {}
    if not tiers:
        return problems + ["no tiers"]

    for name, tier in tiers.items():
        unknown = set(tier) - TIER_KEYS
        if unknown:
            problems.append(f"{name}: unknown keys {sorted(unknown)}")
        parent = tier.get("extends")
        if parent is not None and parent not in tiers:
            problems.append(f"{name}: extends unknown tier {parent!r}")
        bad = set(tier.get("repository", {})) - REPOSITORY_FIELDS
        if bad:
            problems.append(f"{name}: repository keys are not GET /repos fields: {sorted(bad)}")
        bad = set(tier.get("security", {})) - SECURITY_FIELDS
        if bad:
            problems.append(f"{name}: unknown security keys {sorted(bad)}")
        if "files" in tier:
            problems += validate_files(name, tier["files"])

    problems += validate_prohibitions(spec.get("prohibited", []), tiers)

    if "pmgledhill102/" in json.dumps(tiers):
        problems.append("a tier names a repository; assignments are private and belong in paul-context")

    for name in tiers:
        try:
            tier = resolve(tiers, name)
        except ValueError as e:
            problems.append(str(e))
            continue

        repo = tier.get("repository", {})
        ruleset = tier.get("ruleset")
        rules = {r["type"]: r for r in (ruleset or {}).get("rules", [])}

        for rule in rules:
            if rule not in RULE_TYPES:
                problems.append(f"{name}: unknown ruleset rule type {rule!r}")
        for rule in PROHIBITED_RULES & set(rules):
            problems.append(f"{name}: prohibited rule {rule} in ruleset")
        for rule in PROHIBITED_RULES & set(tier.get("rules_required", []) + tier.get("rules_when_ci", [])):
            problems.append(f"{name}: prohibited rule {rule} listed as required")

        if ruleset is not None:
            if ruleset.get("bypass_actors"):
                problems.append(f"{name}: bypass_actors must be empty")
            if ruleset.get("enforcement") != "active":
                problems.append(f"{name}: ruleset enforcement must be active")
            include = ruleset.get("conditions", {}).get("ref_name", {}).get("include")
            if include != ["~DEFAULT_BRANCH"]:
                problems.append(f"{name}: ruleset must target ~DEFAULT_BRANCH only, got {include!r}")
            rsc = rules.get("required_status_checks", {}).get("parameters", {})
            if rsc.get("required_status_checks"):
                problems.append(f"{name}: spec ships status-check contexts; they are per-repo")
            for listed in tier.get("rules_required", []) + tier.get("rules_when_ci", []):
                if listed not in rules:
                    problems.append(f"{name}: {listed} is required but absent from the ruleset payload")

        if repo.get("allow_auto_merge") is True:
            if "required_status_checks" not in tier.get("rules_required", []):
                problems.append(f"{name}: allow_auto_merge without required_status_checks in rules_required")

        asserts_merge = {"allow_merge_commit", "allow_squash_merge", "allow_rebase_merge"} & set(repo)
        if asserts_merge:
            if repo.get("allow_merge_commit") is not True:
                problems.append(f"{name}: asserts merge methods but allow_merge_commit is not true")
            if repo.get("allow_rebase_merge") is not False:
                problems.append(f"{name}: asserts merge methods but allow_rebase_merge is not false")
            if not any(repo.get(k) for k in asserts_merge):
                problems.append(f"{name}: no merge method enabled")

    return problems


def main():
    spec = json.loads(SPEC.read_text())
    problems = validate(spec)
    for p in problems:
        print(f"FAIL {SPEC.relative_to(ROOT)}: {p}")
    if problems:
        return 1
    properties = sum(
        len(rule.get("must_match", [])) + len(rule.get("must_not_match", []))
        for tier in spec["tiers"].values()
        for rule in tier.get("files", {}).values()
    )
    print(f"ok   {SPEC.relative_to(ROOT)}: {len(spec['tiers'])} tiers, "
          f"{len(spec.get('invariants', []))} invariants, "
          f"{properties} file properties, "
          f"{len(spec.get('prohibited', []))} prohibitions")

    # The validator must still catch things. Each mutation breaks one property
    # the spec relies on; a validator that passes any of them is the bug.
    broken = {
        "linear history": lambda s: s["tiers"]["protected"]["ruleset"]["rules"].append(
            {"type": "required_linear_history"}),
        "bypass actor": lambda s: s["tiers"]["protected"]["ruleset"]["bypass_actors"].append(
            {"actor_id": 1, "actor_type": "Integration", "bypass_mode": "always"}),
        "shipped context": lambda s: s["tiers"]["protected"]["ruleset"]["rules"][3]["parameters"]
            ["required_status_checks"].append({"context": "ci"}),
        "auto-merge ungated": lambda s: s["tiers"]["automerge"].__setitem__("rules_required", []),
        "merge disabled": lambda s: s["tiers"]["protected"]["repository"].__setitem__(
            "allow_merge_commit", False),
        "typo field": lambda s: s["tiers"]["protected"]["repository"].__setitem__(
            "allow_merge_commits", True),
        "named repo": lambda s: s["tiers"]["automerge"].__setitem__(
            "applies_to", "pmgledhill102/example"),
        "extends cycle": lambda s: s["tiers"]["baseline"].__setitem__("extends", "automerge"),
        "uncompilable pattern": lambda s: automerge_file(s)["must_match"][0].__setitem__(
            "pattern", "secrets\\.(AUTOMERGE_PAT"),
        "unexplained pattern": lambda s: automerge_file(s)["must_match"][0].pop("why"),
        "unsatisfiable file rule": lambda s: automerge_file(s)["must_not_match"].append(
            dict(automerge_file(s)["must_match"][0], id="contradiction")),
        "prohibition below an unknown tier": lambda s: s["prohibited"][0].__setitem__(
            "applies_below_tier", "hardened"),
        "prohibition on a typo field": lambda s: s["prohibited"][0]["match"].append(
            {"setting": "allow_auto_merges", "value": True}),
        "unexplained prohibition": lambda s: s["prohibited"][0].pop("because"),
    }
    missed = []
    for label, mutate in broken.items():
        s = copy.deepcopy(spec)
        mutate(s)
        if not validate(s):
            missed.append(label)
    if missed:
        print(f"FAIL validator does not catch: {', '.join(missed)}")
        return 1
    print(f"ok   validator catches all {len(broken)} planted faults")
    return 0


if __name__ == "__main__":
    sys.exit(main())
