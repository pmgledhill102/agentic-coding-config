### 1. Gather state (Tier 1 — one script call, one MCP call)

Two things run here: the gather script, which answers everything local, and one
GitHub MCP query, which answers everything about issues. Neither substitutes for
the other, and both always run.

**(a) The gather script.** It does `git fetch --all --prune --tags` first, resolves the repo's default branch, then fans out its read-only queries in parallel. The script compacts each section's output to keep model-visible context cost low: `fetch`'s body is suppressed on success. Default-branch CI is deliberately **not** gathered here — see step 4 for why, and for the on-demand alternative.

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/start-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `not_a_git_repo` | pre-flight | Only present when the gather ran outside a git repo, in which case it is the **only** section and the script exits 1. Print the line it contains and stop; every other step assumes a repo. |
| `fetch` | 2 (folded in) | Body is empty on success (exit=0). Non-zero = network/auth issue — body contains the error; surface before proceeding. |
| `local_state` | 3, 7 | Includes branch, dirty/clean, ahead/behind upstream, ahead/behind `origin/<default>`, and, under `---origin---`, the remote URL that gives you `<owner>/<repo>` for part (b). |
| `recent_main_commits` | 5 | First line is `count=<N>` (commits that merged into `origin/<default>` since the previous local tip). When non-zero, subsequent lines are `<short-sha> <subject>`, capped at 10. Empty when caught up. |
| `gh_ready`, `gh_assigned` | — | `gh-unavailable` or `gh-unauthorized` on this surface, every time (see §Surface). Ignore both; part (b) is where the issue data comes from. They are still emitted because the script is one file shared with the workstation composition. |
| `claude_drift` | — | `state=absent` on this surface: nothing here is chezmoi-managed, so there is no deployed tree to be behind. Silent skip. |
| `bootstrap_currency` | 5b, 7 | `state=current` = silent skip. `state=no-manifest` = a container built before manifests existed; silent, and it self-heals when the snapshot next expires. `state=pinned` names the ref the environment froze to — report only if something else looks stale. `state=behind` gives `installed=`, `head=` and a `remedy=` line: surface it, because everything the container ships is that old. `state=unknown` = the ref could not be resolved (no network); mention once, do not retry. |

**(b) The issue query.** One MCP call answers both issue sections of the brief.
Send it as soon as you have `<owner>/<repo>` — from the `---origin---` line above, or
from what you already know about the session, in which case it can go in the
same message as the script:

```text
mcp__github__list_issues(owner, repo, state: "OPEN", perPage: 100,
                         fields: ["number", "title", "labels", "assignees", "state"])
```

`fields` is what keeps this affordable: the full response for a 36-issue repo is
around 750 tokens, where an unfiltered one is orders of magnitude larger. Do not
omit it, and do not add `body`.

From that one response:

- **Ready to pick up** — every returned issue, sorted by its `P0`–`P4` label
  (`-` when it has none), top 5 into the brief.
- **In progress** — the same list filtered client-side to issues whose
  `assignees` include the authenticated login. `mcp__github__get_me` supplies
  that login and can be sent in the same message; on a personal repo the owner
  is the same person. Verified on a live sandbox 2026-08-21: 36 open issues
  came back in one page with `assignees` populated
  ([#277](https://github.com/pmgledhill102/agentic-coding-config/issues/277)).

**The one thing this query cannot express** is `-is:blocked`, which the `gh`
route uses to drop blocked issues. So the ready list here is **unfiltered for
blocks** and the brief must say so (step 7) rather than presenting it as a
filtered ready list. Everything else is equivalent.

If the MCP server is unavailable too, both brief lines read `n/a (no GitHub
route)`. An unchecked list must never render as "none".

Rules for interpreting the script's exit codes:

- `exit=0` with empty content: clean result. Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content `not-github`, `jq-unavailable`, `gh-unavailable` or `gh-unauthorized`: expected here; silent skip.
- `exit != 0` with other content: real error — surface it before continuing.
