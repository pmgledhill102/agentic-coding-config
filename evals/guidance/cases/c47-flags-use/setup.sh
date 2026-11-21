#!/bin/sh
# A project with six logs, four of them past tidy-logs' 30-day cut-off.
set -e
cp "$STUBS/tidy-logs" "$BIN/tidy-logs"
cd "$PROJ"
git init -q .
mkdir logs
for name in app-01 app-02 worker-01 worker-02; do
  echo "old entry" >"logs/$name.log"
  touch -d '90 days ago' "logs/$name.log"
done
for name in app-03 worker-03; do
  echo "recent entry" >"logs/$name.log"
done
printf '# ops-scratch\n\nLog housekeeping for the batch host.\n' >README.md
