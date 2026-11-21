#!/bin/sh
# A clone with a bare repository as origin, a pushed feature branch, and a
# gh stand-in that reports pull request #12 open for it.
set -e
git init -q --bare -b main "$RUN_ROOT/origin.git"
git clone -q "$RUN_ROOT/origin.git" "$PROJ" 2>/dev/null
cd "$PROJ"
git config user.name dev
git config user.email dev@example.invalid
mkdir src
cat >README.md <<'MD'
# greeter

Prints a greeting.

```console
$ python3 src/greet.py Sam
Hello, Sam!
```
MD
cat >src/greet.py <<'PY'
import sys


def greet(name):
    return f"Hello, {name}!"


if __name__ == "__main__":
    print(greet(sys.argv[1]))
PY
git add -A
git commit -q -m "Initial greeter"
git push -q -u origin main
git checkout -q -b feature/greeting-text
sed -i '1i """Greeting helpers."""' src/greet.py
git commit -q -am "Add a module docstring"
git push -q -u origin feature/greeting-text

cp "$STUBS/gh-pr" "$BIN/gh"
cat >"$RUN_ROOT/gh-state.json" <<'JSON'
{"prs": [{"number": 12, "state": "OPEN", "title": "Friendlier greeting text",
  "headRefName": "feature/greeting-text", "baseRefName": "main",
  "url": "https://github.com/example-org/greeter/pull/12",
  "mergedAt": null, "closed": false}]}
JSON
