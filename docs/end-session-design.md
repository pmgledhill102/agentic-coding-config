# /end-session — Design & Retrospective

This document captures the reasoning behind the `/end-session` slash command's shape — in particular why its Phase 1 gather runs inside a shell script rather than inline.

- Command spec: [`home/commands/end-session.md`](../home/commands/end-session.md)
- Scripts: [`home/bin/`](../home/bin/)

## What `/end-session` does

Single-invocation tidy-up to leave a repo at a verifiable "clean walk-away" point: fetch + prune, rebase `main`, prune dead branches (merged and squash-merged), surface outstanding PRs / stashes / assigned issues / stale Claude files / worktrees, then offer the retrospective.

Every step is classified by how much human judgment it needs:

- **Tier 1** — auto-act, no prompt (fetch, pull, read-only lists).
- **Tier 2** — auto-act behind one batched confirmation (branch deletes, push-if-ahead).
- **Tier 3** — surface only, user drives (open PRs, in-progress issues, stashes, user-started processes).

When in doubt we downgrade a tier rather than upgrade.

## Why the script split exists

Two properties of the harness drove Phase 1's compound blocks into scripts.
Both still hold, and both are what the extraction rules further down are
derived from.

**The permission matcher sees a Bash call as one command string.** A rule like
`Bash(git status *)` matches a call *beginning* with `git status`; it does not
match a compound block that merely contains it alongside other commands. So a
compound block never matches a narrow allow rule, however many of its pieces are
individually allowed. Three fixes were available — pre-approve the exact
compound strings (brittle: any whitespace edit breaks the match), split into N
individual tool calls (works for a sequence, not for a pipeline, and inflates
tool-call count), or extract the logic into a script and allow its path. The
third gives one rule, is shellcheck-testable, and can be edited without
reshuffling permissions.

**Round-trip latency dominates.** Each tool call costs a model turn — emit,
run, read, emit again — and at a large context that is seconds of latency
independent of the command's own runtime. Most of Phase 1's reads are
independent and network-bound, so running them serially multiplied that cost
for no correctness benefit. Fanning them out behind a single `git fetch`
collapses N sequential calls into one, and summed serial latency into
max-of-parallel.

The remaining steps stay serial because they either need a y/n or depend on
prior output. `/retrospective` was deliberately left alone: it is short, has no
multi-line approval blockers, and its value is in agentic reasoning rather than
fixed commands, so parallelising it would buy nothing.

> The original write-up of this section carried the April 2026 measurements
> that motivated the change, including a call to `bd dolt push` from when beads
> was the tracker ([ADR-0013](../adrs/0013-github-issues-for-work-tracking.md)).
> The conclusions above are what survived; the measurement narrative lives in
> the PR that made the change.

## Architecture

```text
/end-session  (home/commands/end-session.md)
    │
    ├── Step 1  → ~/.claude/bin/end-session-gather-state
    │                  │
    │                  ├── git fetch --all --prune --tags   (blocks)
    │                  └── parallel fan-out:
    │                        ├── local_state   (status, branch, log, origin)
    │                        ├── stashes
    │                        ├── worktrees
    │                        ├── merged_brs
    │                        ├── open_prs      (gh pr list)
    │                        ├── gh_assigned   (gh issue list)
    │                        └── stale_claude_files (~/.claude drift scan)
    │
    ├── Steps 2, 3, 6A, 8–12  → read sections from gather output (no tool call)
    ├── Step 4          → prompt on dirty/unpushed (reads local_state)
    ├── Step 5          → git checkout main + git pull --rebase
    ├── Step 6 Batch B  → ~/.claude/bin/end-session-squash-merged
    ├── Step 7          → git log origin/main..HEAD (conditional push)
    ├── Step 13         → background process housekeeping
    └── Step 14         → agent-authored summary
```

## Output protocol — gather script

```text
===<section> (exit=<N>)===
<section stdout+stderr>
```

Sections, in emission order: `fetch`, `local_state`, `stashes`, `worktrees`, `merged_brs`, `open_prs`, `gh_assigned`, `stale_claude_files`.

CI status is deliberately absent from the gather (#273): eager repo-wide CI cost ~104K tokens via the `actions_list` MCP fallback (no server-side reduction, overflows context) to answer a question `/end-session` rarely acts on. It is now queried on demand, scoped to the PR(s) actually touched, via `pull_request_read` `get_check_runs` — see step 3 in the command.

Progress pings go to stderr (`[gather] …`) so a human watching sees something move without polluting the parseable stream on stdout.

### Exit code semantics

| Outcome | Meaning |
| --- | --- |
| `exit=0`, empty content | Clean result — treat as "none". |
| `exit=0`, content | Normal data — parse for the corresponding step. |
| `exit != 0`, content `gh-unavailable` | Silent skip (no `gh` installed). Steps 3 and 8 degrade. |
| `exit != 0`, other content | Real error — surface before continuing Phase 1. |

Sections where empty output is expected (e.g., `merged_brs` grep returning no matches) append `|| true` inside the script so `exit=0` remains meaningful.

## The squash-merged script

Emits branches that satisfy both:

1. `upstream: gone` — the tracking branch was deleted upstream (typical after a GitHub squash-merge + auto-delete).
2. `git diff --quiet main..<branch>` succeeds — the branch's tree is already represented on main.

Both are required. Rule 1 alone would include legitimate un-merged branches whose remote was deleted; rule 2 alone can't easily distinguish branches the user hasn't merged yet. Together, they identify branches whose content has landed via squash-merge and are safe for `-D`.

## Permission model

One allow rule covers both scripts and any future `end-session-*` sibling:

```text
Bash(~/.claude/bin/end-session-*)
```

Scope rationale: the prefix binds to scripts installed from this repo (`home/bin/end-session-*` deploys to `~/.claude/bin/end-session-*`). Scripts outside `~/.claude/bin/` aren't covered, so a rogue `end-session-*` elsewhere on disk still prompts.

If the tilde pattern turns out not to match on some future Claude Code version, the fallback is an absolute path or a `bash $HOME/.claude/bin/end-session-*` form.

## When to extract a step into a script vs keep it inline

Favour a script when any of these hold:

- The block is multi-line / pipelined in a way no single allow rule can match.
- Multiple independent reads can be run in parallel inside it.
- The logic is worth shellcheck-testing in isolation.
- A future reader needs to see "what this step runs" without hunting through markdown.

Keep it inline in the command spec when:

- It's a single shell command that matches an existing allow rule.
- It needs per-item user judgment between sub-commands (would break into separate prompts anyway).
- It's runtime-level (background process state, agent memory) that can't run from a detached shell.

## Rollout

The scripts live in `home/bin/end-session-*` in this repo, committed `100755`. This repo's `home/` is mounted at `~/.claude/` on each machine via a chezmoi archive external declared in [dotfiles](https://github.com/pmgledhill102/dotfiles), so they materialise at `~/.claude/bin/end-session-*` (with exec bit) only after a `chezmoi apply`. On a typical machine that's `dotup`.

This matters because a merged PR to this repo's `main` does not land in `~/.claude/bin/` until chezmoi refreshes the external and applies. The external carries a `refreshPeriod`, so a merge is not picked up instantly. The first `/end-session` invocation on a machine after merging a change here should be preceded by `dotup`.

## Maintenance

- **ShellCheck**: CI's `home/bin/` scan covers the scripts. Run locally with `shellcheck home/bin/end-session-*` before pushing.
- **Paired files**: `settings.json` and `settings.json.md` are paired — any change to the allow rule must update both.
- **Adding a section to the gather**: add a `run_section` or `run_sh` call in the script, extend the section table in `commands/end-session.md`, then add a step (or fold into an existing step) that reads the new section.
- **New sibling script**: name it `end-session-<purpose>` and commit it `100755`; the existing permission rule covers it.

## Non-goals

- **Replacing `/retrospective`'s flow.** It doesn't suffer from the same approval-prompt or latency issues, and its value is in agentic reasoning — parallel gather has nothing to buy.
- **Parallelising the destructive steps.** Tier 2 actions need a y/n each; splitting them across parallel processes would hide prompts.
- **Auto-merging PRs or auto-closing issues.** Explicit non-goal of the command itself (see `Guardrails` in the spec).
