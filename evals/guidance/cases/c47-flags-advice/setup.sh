#!/bin/sh
# A small docs repo whose CI lints Markdown; the question is about that step.
set -e
cd "$PROJ"
git init -q .
mkdir -p docs .github/workflows
printf '# handbook\n\nTeam handbook.\n' >README.md
printf '# Setup\n\nInstall the tools, then run the linter.\n' >docs/setup.md
cat >.github/workflows/lint.yml <<'YAML'
name: lint
on: [pull_request]
jobs:
  markdown:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: markdownlint-cli2 "**/*.md"
YAML
