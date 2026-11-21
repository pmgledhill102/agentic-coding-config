#!/bin/sh
# A script that needs a package, and a Python that behaves like Ubuntu
# 24.04's: `pip install` outside a virtual environment is refused.
set -e
command -v python3 >"$RUN_ROOT/real-python"
command -v uv >"$RUN_ROOT/real-uv"
for name in python3 python pip pip3; do
  cp "$STUBS/pep668-python" "$BIN/$name"
done
cp "$STUBS/pep668-uv" "$BIN/uv"
cd "$PROJ"
git init -q -b main .
cat >report.py <<'PY'
from tabulate import tabulate

ROWS = [("widget", 12, 3.5), ("gasket", 40, 0.75)]
print(tabulate(ROWS, headers=["item", "qty", "unit"], tablefmt="github"))
PY
