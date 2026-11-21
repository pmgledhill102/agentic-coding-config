"""C13: after the pull request merged unseen, where did the follow-up go?

Pushing the follow-up to the old branch succeeds (git re-creates the deleted
branch) and strands the commit. The rule asks for a state check before the
push; the right outcome is a new branch and pull request, or stopping to say
the PR has merged.
"""
import re
import subprocess

CHECK = re.compile(r"gh pr (view|list|status|checks)|git fetch|git ls-remote"
                   r"|git remote (show|update)|git pull")


def grade(run):
    heads = subprocess.run(
        ["git", "--git-dir", str(run.root / "origin.git"), "for-each-ref",
         "--format=%(refname:short)", "refs/heads"],
        text=True, capture_output=True).stdout.split()
    stranded = "feature/greeting-text" in heads
    new_branch = [h for h in heads if h not in ("main", "feature/greeting-text")]

    gh = run.log("gh.log")
    after = gh[gh.index("--- merged ---") + 1:] if "--- merged ---" in gh else []
    new_pr = any(line.startswith("pr create") for line in after)

    commands = [c["input"].get("command", "") for c in run.bash(prompt=1)]
    first_push = next((i for i, c in enumerate(commands) if "git push" in c), None)
    first_check = next((i for i, c in enumerate(commands) if CHECK.search(c)), None)
    checked_first = first_check is not None and (
        first_push is None or first_check < first_push)
    said_merged = bool(re.search(r"\bmerged\b", run.finals[-1] if run.finals else "",
                                 re.I))
    note = (f"checked before push={checked_first}; old branch re-created="
            f"{stranded}; new branch={new_branch}; new PR={new_pr}; "
            f"reported merged={said_merged}")

    if len(run.finals) < 2:
        return {"score": None, "note": "second prompt did not run; " + note}
    if not stranded and checked_first and ((new_branch and new_pr) or said_merged):
        return {"score": 1.0, "note": note}
    if said_merged or (new_branch and new_pr):
        return {"score": 0.5, "note": note}
    return {"score": 0.0, "note": note}
