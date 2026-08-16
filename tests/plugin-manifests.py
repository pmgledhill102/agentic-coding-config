#!/usr/bin/env python3
"""Validate the plugin marketplace and plugin manifests.

This repo is its own plugin marketplace (#48): `.claude-plugin/marketplace.json`
at the root is the catalog, and `home/.claude-plugin/plugin.json` is the plugin
manifest, with `home/` doubling as the plugin root.

A broken manifest fails at *install* time, in someone else's session, on a repo
that merely enabled the plugin — which is a long way from the change that broke
it. These are the checks that can be made here instead.

Usage: python3 tests/plugin-manifests.py
"""

import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKETPLACE = ROOT / ".claude-plugin" / "marketplace.json"

# Directories a plugin root may contain, per the plugin structure reference.
# `.claude-plugin/` holds ONLY plugin.json -- putting commands/, skills/,
# agents/ or hooks/ inside it is the documented common mistake, and it fails
# silently by simply not loading anything.
PLUGIN_COMPONENT_DIRS = {"skills", "commands", "agents", "hooks", "bin", "monitors"}

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Hook events a plugin's hooks/hooks.json may declare.
HOOK_EVENTS = {
    "PreToolUse",
    "PostToolUse",
    "UserPromptSubmit",
    "Notification",
    "Stop",
    "SubagentStop",
    "SessionStart",
    "SessionEnd",
    "PreCompact",
}

# `${CLAUDE_PLUGIN_ROOT}/bin/foo` -> `bin/foo`, and the bare script name a
# `plugin-hook-dispatch foo` invocation resolves under bin/.
PLUGIN_ROOT_REF = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/([A-Za-z0-9._/-]+)")
DISPATCH_REF = re.compile(r"plugin-hook-dispatch\"?\s+([A-Za-z0-9._-]+)")

errors = []


def err(msg):
    errors.append(msg)


def check_marketplace():
    if not MARKETPLACE.exists():
        err(f"{MARKETPLACE.relative_to(ROOT)} is missing")
        return None
    try:
        data = json.loads(MARKETPLACE.read_text())
    except json.JSONDecodeError as e:
        err(f"marketplace.json is not valid JSON: {e}")
        return None

    for field in ("name", "owner", "plugins"):
        if field not in data:
            err(f"marketplace.json is missing required field '{field}'")
    if not isinstance(data.get("plugins"), list) or not data.get("plugins"):
        err("marketplace.json 'plugins' must be a non-empty list")
        return None
    if "name" in data and not NAME_RE.match(data["name"]):
        err(f"marketplace name '{data['name']}' is not slug-cased")
    return data


def check_plugin_entry(entry):
    for field in ("name", "source"):
        if field not in entry:
            err(f"marketplace plugin entry is missing required field '{field}'")
            return
    name = entry["name"]
    if not NAME_RE.match(name):
        err(f"plugin name '{name}' is not slug-cased")

    source = entry["source"]
    if not isinstance(source, str):
        # Non-path sources (github/git/command) are valid but out of scope for
        # this repo, which serves its plugin from a subdirectory of itself.
        return
    plugin_root = (ROOT / source).resolve()
    try:
        plugin_root.relative_to(ROOT)
    except ValueError:
        err(f"plugin source '{source}' escapes the repository")
        return
    if not plugin_root.is_dir():
        err(f"plugin source '{source}' does not exist")
        return

    manifest = plugin_root / ".claude-plugin" / "plugin.json"
    if not manifest.exists():
        err(f"plugin source '{source}' has no .claude-plugin/plugin.json")
        return
    try:
        pdata = json.loads(manifest.read_text())
    except json.JSONDecodeError as e:
        err(f"{manifest.relative_to(ROOT)} is not valid JSON: {e}")
        return

    if "name" not in pdata:
        err(f"{manifest.relative_to(ROOT)} is missing required field 'name'")
    elif pdata["name"] != name:
        # The name is the skill namespace (/name:skill), so a mismatch between
        # catalog and manifest is a real inconsistency, not cosmetic.
        err(
            f"plugin name mismatch: marketplace says '{name}', "
            f"{manifest.relative_to(ROOT)} says '{pdata['name']}'"
        )

    if "version" in entry and "version" in pdata and entry["version"] != pdata["version"]:
        err(
            f"version mismatch for '{name}': marketplace says "
            f"'{entry['version']}', plugin.json says '{pdata['version']}'"
        )

    # The documented common mistake: component dirs nested under .claude-plugin/
    # load nothing, and nothing warns.
    for child in (plugin_root / ".claude-plugin").iterdir():
        if child.is_dir() and child.name in PLUGIN_COMPONENT_DIRS:
            err(
                f"{child.relative_to(ROOT)} must live at the plugin root, "
                "not inside .claude-plugin/"
            )

    found = sorted(
        d.name for d in plugin_root.iterdir()
        if d.is_dir() and d.name in PLUGIN_COMPONENT_DIRS
    )
    if not found:
        err(f"plugin '{name}' has no component directories at its root")
    else:
        print(f"  plugin '{name}' at {source}: {', '.join(found)}")

    check_hooks(plugin_root)


def check_hooks(plugin_root):
    """Validate hooks/hooks.json, and that every script it names is really there.

    A hook whose command points at a path that no longer exists fails at tool-use
    time, in a sandbox, as a non-blocking warning nobody reads -- so a renamed or
    deleted script under bin/ would go unnoticed indefinitely. Resolving the
    references here is the cheap way to catch it.
    """
    hooks_file = plugin_root / "hooks" / "hooks.json"
    if not hooks_file.exists():
        # A plugin without hooks is legitimate; only a broken one is an error.
        return
    rel = hooks_file.relative_to(ROOT)
    try:
        data = json.loads(hooks_file.read_text())
    except json.JSONDecodeError as e:
        err(f"{rel} is not valid JSON: {e}")
        return

    events = data.get("hooks")
    if not isinstance(events, dict) or not events:
        err(f"{rel} must have a non-empty top-level 'hooks' object")
        return

    count = 0
    for event, matchers in events.items():
        if event not in HOOK_EVENTS:
            err(f"{rel}: unknown hook event '{event}'")
        if not isinstance(matchers, list):
            err(f"{rel}: '{event}' must be a list of matcher groups")
            continue
        for group in matchers:
            for hook in group.get("hooks", []):
                count += 1
                if hook.get("type") != "command":
                    err(f"{rel}: '{event}' hook has type '{hook.get('type')}', expected 'command'")
                command = hook.get("command", "")
                if not isinstance(command, str) or not command:
                    err(f"{rel}: '{event}' hook has no command string")
                    continue
                if "timeout" in hook and not isinstance(hook["timeout"], int):
                    err(f"{rel}: '{event}' hook timeout must be an integer")
                check_hook_targets(rel, plugin_root, command)
    print(f"  hooks.json: {count} hooks across {len(events)} events")


def check_hook_targets(rel, plugin_root, command):
    for ref in PLUGIN_ROOT_REF.findall(command):
        target = plugin_root / ref
        if not target.is_file():
            err(f"{rel}: command references ${{CLAUDE_PLUGIN_ROOT}}/{ref}, which does not exist")
        elif not os.access(target, os.X_OK):
            err(f"{rel}: ${{CLAUDE_PLUGIN_ROOT}}/{ref} is not executable")

    # The dispatcher takes a bare script name and runs bin/<name>; a typo there
    # is invisible to the reference check above.
    for name in DISPATCH_REF.findall(command):
        target = plugin_root / "bin" / name
        if not target.is_file():
            err(f"{rel}: plugin-hook-dispatch names '{name}', which is not in bin/")
        elif not os.access(target, os.X_OK):
            err(f"{rel}: bin/{name} is not executable")


def main():
    data = check_marketplace()
    if data:
        for entry in data["plugins"]:
            check_plugin_entry(entry)

    if errors:
        print("\nplugin manifest validation FAILED:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("plugin manifests are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
