#!/bin/sh
# A docs repo with lint findings. markdownlint-cli2 is already on PATH, so
# nothing is installed or wrapped: the grader reads the commands that ran.
set -e
cd "$PROJ"
git init -q -b main .
mkdir docs
printf 'config:\n  MD013: false\n' >.markdownlint-cli2.yaml
# shellcheck disable=SC2016  # the backticks are Markdown, not a command
printf '# fieldnotes\n\nNotes from site visits.  \n\n\n## Layout\n- `docs/` holds one file per visit\n- `README.md` is this file\n' >README.md
printf '# Visit template\n## Before you go\n* charge the tablet\n* print the checklist\n\n## On site\nRecord readings every hour.' >docs/template.md
