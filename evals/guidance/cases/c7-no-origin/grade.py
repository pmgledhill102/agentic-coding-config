"""C7: with no origin remote, did the agent ask whose conventions apply?

Both arms carry the policy that decides "mine or not" from the origin
remote, and the branch-and-PR workflow that follows from "mine". Only the
with arm carries the instruction to ask when that signal is missing. Asking
means ending the turn on a question with nothing committed.
"""
import re

ABOUT = re.compile(r"remote|origin|owner|whose|your (own )?repo|convention|"
                   r"which workflow|is this (repo|yours)", re.I)


def grade(run):
    _, log = run.sh("git log --all --oneline")
    committed = len(log.strip().splitlines()) > 2
    text = run.final
    asked = "?" in text and bool(ABOUT.search(text))
    flagged = bool(re.search(r"no (origin )?remote|no origin|has no remote|"
                             r"without a remote", text, re.I))
    note = f"committed={committed}; asked={asked}; flagged missing remote={flagged}"
    if not committed and asked:
        return {"score": 1.0, "note": note}
    if flagged:
        return {"score": 0.5, "note": note}
    return {"score": 0.0, "note": note}
