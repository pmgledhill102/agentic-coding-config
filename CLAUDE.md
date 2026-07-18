# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Issue Tracking

This project uses **GitHub Issues** — see
[docs/github-issues-workflow.md](docs/github-issues-workflow.md) for the
conventions (sub-issue hierarchy, P0–P4 priority labels, `type: *` labels,
blocked-by dependencies).

- Create an issue before starting work; close it when the work merges
  (`Closes #<n>` in the PR body closes it automatically)
- Use `gh issue list` or direct reads for anything time-sensitive — never
  `gh search issues`, which is eventually consistent

## Session Completion

**When ending a work session:**

1. **File issues for remaining work** — anything that needs follow-up
2. **Run quality gates** (if code changed) — tests, linters, builds
3. **Update issue status** — close finished work, comment on in-progress items
4. **Push to remote** — work is not complete until `git push` succeeds:

   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** — clear stashes, prune remote branches

## Build & Test

No build step. Quality gates (run before pushing; CI runs the same):

```bash
markdownlint-cli2 "**/*.md"        # markdown lint
shellcheck home/bin/*              # shell scripts (CI scans home/bin/)
HOME=/tmp/chezmoi-test chezmoi init --source . --dry-run  # template sanity
```

## Architecture Overview

The `home/` directory is the chezmoi source that mounts at `~/.claude/`
on every machine (see README for the external/archive mechanics).
Everything at the repo root — `adrs/`, `docs/`, CI config, this file —
is repo-meta and never deploys.

## Conventions & Patterns

- `home/settings.json` and `home/settings.json.md` must change together
  (CI enforces the sync; the `.md` carries the rationale)
- ADRs in `adrs/` record decisions; `docs/` holds workflow docs and runbooks
