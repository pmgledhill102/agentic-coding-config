Start-of-session sync: bring git and GitHub-issue state up-to-date and surface anything that needs your attention before you begin work.

This command runs in a single phase. It mirrors `/end-session`'s shape — parallel state-gather, three-tier action model — but inverted: where `/end-session` leaves things tidy at walk-away, `/start-session` brings local state forward to "ready to work" and prints a one-screen session brief.

## Action tiers

Every step falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase` on the default branch, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: predictable but should be a conscious choice. Example: chaining into `/promote-journal-inbox` when journal drafts are pending. Per-repo opt-in to Tier 1 is available via `.agent-policy` (see below) for users who always say "yes" in a given repo.
- **Tier 3 — surface only, user drives**: needs per-item judgment. Examples: a feature branch trailing `main`, issues left assigned mid-flight from the last session, red `main` CI. **Never** opt-in via `.agent-policy` — these require human judgment by design.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.

## Pre-flight

This command **requires a git-backed repository**. Run the bare command below and branch on its exit code — don't paste a compound `||` / `&&` form, which won't match any single allow rule and will trigger a permission prompt.

```sh
git rev-parse --is-inside-work-tree
```

If the exit code is non-zero (or stdout is not `true`), print a single-line warning (`` `/start-session` requires a git-backed repo — nothing to sync, stopping. ``) and stop.

## Repo-level policy (`.agent-policy`)

**Optional.** A POSIX shell `KEY=VALUE` file at the repo root that opts specific Tier 2 prompts into Tier 1 (auto-run, no prompt) on a per-repo basis. Defaults (file absent or key unset) preserve the prompt — adding the file never makes any repo behave more aggressively than before.

**Supported keys:**

| Key | When `=true` | Affects |
| --- | --- | --- |
| `AUTO_JOURNAL_PROMOTE` | Auto-run `/promote-journal-inbox` when filesystem `_incoming/` count >= 1 — no prompt | Step 6 |

Any value other than `true` is treated as unset. Unknown keys are ignored silently (forward-compatibility).

**Trust model:** the file is sourced as POSIX shell, so a hostile commit could place arbitrary commands in it. Treat `.agent-policy` the same as `.envrc` / `.editorconfig` — only commit it on repos you control, and only opt into automation you actually want. The file lives at the repo root (not under `.claude/`, which is reserved for the harness's own config).

**Example `.agent-policy`:**

```sh
# .agent-policy — opt-in automation for /start-session in this repo
AUTO_JOURNAL_PROMOTE=true
```

## Phase 1 — Sync

If `.agent-policy` exists at the repo root, source it once before proceeding:

```sh
[ -f .agent-policy ] && . ./.agent-policy
```

This loads any opt-in keys consulted by Tier 2 steps. The file is optional; if absent, every Tier 2 step prompts as today.

### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, resolves the repo's default branch, then fans out all read-only queries (local branch state, `main` CI, ready/assigned GitHub issues) in parallel. The script compacts each section's output to keep model-visible context cost low: `fetch`'s body is suppressed on success, and `main_ci` is parsed in-script to one line per workflow.

```sh
~/.claude/bin/start-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `fetch` | 2 (folded in) | Body is empty on success (exit=0). Non-zero = network/auth issue — body contains the error; surface before proceeding. |
| `local_state` | 3, 7 | Includes branch, dirty/clean, ahead/behind upstream, ahead/behind `origin/<default>`. |
| `main_ci` | 4 | Content `gh-unavailable` / `jq-unavailable` = silent skip. Otherwise: first line is `workflows=<N>`; subsequent lines are `<workflow-name>=<conclusion-or-status>@<short-sha>` (one per most-recent run per workflow on `<default>`). On `failure` / `cancelled` / `timed_out`, the line ends with a trailing space-separated run URL: `<workflow-name>=<conclusion>@<short-sha> <url>`. Non-zero with other content = real error. |
| `recent_main_commits` | 5 | First line is `count=<N>` (commits that merged into `origin/<default>` since the previous local tip). When non-zero, subsequent lines are `<short-sha> <subject>`, capped at 10. Empty when caught up. |
| `gh_ready` | 7 | Content `not-github` / `gh-unavailable` / `jq-unavailable` = silent skip. Empty content = no ready work. Otherwise up to 10 pipe-separated rows: `#<n>\|P<pri>\|<title>` (priority `-` when the issue has no `P0`–`P4` label). Ready = open and not directly blocked (`gh issue list --search "is:open -is:blocked"`) — direct blocks only, no transitive query. Already pre-summarised — use rows directly in the brief without further parsing. |
| `gh_assigned` | 7 | Same skip convention as `gh_ready`. Empty content = nothing in flight. Otherwise pipe-separated rows: `#<n>\|P<pri>\|<title>` for open issues assigned to me (usually 0-3). Same row shape as `gh_ready`. |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no ready work, nothing assigned, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content equal to `not-github`, `gh-unavailable`, or `jq-unavailable`: silent skip.
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
- **On a feature branch with unpushed commits** (non-zero `ahead` vs `@{u}`): surface the count. Don't push from here; that's `/end-session`'s job.

Don't switch branches outside of the auto-switch case above.

### 4. `main` CI status (Tier 1 — surface)

From gather section `main_ci`. The script has already deduplicated to one most-recent run per workflow on `<default>` and emitted compact lines: `<workflow-name>=<conclusion-or-status>@<short-sha>`. Failing runs include the URL on the same line: `<workflow-name>=<conclusion>@<short-sha> <url>`.

- **Any line where `<conclusion-or-status>` is `failure` / `cancelled` / `timed_out`**: flag in the session brief with workflow name + short-sha + run URL (the URL is on the same line — surface it inline so the user can click straight through). A red default branch is the loudest "not clean" signal — call it out before the user starts new work.
- **Any line where `<conclusion-or-status>` is `in_progress`**: list with the short-sha. (Elapsed time is no longer captured — gather doesn't track createdAt in the compact form. If you need it, run `gh run list` directly.)
- **All `success`**: silent (the brief reports "green").

If the section content is `gh-unavailable` / `jq-unavailable` or the repo has no remote, skip silently and report `n/a` in the brief.

### 5. Recent merges to `<default>` (Tier 1 — surface)

From gather section `recent_main_commits`. The first line is `count=<N>` — commits that merged into `origin/<default>` since the previous local tip (i.e. the activity the user missed since they last opened this repo). When non-zero, subsequent lines are `<short-sha> <subject>` (capped at 10, oldest-first; topmost line is the most recent).

- **`count=0`**: silent. Caught up.
- **`count >= 1`**: surface a `Recent merges:` block in the session brief listing the entries verbatim. Useful before picking up new work — orients the user on what landed while they were away.

This is informational only — no action prompts. The section adds a few lines on busy days and zero on quiet ones.

### 6. Paul-context inbox surface (Tier 2 — prompt, paul-context only; Tier 1 with policy opt-in)

**Only fires when the current working tree is `paul-context`** (`basename "$(git rev-parse --show-toplevel)" = "paul-context"`). Otherwise skip silently. This is a runtime filesystem check, not part of the gather output — `/start-session` runs in many repos and a generic gather section would always be empty for the rest.

```sh
ls -1 _incoming/ 2>/dev/null
```

Filter the listing to entries matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$` (excludes `README.md` and any non-conforming files). Count the matches.

- **0 matches**: skip silently.
- **>= 1 match**: print the count and (up to first 5) filenames, then:

  - **If `AUTO_JOURNAL_PROMOTE=true` (from `.agent-policy`)**: skip the prompt and invoke `/promote-journal-inbox` directly. Add a `Policy:` line to the session brief noting that the promote fired automatically.
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

Policy:                                             (omit when no policy keys fired)
  AUTO_JOURNAL_PROMOTE=true → promoted <N> draft(s)

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
───────────────────────────────────────────────
```

Rules:

- Sections with nothing to say collapse to a single `none` line; "Needs attention" is omitted entirely when empty.
- "Ready to pick up next" is sourced from gather section `gh_ready`. Each row is already pipe-separated `#<n>|P<pri>|<title>` — split on `|`, sort by priority label (P0 first, `-` last), and emit the top 5. Ready = open and not directly blocked; the filter is direct-blocks-only, so eyeball the blocked icon before claiming work.
- "In progress" is sourced from gather section `gh_assigned`. Same `#<n>|P<pri>|<title>` row shape; no cap (usually 0–3 items).
- "Recent merges" is sourced from gather section `recent_main_commits`. Omit the entire section when `count=0`.
- "Policy" lists each `.agent-policy` key that fired this session (i.e. promoted a Tier 2 prompt to Tier 1 auto-action). Omit the entire section when no keys fired or the file is absent. Don't list keys that were set but had nothing to do (e.g. `AUTO_JOURNAL_PROMOTE=true` with an empty inbox) — only list actual fires.
- If the repo has no GitHub origin (`gh_ready` / `gh_assigned` report `not-github` or are skipped), drop both issue sections silently (the brief still shows git/CI lines).
- Truncate any title to ~78 columns to keep rows on one line.

## Guardrails

- **Pre-flight gate is non-negotiable.** Never proceed when not in a git repo.
- **Never auto-rebase a feature branch** onto an advanced default branch. Surface the gap and stop. The user picks the strategy.
- **Never switch branches except when the upstream is gone and the tree is clean.** That single case (PR merged + branch auto-deleted on remote, no local uncommitted work) is auto-handled per Step 3. Otherwise, `/start-session` reports state on whatever branch the user is on.
- **Don't push anything.** Pushes belong to `/end-session` (for git/`main`). `/start-session` is read-mostly. (Note: if `AUTO_JOURNAL_PROMOTE=true` fires, `/promote-journal-inbox` runs its own commit + push against `paul-context` — that's the promote command's contract, not a carve-out here.)
- **Don't modify settings, config, or unrelated files.** Scope is git and GitHub-issue surface only.
- **`.agent-policy` only promotes Tier 2 → Tier 1 for the keys it explicitly governs.** Tier 3 surfaces (user judgment) cannot be opted in. Unknown keys are ignored silently.
