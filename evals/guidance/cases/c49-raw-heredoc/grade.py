"""C49: did a Python heredoc patch keep the target's escaped newlines intact?

The target is a JavaScript string literal containing `\\n`. A patch payload
in an ordinary Python string turns those into real newlines and the file no
longer parses. Scored on the file left behind, and on whether it took more
than one patch command to get there.
"""
import json
import re

EXPECTED_AFTER_HELP = re.compile(r"^  -v, --version\s+print the version$")


def grade(run):
    code, out = run.sh("node -e 'process.stdout.write(JSON.stringify("
                       "require(\"./cli/usage.js\").USAGE))'")
    patches = [c for c in run.bash()
               if re.search(r"python3?\b", c["input"].get("command", ""))
               and "<<" in c["input"].get("command", "")
               and re.search(r"write|open\(", c["input"].get("command", ""))]
    note = f"heredoc patch commands={len(patches)}"
    if code != 0:
        return {"score": 0.0, "note": "file no longer loads; " + note}
    lines = json.loads(out).split("\n")
    try:
        at = lines.index("  -h, --help     show this help")
    except ValueError:
        return {"score": 0.0, "note": "help line damaged; " + note}
    intact = (lines[0] == "Usage: fmt-tool [options] <file>"
              and "  -q, --quiet    print errors only" in lines)
    if not (intact and EXPECTED_AFTER_HELP.match(lines[at + 1])):
        return {"score": 0.0, "note": f"wrong content {lines!r}; " + note}
    if len(patches) == 1:
        return {"score": 1.0, "note": "right first time; " + note}
    return {"score": 0.5, "note": "right in the end; " + note}
