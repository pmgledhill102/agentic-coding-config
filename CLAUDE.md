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
markdownlint-cli2 "**/*.md"              # markdown lint                       ~1s
sh tests/gcp-credentials-test.sh         # credential-helper behaviour         ~5s
sh tests/precommit-hook-test.sh          # pre-commit hook matching            ~7s
sh tests/bootstrap-failure-test.sh       # a half-installed bootstrap reports itself  ~160s
sh tests/retired-paths.sh                # the prune list is safe and sectioned  <1s
sh tests/retired-paths-test.sh           # ...and its validator still catches    ~1s
python3 tests/compose-context.py         # composed profiles and skills match their fragments  <1s
python3 tests/allowlist-covers-commands.py  # allow rules match documented invocations  <1s
python3 tests/github-repo-standard.py       # the repo-settings spec holds its own invariants  ~1s
sh tests/estate-report-test.sh           # estate flag thresholds and bucketing  <1s

# shell — CI scans home/bin/, cloud/ and tests/. Select by shebang rather than
# globbing: `shellcheck home/bin/*` errors on any non-shell file, and the
# selection is what keeps that from being a tripwire the next time one lands.
find home/bin cloud tests -type f \
  -exec sh -c 'head -1 "$1" | grep -q "^#!.*sh$"' _ {} \; -print0 \
  | xargs -0 shellcheck                  #                                      ~3s
```

**One gate is the whole cost.** `bootstrap-failure-test.sh` runs a bootstrap,
so it takes ~160s of a ~3-minute serial run; every other gate above finishes
in single-digit seconds, ~20s for all of them combined. Timings measured
2026-09-21 in a cloud sandbox and approximate — re-measure rather than trust
them if one looks wrong.

That matters because **an agent's foreground command typically times out at
120s**, which `bootstrap-failure-test.sh` exceeds on its own. The run is not
killed — it continues and passes — but the result is lost and has to be
recovered, which costs more round-trips than the gates cost seconds. So run
the full list **backgrounded** and collect the result when it exits, rather
than in the foreground. Waiting with `sleep N && cat <file>` does not work:
the harness refuses that shape, and wants an `until` loop or a backgrounded
task.

**Run only what the change touches** when the change is narrow — markdown-only
edits need `markdownlint-cli2`; a `context/` edit needs `compose-context.py`;
`home/settings.json` needs the allowlist check. Push-blocking is what the full
list is for, and CI runs it regardless. The fast subset is everything except
`bootstrap-failure-test.sh`, and it is ~20 seconds.

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
- **Comments carry mechanism, not incident history.** A comment earns its place
  if it changes what a future editor does. How the code came to be this way is
  the commit, the issue and the PR — all durable, all linked. The distinction
  that is easy to get wrong: a *surprising fact* stays, because it stops someone
  "correcting" the design back into a bug; the experiment that established it
  goes. Keep "`github.com` 403s this sandbox's curl while its release assets
  resolve fine"; drop "measured 2026-08-18 by planting one and watching a hook
  fire eight seconds later"
- **Anything with a `GENERATED` banner is composed — edit the fragment.**
  `context/manifest.json` says which fragments build which output;
  `context/fragments/` holds policy fragments and `context/skills/` holds
  skill-body fragments. Run `python3 tests/compose-context.py --write` after
  editing one, and commit the regenerated artefacts in the same change. That
  covers `home/{AGENTS,CLAUDE}.md`, everything under `profiles/`, and the
  `start-session` / `end-session` skill and command files
