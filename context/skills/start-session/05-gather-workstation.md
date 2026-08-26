### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, resolves the repo's default branch, then fans out all read-only queries (local branch state, ready/assigned GitHub issues) in parallel. The script compacts each section's output to keep model-visible context cost low: `fetch`'s body is suppressed on success. Default-branch CI is deliberately **not** gathered here — see step 4 for why, and for the on-demand alternative.

```sh
~/.claude/bin/start-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `not_a_git_repo` | pre-flight | Only present when the gather ran outside a git repo, in which case it is the **only** section and the script exits 1. Print the line it contains and stop; every other step assumes a repo. |
| `fetch` | 2 (folded in) | Body is empty on success (exit=0). Non-zero = network/auth issue — body contains the error; surface before proceeding. |
| `local_state` | 3, 7 | Includes branch, dirty/clean, ahead/behind upstream, ahead/behind `origin/<default>`. |
| `recent_main_commits` | 5 | First line is `count=<N>` (commits that merged into `origin/<default>` since the previous local tip). When non-zero, subsequent lines are `<short-sha> <subject>`, capped at 10. Empty when caught up. |
| `gh_ready` | 7 | Content `not-github` / `jq-unavailable` = silent skip. Empty content = no ready work. Otherwise up to 10 pipe-separated rows: `#<n>\|P<pri>\|<title>` (priority `-` when the issue has no `P0`–`P4` label). Ready = open and not directly blocked (`gh issue list --search "is:open -is:blocked"`) — direct blocks only, no transitive query. Already pre-summarised — use rows directly in the brief without further parsing. |
| `gh_assigned` | 7 | Same skip convention as `gh_ready`. Empty content = nothing in flight. Otherwise pipe-separated rows: `#<n>\|P<pri>\|<title>` for open issues assigned to me (usually 0-3). Same row shape as `gh_ready`. |
| `claude_drift` | 5b, 7 | `state=no-source` (not in an a-c-c checkout) = silent skip. `state=compared` gives `behind=<n>` and `modified=<n>`, then one `behind: <path>` / `modified: <path>` line each, plus `remedy_behind=` / `remedy_modified=` when non-zero. Both zero = silent. |
| `bootstrap_currency` | — | `state=not-a-container` on this surface, every time. Silent skip; it is the sandbox composition's check. |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no ready work, nothing assigned, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content `not-github` or `jq-unavailable`: silent skip.
- `exit != 0` with content `gh-unavailable` or `gh-unauthorized`: `gh` is missing from PATH, or signed out. Not expected on this surface — say so once and report the affected brief lines as `n/a (gh absent)`, so a thin brief reads as "not gathered", never as "all clear". Where the client offers a structured GitHub API tool, use it for those two sections rather than reporting nothing.
- `exit != 0` with other content: real error — surface it before continuing.
