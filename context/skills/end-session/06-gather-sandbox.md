### 1. Gather state (Tier 1 — one script call, two MCP calls)

Two things run here: the gather script, which answers everything local, and two
GitHub MCP queries, which answer everything about issues and PRs. Neither
substitutes for the other, and all three always run.

**(a) The gather script.** It does `git fetch --all --prune --tags` first, then fans out its read-only queries (status/branch/log, stashes, worktrees, merged branches) in parallel. Default-branch CI is deliberately not gathered — see step 3.

```sh
~/.claude/bin/end-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `fetch` | 2 (folded in) | Non-zero = network/auth issue — surface before proceeding. |
| `local_state` | 1, 4 | Dirty tree + unpushed commits for step 4, and, under `---origin---`, the remote URL that gives you `<owner>/<repo>` for part (b). |
| `stashes` | 9 | Exit 0 even when empty. |
| `worktrees` | 13 | Exit 0 even when empty. |
| `merged_brs` | 6 Batch A | Script appends `\|\| true` — exit 0 even if no matches. |
| `open_prs`, `gh_assigned` | — | `gh-unavailable` or `gh-unauthorized` on this surface, every time (see §Surface). Ignore both; part (b) is where that data comes from. They are still emitted because the script is one file shared with the workstation composition. |
| `stale_claude_files` | — | `chezmoi-unavailable` on this surface, every time. Silent skip; step 11 says why. |
| `gcp_projects` | 14 | Always exit 0. First line is `state=` (`no-grant` / `grant` / `helper-unavailable`); `created=` lines follow only when this session's approval built the repo's sandbox project. Step 14 has the mapping, including why `no-grant` and `none` are different answers. |

**(b) The GitHub queries.** Two calls, sendable together as soon as you have
`<owner>/<repo>` from the `---origin---` line:

```text
mcp__github__list_issues(owner, repo, state: "OPEN", perPage: 100,
                         fields: ["number", "title", "labels", "assignees", "state"])
mcp__github__list_pull_requests(owner, repo, state: "open")
```

`fields` on the issue call is what keeps it affordable — around 750 tokens for
a 36-issue repo, against orders of magnitude more unfiltered. Do not omit it,
and do not add `body`.

- **Issues assigned to you** (step 10) — filter the issue response client-side
  to issues whose `assignees` include the authenticated login.
  `mcp__github__get_me` supplies that login and can go in the same message; on
  a personal repo the owner is the same person. Verified on a live sandbox
  2026-08-21: 36 open issues came back in one page with `assignees` populated
  ([#277](https://github.com/pmgledhill102/agentic-coding-config/issues/277)).
- **Open PRs** (step 8) — the PR response directly. One honest difference from
  the `gh` route: it filters to `--author @me` and `list_pull_requests` has no
  author filter, so this lists **all** open PRs on the repo. Equivalent on a
  personal repo; worth a caveat line anywhere it is not.

If the MCP server is unavailable too, both summary lines read `n/a (no GitHub
route)`. An unchecked list must never render as "none".

Rules for interpreting the script's exit codes:

- `exit=0` with empty content: clean result. Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content `not-github`, `jq-unavailable`, `chezmoi-unavailable`, `gh-unavailable` or `gh-unauthorized`: expected here; silent skip.
- `exit != 0` with other content: real error — surface it before continuing Phase 1.
