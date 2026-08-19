---
name: start-session
description: 'Start a work session: sync git and GitHub-issue state, surface open PRs, review comments, failing checks, stale branches and available issues before work begins. Use at the beginning of a session, when the user says they are starting work or picking something up, or when asked what to work on next.'
---

# Start a work session

This command runs in a single phase. It mirrors `end-session`'s shape — parallel state-gather, three-tier action model — but inverted: where `end-session` leaves things tidy at walk-away, `start-session` brings local state forward to "ready to work" and prints a one-screen session brief.

## Action tiers

Every step falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase` on the default branch, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: predictable but should be a conscious choice. Example: chaining into `/promote-journal-inbox` when journal drafts are pending.
- **Tier 3 — surface only, user drives**: needs per-item judgment. Examples: a feature branch trailing `main`, issues left assigned mid-flight from the last session, red `main` CI.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.

## Surface

This command runs on a workstation and in a cloud sandbox, and some steps only
make sense on one of them. Two facts settle every such case:

**Where the helper scripts are.** Prefer the plugin-relative path and fall back
to the chezmoi one:

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/<script>
```

Both spellings are auto-approved in `settings.json`. Under chezmoi the variable
is unset and this resolves to `~/.claude/bin/`; under a plugin install it
resolves inside the plugin. Do not hard-code either.

**Which surface this is.** `command -v chezmoi` is the test. A workstation has
chezmoi and a `~/.claude/` it manages; a sandbox has neither, having been built
by `cloud/bootstrap.sh` from scratch.

Machine-specific steps **detect and skip** — they never error. A skipped step
reports `n/a (sandbox)` in the summary rather than vanishing, so the brief means
the same thing everywhere and a missing line is never ambiguous between "clean"
and "could not check".

## Phase 1 — Sync

Everything starts with one script call. The pre-flight check is inside it, so
this command makes **no standalone Bash calls before the gather**.

### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, resolves the repo's default branch, then fans out all read-only queries (local branch state, `main` CI, ready/assigned GitHub issues) in parallel. The script compacts each section's output to keep model-visible context cost low: `fetch`'s body is suppressed on success, and `main_ci` is parsed in-script to one line per workflow.

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/start-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `not_a_git_repo` | pre-flight | Only present when the gather ran outside a git repo, in which case it is the **only** section and the script exits 1. Print the line it contains and stop; every other step assumes a repo. |
| `fetch` | 2 (folded in) | Body is empty on success (exit=0). Non-zero = network/auth issue — body contains the error; surface before proceeding. |
| `local_state` | 3, 7 | Includes branch, dirty/clean, ahead/behind upstream, ahead/behind `origin/<default>`. |
| `main_ci` | 4 | Content `jq-unavailable` = silent skip; `gh-unavailable` / `gh-unauthorized` = recover via MCP (see exit-code rules). Otherwise: first line is `workflows=<N>`; subsequent lines are `<workflow-name>=<conclusion-or-status>@<short-sha>` (one per most-recent run per workflow on `<default>`). On `failure` / `cancelled` / `timed_out`, the line ends with a trailing space-separated run URL: `<workflow-name>=<conclusion>@<short-sha> <url>`. Non-zero with other content = real error. |
| `recent_main_commits` | 5 | First line is `count=<N>` (commits that merged into `origin/<default>` since the previous local tip). When non-zero, subsequent lines are `<short-sha> <subject>`, capped at 10. Empty when caught up. |
| `gh_ready` | 7 | Content `not-github` / `jq-unavailable` = silent skip; `gh-unavailable` / `gh-unauthorized` = recover via MCP (see exit-code rules). Empty content = no ready work. Otherwise up to 10 pipe-separated rows: `#<n>\|P<pri>\|<title>` (priority `-` when the issue has no `P0`–`P4` label). Ready = open and not directly blocked (`gh issue list --search "is:open -is:blocked"`) — direct blocks only, no transitive query. Already pre-summarised — use rows directly in the brief without further parsing. |
| `gh_assigned` | 7 | Same skip convention as `gh_ready`. Empty content = nothing in flight. Otherwise pipe-separated rows: `#<n>\|P<pri>\|<title>` for open issues assigned to me (usually 0-3). Same row shape as `gh_ready`. |
| `claude_drift` | 6b, 7 | `state=absent` (sandbox, no `~/.claude`) or `state=no-source` (not in an a-c-c checkout) = silent skip. `state=compared` gives `behind=<n>` and `modified=<n>`, then one `behind: <path>` / `modified: <path>` line each, plus `remedy_behind=` / `remedy_modified=` when non-zero. Both zero = silent. |
| `bootstrap_currency` | 6b, 7 | `state=not-a-container` (a workstation) or `state=current` = silent skip. `state=no-manifest` = a container built before manifests existed; silent, and it self-heals when the snapshot next expires. `state=pinned` names the ref the environment froze to — report only if something else looks stale. `state=behind` gives `installed=`, `head=` and a `remedy=` line: surface it, because everything the container ships is that old. `state=unknown` = the ref could not be resolved (no network); mention once, do not retry. |

**On `gh` inside the gather script.** The gather runs as a shell script, so its
GitHub queries use `gh` and cannot use `mcp__github__*` — an MCP tool is not
callable from a subprocess. That is a deliberate exception to the MCP-first
preference, not an oversight. But `gh` is a property of the surface, not a
constant: present on workstations, **absent from Claude cloud sandboxes**, where
those sections return `gh-unavailable` and MCP is the only GitHub route. A
surface can also have `gh` installed yet policy-blocked from repo data — the
sandbox egress proxy authenticates identity endpoints but 403s every
repo-scoped API path (#273) — in which case the sections return
`gh-unauthorized`, which means the same thing: MCP is the only route. When
that happens, recover the data with the MCP equivalents rather than treating the
gap as empty — see the exit-code rules below. Any GitHub op **this command**
performs directly, outside the gather, should prefer MCP.

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no ready work, nothing assigned, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content `not-github` or `jq-unavailable`: silent skip.
- `exit != 0` with content `gh-unavailable` or `gh-unauthorized`: **not silent.** Recover the section with the MCP equivalents when the GitHub MCP server is connected — `mcp__github__actions_list` for `main_ci`, `mcp__github__list_issues` for `gh_ready` / `gh_assigned` — and use the recovered data as if the gather had produced it. Only when MCP is also unavailable, report `n/a (gh absent)` in the brief, so a thin brief reads as "not gathered", never as "all clear".
- `exit != 0` with other content: real error — surface it before continuing.

### 2. Surface fetch result (Tier 1)

Folded into step 1's gather. On success, the `fetch` section is empty (exit=0, no body) — silent pass. If its exit code is non-zero, the body contains the error output; halt the rest of the phase and surface it — every downstream step assumes a successful fetch.

### 3. Sync the default branch (Tier 1 / Tier 3)

Read `local_state`, including the `upstream_status` line (`alive` / `gone` / `none`). Behavior depends on which branch you're on:

- **On the default branch** (`branch` matches `default_branch`) and behind `origin/<default>`: run `git pull --rebase --autostash`. Tier 1.
- **On the default branch** and clean / up-to-date: silent.
- **On a feature branch with `upstream_status=gone` and a clean working tree**: auto-switch back to the default branch and bring it up to date. Tier 1.

  `upstream_status=gone` means an upstream is configured in `.git/config` but its remote ref has been pruned during fetch — the canonical signal that the PR was merged and the branch was auto-deleted on the remote. Run:

  ```sh
  git checkout <default_branch>
  git pull --rebase --autostash
  ```

  Add `auto-switched <feature> → <default> (upstream gone)` as an extra line under `Sync:` in the session brief. Leave the local feature branch in place — never delete it. The user can return to it with `git checkout <feature>` if they need to.

- **On a feature branch with `upstream_status=gone` but the working tree is dirty**: do NOT auto-switch. The dirty work might sit on top of commits that are now squash-merged into `main`, and switching would risk surprising the user. Surface as Tier 3: `<branch>'s upstream is gone (PR merged?) but tree is dirty — commit or stash, then switch manually`.
- **On a feature branch with `upstream_status=alive`** and `default_branch` advanced (`vs origin/<default>` shows non-zero `behind`): surface the count — "`<default>` is N commits ahead of your branch". Do **not** auto-rebase. Tier 3 — the user decides whether to rebase, merge, or carry on.
- **On a feature branch with unpushed commits** (non-zero `ahead` vs `@{u}`): surface the count. Don't push from here; that's `end-session`'s job.

Don't switch branches outside of the auto-switch case above.

### 4. `main` CI status (Tier 1 — surface)

From gather section `main_ci`. The script has already deduplicated to one most-recent run per workflow on `<default>` and emitted compact lines: `<workflow-name>=<conclusion-or-status>@<short-sha>`. Failing runs include the URL on the same line: `<workflow-name>=<conclusion>@<short-sha> <url>`.

- **Any line where `<conclusion-or-status>` is `failure` / `cancelled` / `timed_out`**: flag in the session brief with workflow name + short-sha + run URL (the URL is on the same line — surface it inline so the user can click straight through). A red default branch is the loudest "not clean" signal — call it out before the user starts new work.
- **Any line where `<conclusion-or-status>` is `in_progress`**: list with the short-sha. (Elapsed time is no longer captured — gather doesn't track createdAt in the compact form. If you need it, run `gh run list` directly.)
- **All `success`**: silent (the brief reports "green").

If the content is `jq-unavailable` or the repo has no remote, report `n/a`. On `gh-unavailable` / `gh-unauthorized`, recover via `mcp__github__actions_list` when connected; otherwise report `n/a (gh absent)` — never let an ungathered section read as "green".

### 5. Recent merges to `<default>` (Tier 1 — surface)

From gather section `recent_main_commits`. The first line is `count=<N>` — commits that merged into `origin/<default>` since the previous local tip (i.e. the activity the user missed since they last opened this repo). When non-zero, subsequent lines are `<short-sha> <subject>` (capped at 10, oldest-first; topmost line is the most recent).

- **`count=0`**: silent. Caught up.
- **`count >= 1`**: surface a `Recent merges:` block in the session brief listing the entries verbatim. Useful before picking up new work — orients the user on what landed while they were away.

This is informational only — no action prompts. The section adds a few lines on busy days and zero on quiet ones.

### 5b. Deployed-config drift (Tier 1 — surface, never act)

### Is this container running current config?

From gather section `bootstrap_currency`. The container equivalent of the
drift check below: a cloud environment restores a filesystem snapshot and
re-runs its setup script only when the script text changes, the allowed hosts
change, or roughly seven days pass — so pushing to a branch does not reach new
sessions, and a sandbox can be running week-old skills, policy and helper
scripts with nothing saying so.

On `state=behind`, say so plainly and give the remedy: re-running the bootstrap
takes effect immediately and needs no restart. Everything the container
delivers — skills, policy, helpers — is as old as that SHA, so it is worth
one line at the top of the brief rather than a footnote.

Two honest limits, worth knowing rather than implying more than it does. The
check ships inside the thing it checks, so a container older than the check
cannot report it — that resolves itself after one cache cycle, not immediately.
And this runs only when start-session runs; it is advisory, not a guarantee.

From gather section `claude_drift`. Answers a question nothing else asks: does
`~/.claude/` on this machine still match what the repo says it should be?

A chezmoi-managed file can be fixed in the repo and go on running the old
version here for as long as nobody applies. The failure is not forgetting to
apply — it is that nothing distinguishes "this machine is current" from "this
machine is a day behind", so there is nothing to forget about. It has already
cost a session: two merged commits to `bin/gcp-credentials` were undeployed
while the cloud surface had them, so local and cloud disagreed on the behaviour
of a security control and an issue was filed against a defect already fixed.

- **`state=absent` or `state=no-source`**: silent skip. A sandbox has nothing
  deployed; outside an a-c-c checkout there is nothing to compare against
  without a network fetch, which is not worth every session start.
- **`behind=0 modified=0`**: silent. This is the normal case and should stay
  invisible.
- **`behind >= 1`**: surface under **Needs attention** in the brief, naming the
  count and the files, with the remedy verbatim from `remedy_behind`. The
  command is `chezmoi apply --refresh-externals`, **not** a plain `chezmoi
  apply` — the archive external's 168h refresh period means a plain apply can
  re-serve the cached copy.
- **`modified >= 1`**: surface separately, and do not conflate it with the
  above. A hand-edited file in `~/.claude/` is a different problem with a
  different fix — the edit is lost on the next apply, so it needs moving into
  the repo. Reporting both as one number makes the message ignorable.

**Never apply anything, and never offer to.** This is Tier 1 surface-only by
design: applying config changes under an agent without the human reading them
is its own hazard, and this repo deploys the harness the agent is running
inside.

### 6. Paul-context inbox surface (Tier 2 — prompt, paul-context only)

**Only fires when the current working tree is `paul-context`** (`basename "$(git rev-parse --show-toplevel)" = "paul-context"`). Otherwise skip silently. This is a runtime filesystem check, not part of the gather output — `start-session` runs in many repos and a generic gather section would always be empty for the rest.

```sh
ls -1 _incoming/ 2>/dev/null
```

Filter the listing to entries matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$` (excludes `README.md` and any non-conforming files). Count the matches.

- **0 matches**: skip silently.
- **>= 1 match**: print the count and (up to first 5) filenames, then:

  - **Otherwise (default)**: prompt:

    > `<N>` journal draft(s) pending in `_incoming/`. Run `/promote-journal-inbox` now? (y/n)

    - **yes** → invoke `/promote-journal-inbox` directly. That command's pre-flight verifies cwd, then drains both filesystem `_incoming/` and `journal-draft`-labeled Issues from `pmgledhill102/paul-context`, commits each draft separately, single-pushes, and closes the drained Issues. Carry the result into the session brief.
    - **no / empty / cancel** → carry on. Surface the count in the session brief under "Needs attention" so it's visible at a glance.

Note: this surface only counts the **filesystem** half of the inbox. The Issue-side half (sandbox-fallback drafts) isn't enumerated here — surfacing it would require an extra `gh issue list --label journal-draft` call, and the filesystem count is the dominant signal because the local machine is where the user lives. `/promote-journal-inbox` itself drains both inboxes when invoked, so user action is consistent regardless of which path filed the draft.

### 7. Session brief (Tier 1 — final summary)

Always print, even when everything is clean. This is the user-facing payoff — one screenful, scannable, no surprises. Format:

```text
── Session brief ──────────────────────────────
Repo:     <repo>             Branch: <branch> (<clean|dirty>)
Sync:     <default> <ahead/behind/even>   upstream <ahead/behind/even/gone/n/a>
          [auto-switched <feature> → <default> (upstream gone)]    (only when Step 3 auto-switched)
CI:       <green / N failing / N in-progress / n/a>

Recent merges:                                      (omit when count=0)
  <short-sha>  <commit subject>
  …                                                 (cap at gather's 10)

In progress (assigned to you):
  #<n>  P<pri>  <title>            (or "none")

Ready to pick up next:
  #<n>  P<pri>  <title>            (top 5 by priority; or "none — backlog empty")
  …

Needs attention:
  • <pending journal drafts: N>    (omit when 0 / not paul-context)
  • <main CI red on workflow X>    (omit when green)
  • <feature branch behind main by N>          (omit when on default, even, or auto-switched)
  • <branch upstream gone but tree dirty>      (omit unless that case fires)
  • ~/.claude is behind the repo on N file(s): <paths> — run `chezmoi apply --refresh-externals`
                                               (omit when behind=0 / skipped)
  • ~/.claude has N hand-edited file(s): <paths> — the edits are lost on the next
    apply; move them into the repo    (omit when modified=0 / skipped)
───────────────────────────────────────────────
```

Rules:

- Sections with nothing to say collapse to a single `none` line; "Needs attention" is omitted entirely when empty.
- "Ready to pick up next" is sourced from gather section `gh_ready`. Each row is already pipe-separated `#<n>|P<pri>|<title>` — split on `|`, sort by priority label (P0 first, `-` last), and emit the top 5. Ready = open and not directly blocked; the filter is direct-blocks-only, so eyeball the blocked icon before claiming work.
- "In progress" is sourced from gather section `gh_assigned`. Same `#<n>|P<pri>|<title>` row shape; no cap (usually 0–3 items).
- "Recent merges" is sourced from gather section `recent_main_commits`. Omit the entire section when `count=0`.
- If the repo has no GitHub origin (`gh_ready` / `gh_assigned` report `not-github` or are skipped), drop both issue sections silently (the brief still shows git/CI lines).
- Truncate any title to ~78 columns to keep rows on one line.

## Guardrails

- **Pre-flight gate is non-negotiable.** Never proceed when not in a git repo.
- **Never auto-rebase a feature branch** onto an advanced default branch. Surface the gap and stop. The user picks the strategy.
- **Never switch branches except when the upstream is gone and the tree is clean.** That single case (PR merged + branch auto-deleted on remote, no local uncommitted work) is auto-handled per Step 3. Otherwise, `start-session` reports state on whatever branch the user is on.
- **Don't push anything.** Pushes belong to `end-session` (for git/`main`). `start-session` is read-mostly. (Note: if the user says yes to the journal-promote prompt, `/promote-journal-inbox` runs its own commit + push against `paul-context` — that's the promote command's contract, not a carve-out here.)
- **Don't modify settings, config, or unrelated files.** Scope is git and GitHub-issue surface only.
