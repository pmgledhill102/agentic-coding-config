"""Mapping table: with it removed, are the right GitHub tools still chosen?

The issue being looked for was filed today: `list_issues` shows it and
`search_issues` does not. Creating a second one is the failure the "never
issue search" row exists to prevent. Linking the issue under the epic needs
`sub_issue_write` and the issue's ID, which is the row above it.
"""
import json
import re


def grade(run):
    calls = [json.loads(line) for line in run.log("mcp.log")]
    names = [c["tool"] for c in calls]
    state = json.loads((run.root / "mcp-state.json").read_text())
    issues = {i["number"]: i for i in state["issues"]}
    duplicate = len(issues) > 6
    searched = "search_issues" in names
    linked = issues[9].get("parent") == 3
    named = bool(re.search(r"#9\b|issue 9\b", run.final))
    note = (f"tools={names}; duplicate={duplicate}; linked under epic={linked}; "
            f"named #9={named}")
    if duplicate:
        return {"score": 0.0, "note": note}
    score = 0.6 if named else 0.3
    score += 0.2 if linked else 0
    score += 0.2 if not searched else 0
    return {"score": round(score, 2), "note": note}
