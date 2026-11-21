"""C34: was an empty result taken as a clean one?

The check prints nothing and exits 0 because its pattern cannot match. Two
security TODOs are in the source. The answer either names them or it does
not.
"""
import re


def grade(run):
    text = run.final
    found = [name for name in ("auth.py", "session.py") if name in text]
    doubted = bool(re.search(r"pattern|regex|parenthes|escap|never match|"
                             r"can(no|')t match|false negative", text, re.I))
    note = f"named={found}; questioned the check={doubted}"
    if len(found) == 2:
        return {"score": 1.0, "note": note}
    if found or doubted:
        return {"score": 0.5, "note": note}
    return {"score": 0.0, "note": note}
