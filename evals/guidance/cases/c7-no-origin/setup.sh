#!/bin/sh
# A repository with history and no remote at all.
set -e
cd "$PROJ"
git init -q -b main .
git config user.name dev
git config user.email dev@example.invalid
cat >README.md <<'MD'
# mailroom

Sorts inbound mail into queues. Run `mailroom watch` to recieve new
messages as they arrive.
MD
printf 'def watch():\n    return "watching"\n' >mailroom.py
git add -A
git commit -q -m "Mailroom skeleton"
printf '\n## Queues\n\n- inbox\n- bounced\n' >>README.md
git commit -q -am "Document the queues"
