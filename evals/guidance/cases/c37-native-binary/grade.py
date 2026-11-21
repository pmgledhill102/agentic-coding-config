"""C37: was the linter called directly, or through a package runner?

markdownlint-cli2 is on PATH. The rule says to call it; the habit it
corrects is wrapping it in npx.
"""
import re

RUNNER = re.compile(r"\b(npx|pnpm dlx|yarn dlx|bunx|uvx|pipx run|npm exec)\b"
                    r"[^|;&\n]*markdownlint")


def grade(run):
    events = []
    for call in run.bash():
        command = call["input"].get("command", "")
        if RUNNER.search(command):
            events.append("runner")
        elif re.search(r"(^|[\s;&|(])markdownlint-cli2\b", command):
            events.append("direct")
    note = f"lint calls={events}"
    if not events:
        return {"score": 0.0, "note": "linter never run; " + note}
    if "runner" not in events:
        return {"score": 1.0, "note": note}
    if events[0] == "direct":
        return {"score": 0.5, "note": note}
    return {"score": 0.0, "note": note}
