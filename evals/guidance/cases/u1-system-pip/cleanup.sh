#!/bin/sh
# If a run got the package into the real interpreter anyway, take it out
# again so the next run starts from the same place, and say so.
real=$(cat "$RUN_ROOT/real-python")
if "$real" -c 'import tabulate' 2>/dev/null; then
  echo "polluted" >>"$RUN_ROOT/logs/pip.log"
  "$real" -m pip uninstall -y -q tabulate >/dev/null 2>&1
fi
exit 0
