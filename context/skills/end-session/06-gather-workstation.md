### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, then fans out all read-only queries (status/branch/log, stashes, worktrees, merged branches, open PRs, assigned GitHub issues) in parallel. Default-branch CI is deliberately not gathered — see step 3.

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/end-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `fetch` | 2 (folded in) | Non-zero = network/auth issue — surface before proceeding. |
| `local_state` | 1, 4 | Dirty tree + unpushed commits for step 4. |
| `stashes` | 9 | Exit 0 even when empty. |
| `worktrees` | 13 | Exit 0 even when empty. |
| `merged_brs` | 6 Batch A | Script appends `\|\| true` — exit 0 even if no matches. |
| `open_prs` | 8 | Empty content = no open PRs. Otherwise one row per open PR authored by me. |
| `gh_assigned` | 10 | Content `not-github` / `jq-unavailable` = silent skip. Empty content = nothing in flight. Otherwise one `#<n> <title>` line per open issue assigned to me. |
| `stale_claude_files` | 11 | Content `chezmoi-unavailable` = silent skip. Empty body (exit=0) = nothing stale. Otherwise: one path per line under `.claude/commands/` or `.claude/bin/` that's present locally but not tracked by chezmoi. |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no stashes, no merged branches, no in-progress issues, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content `not-github` or `jq-unavailable`: silent skip.
- `exit != 0` with content `gh-unavailable` or `gh-unauthorized`: `gh` is missing from PATH, or signed out. Not expected on this surface — say so once and report the affected summary lines as `n/a (gh absent)`, never as "none". Where the client offers a structured GitHub API tool, use it for those sections rather than reporting nothing.
- `exit != 0` with other content: real error — surface it before continuing Phase 1.
