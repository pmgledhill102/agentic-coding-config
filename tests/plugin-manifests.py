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
