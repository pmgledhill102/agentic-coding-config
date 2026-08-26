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
markdownlint-cli2 "**/*.md"              # markdown lint
sh tests/gcp-credentials-test.sh         # credential-helper behaviour
sh tests/precommit-hook-test.sh          # pre-commit hook matching
sh tests/retired-paths.sh                # the prune list is safe and sectioned
sh tests/retired-paths-test.sh           # ...and its validator still catches
python3 tests/compose-context.py         # composed profiles and skills match their fragments
python3 tests/skills-match-commands.py   # skills match their source commands
python3 tests/allowlist-covers-commands.py  # allow rules match documented commands

# shell — CI scans home/bin/, cloud/ and tests/. Select by shebang: home/bin/
# also holds a Python script, and `shellcheck home/bin/*` errors on it.
find home/bin cloud tests -type f \
  -exec sh -c 'head -1 "$1" | grep -q "^#!.*sh$"' _ {} \; -print0 \
  | xargs -0 shellcheck
```

**There is no chezmoi template check.** This repo contains no chezmoi
templates: it is consumed as an **archive** external, so files deploy verbatim.
The `chezmoi init --dry-run` gate listed here previously was inherited from
`dotfiles`, where templates do exist, and never applied to this repo.

## Architecture Overview

The `home/` directory is the chezmoi source that mounts at `~/.claude/`
on every machine (see README for the external/archive mechanics).
Everything at the repo root — `adrs/`, `docs/`, CI config, this file —
is repo-meta and never deploys.

## Conventions & Patterns

- `home/settings.json` and `home/settings.json.md` must change together
  (CI enforces the sync; the `.md` carries the rationale)
- ADRs in `adrs/` record decisions; `docs/` holds workflow docs and runbooks
- **Anything with a `GENERATED` banner is composed — edit the fragment.**
  `context/manifest.json` says which fragments build which output;
  `context/fragments/` holds policy fragments and `context/skills/` holds
  skill-body fragments. Run `python3 tests/compose-context.py --write` after
  editing one, and commit the regenerated artefacts in the same change. That
  covers `home/{AGENTS,CLAUDE}.md`, everything under `profiles/`, and the
  `start-session` / `end-session` skill and command files
