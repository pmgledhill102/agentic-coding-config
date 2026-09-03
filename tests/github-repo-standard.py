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
  - no tier names a repository: assignments are private and live elsewhere

Run with no arguments to validate the committed spec. The last section feeds
the validator a deliberately broken copy, so a validator that stops catching
things fails CI rather than passing it.
"""

import copy
import json
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
    "dependabot_secrets",
}


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
    print(f"ok   {SPEC.relative_to(ROOT)}: {len(spec['tiers'])} tiers, "
          f"{len(spec.get('invariants', []))} invariants")

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
