Start-of-session sync: bring git, beads, and GitHub-issue state up-to-date and surface anything that needs your attention before you begin work.

This command runs in a single phase. It mirrors `/end-session`'s shape — parallel state-gather, three-tier action model — but inverted: where `/end-session` leaves things tidy at walk-away, `/start-session` brings local state forward to "ready to work" and prints a one-screen session brief.

## Action tiers

Every step falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase` on the default branch, `bd dolt pull`, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: predictable but should be a conscious choice. Example: chaining into `/bd-import-github-issues` when unmigrated GitHub issues exist.
- **Tier 3 — surface only, user drives**: needs per-item judgment. Examples: a feature branch trailing `main`, in-progress beads left mid-flight from the last session, red `main` CI.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.

## Pre-flight

This command **requires a git-backed repository**. Run the bare command below and branch on its exit code — don't paste a compound `||` / `&&` form, which won't match any single allow rule and will trigger a permission prompt.

```sh
git rev-parse --is-inside-work-tree
```

If the exit code is non-zero (or stdout is not `true`), print a single-line warning (`` `/start-session` requires a git-backed repo — nothing to sync, stopping. ``) and stop.

## Phase 1 — Sync

### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, resolves the repo's default branch, then fans out all read-only queries (local branch state, `main` CI, beads remote/ready/in-progress, unmigrated GH issues) in parallel. The script compacts each section's output to keep model-visible context cost low: `fetch`'s body is suppressed on success, `main_ci` is parsed in-script to one line per workflow, and the previously-emitted `bd_preflight` section is gone (its `bd preflight` template output was Go-specific and not actionable on most projects).

```sh
~/.claude/bin/start-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `fetch` | 2 (folded in) | Body is empty on success (exit=0). Non-zero = network/auth issue — body contains the error; surface before proceeding. |
| `local_state` | 3, 9 | Includes branch, dirty/clean, ahead/behind upstream, ahead/behind `origin/<default>`. |
| `main_ci` | 7 | Content `gh-unavailable` / `jq-unavailable` = silent skip. Otherwise: first line is `workflows=<N>`; subsequent lines are `<workflow-name>=<conclusion-or-status>@<short-sha>` (one per most-recent run per workflow on `<default>`). On `failure` / `cancelled` / `timed_out`, the line ends with a trailing space-separated run URL: `<workflow-name>=<conclusion>@<short-sha> <url>`. Non-zero with other content = real error. |
| `gh_unmigrated` | 8 | Content `gh-unavailable` or `jq-unavailable` = silent skip. First line is `count=<N>`; remaining lines are `#<n> <title>` per unmigrated issue. |
| `bd_remote` | 4 | Section absent if no beads workspace. Empty content = no remote configured (single-machine setup). |
| `bd_ready` | 9 | Section absent if no beads workspace. Empty content = no ready work. Otherwise up to 5 pipe-separated rows: `<id>\|P<n>\|<title>`. Already pre-summarised — use rows directly in the brief without further parsing. |
| `bd_in_progress` | 9 | Section absent if no beads workspace. Empty content = nothing in flight. Otherwise pipe-separated rows: `<id>\|P<n>\|<title>` (no limit; usually 0-3). Same row shape as `bd_ready`. |
| `bd_inprogress_delivered` | 5 | Section absent if no beads workspace. Empty content = nothing to auto-close. Each line is `<id>\|<short-sha>\|<subject>` for an in_progress bead whose ID was referenced by a merged commit on `<default>` (`Closes <id>` / `Fixes <id>`). |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no remote configured, no in-progress issues, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content equal to `gh-unavailable` or `jq-unavailable`: silent skip.
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

### 4. Beads Dolt pull (Tier 1)

If there's no beads workspace (`bd_remote` section absent), skip silently.

If the `bd_remote` section is empty (no remote configured — typical for a single-machine project), print one line: `(no Dolt remote — skipping pull)`, and continue.

Otherwise run:

```sh
bd dolt pull
```

If it fails (auth, network, or genuine conflict), halt the phase and surface the error verbatim. Do **not** attempt auto-merge or auto-resolve — the user needs to fix this manually before continuing. Mention the v1.81.10 credential-prompt workaround documented in `/bd-modernize` step 5d if the failure looks like it.

### 5. Auto-close delivered in_progress beads (Tier 1)

Read gather section `bd_inprogress_delivered` (absent if no beads workspace; empty if nothing matched). Each line is `<id>|<short-sha>|<subject>` — an `in_progress` bead whose ID was referenced by a merged commit on the default branch with `Closes <id>` or `Fixes <id>` in the message.

These are deliveries that never got their bead closed. The PR was already reviewed and merged; closing the bead is bookkeeping, not a judgment call. Auto-close each one — no prompt:

```sh
bd close <id> --reason="Auto-closed by /start-session: shipped via <short-sha>"
```

After all auto-closes, run `bd dolt push` once so the closures persist to the remote (otherwise a second machine that pulls afterwards re-detects the same beads as in_progress and re-closes them — harmless but noisy). This is a deliberate carve-out from the general "don't push" guardrail; it's the only push `/start-session` ever issues.

If the section is absent, empty, or nothing matched: skip silently. The session brief shows an `Auto-closed (delivered):` line listing what was closed (omit the line entirely when nothing was closed).

False-positive risk is low: a stray `Closes <bead-id>` reference in a non-closing context would trigger a spurious close. If hit, recovery is `bd reopen <id>` — Tier 1 acceptable in exchange for not having to manually close every shipped bead.

### 6. (removed) — Beads preflight is no longer collected

`bd preflight`'s output is a Go-specific PR-readiness checklist (`go test`, `golangci-lint`, `gofmt`, …) that produces no useful signal on non-Go projects and was largely noise in the brief. If you want to run those checks for a specific repo where they apply, invoke `bd preflight --check` directly outside `/start-session`.

### 7. `main` CI status (Tier 1 — surface)

From gather section `main_ci`. The script has already deduplicated to one most-recent run per workflow on `<default>` and emitted compact lines: `<workflow-name>=<conclusion-or-status>@<short-sha>`. Failing runs include the URL on the same line: `<workflow-name>=<conclusion>@<short-sha> <url>`.

- **Any line where `<conclusion-or-status>` is `failure` / `cancelled` / `timed_out`**: flag in the session brief with workflow name + short-sha + run URL (the URL is on the same line — surface it inline so the user can click straight through). A red default branch is the loudest "not clean" signal — call it out before the user starts new work.
- **Any line where `<conclusion-or-status>` is `in_progress`**: list with the short-sha. (Elapsed time is no longer captured — gather doesn't track createdAt in the compact form. If you need it, run `gh run list` directly.)
- **All `success`**: silent (the brief reports "green").

If the section content is `gh-unavailable` / `jq-unavailable` or the repo has no remote, skip silently and report `n/a` in the brief.

### 8. Unmigrated GitHub Issues (Tier 2 — prompt)

From gather section `gh_unmigrated`. The first line is `count=<N>`; remaining lines are `#<number> <title>` per unmigrated issue.

- **`gh-unavailable` / `jq-unavailable` / no remote**: skip silently.
- **`count=0`**: silent.
- **`count > 0`**: print the count and (up to) the first 5 titles, then prompt:

  > `<N>` open GitHub issue(s) haven't been imported into beads yet. Run `/bd-import-github-issues` now? (y/n)

  - **yes** → invoke `/bd-import-github-issues` directly. That command does its own `bd dolt pull` (Step 0) and `bd dolt push` (Step 8); a second pull right after step 4 is a clean no-op, and the push at the end is what we want anyway.
  - **no / empty / cancel** → carry on. Surface the count in the session brief under "Needs attention" so it's visible at a glance.

### 8.5. Paul-context inbox surface (Tier 2 — prompt, paul-context only)

**Only fires when the current working tree is `paul-context`** (`basename "$(git rev-parse --show-toplevel)" = "paul-context"`). Otherwise skip silently. This is a runtime filesystem check, not part of the gather output — `/start-session` runs in many repos and a generic gather section would always be empty for the rest.

```sh
ls -1 _incoming/ 2>/dev/null
```

Filter the listing to entries matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$` (excludes `README.md` and any non-conforming files). Count the matches.

- **0 matches**: skip silently.
- **>= 1 match**: print the count and (up to first 5) filenames, then prompt:

  > `<N>` journal draft(s) pending in `_incoming/`. Run `/promote-journal-inbox` now? (y/n)

  - **yes** → invoke `/promote-journal-inbox` directly. That command's pre-flight verifies cwd, then drains both filesystem `_incoming/` and `journal-draft`-labeled Issues from `pmgledhill102/paul-context`, commits each draft separately, single-pushes, and closes the drained Issues. Carry the result into the session brief.
  - **no / empty / cancel** → carry on. Surface the count in the session brief under "Needs attention" so it's visible at a glance.

Note: this surface only counts the **filesystem** half of the inbox. The Issue-side half (sandbox-fallback drafts) isn't enumerated here — surfacing it would require an extra `gh issue list --label journal-draft` call, and the filesystem count is the dominant signal because the local machine is where the user lives. `/promote-journal-inbox` itself drains both inboxes when invoked, so user action is consistent regardless of which path filed the draft.

### 9. Session brief (Tier 1 — final summary)

Always print, even when everything is clean. This is the user-facing payoff — one screenful, scannable, no surprises. Format:

```text
── Session brief ──────────────────────────────
Repo:     <repo>             Branch: <branch> (<clean|dirty>)
Sync:     <default> <ahead/behind/even>   upstream <ahead/behind/even/gone/n/a>
          [auto-switched <feature> → <default> (upstream gone)]    (only when Step 3 auto-switched)
Dolt:     <pulled / up-to-date / no remote / FAILED>
CI:       <green / N failing / N in-progress / n/a>

Auto-closed (delivered):                            (omit when none)
  <id>  via <short-sha>  <commit subject>

In progress (you left these mid-flight):
  <id>  P<pri>  <title>            (or "none")

Ready to pick up next:
  <id>  P<pri>  <title>   est:<n>  (top 5 by priority, then est)
  …                                 (or "none — backlog empty")

Needs attention:
  • <unmigrated GH issues: N>      (omit when 0 / n/a)
  • <pending journal drafts: N>    (omit when 0 / not paul-context)
  • <main CI red on workflow X>    (omit when green)
  • <feature branch behind main by N>          (omit when on default, even, or auto-switched)
  • <branch upstream gone but tree dirty>      (omit unless that case fires)
───────────────────────────────────────────────
```

Rules:

- Sections with nothing to say collapse to a single `none` line; "Needs attention" is omitted entirely when empty.
- "Ready to pick up next" is sourced from gather section `bd_ready`. Each row is already pipe-separated `<id>|P<n>|<title>` and pre-truncated to 5 — split on `|` and emit. `bd ready` already filters to issues whose blockers are all closed and sorts sensibly; preserve the gather order.
- "In progress" is sourced from gather section `bd_in_progress`. Same `<id>|P<n>|<title>` row shape; no cap (usually 0–3 items). Note: any beads auto-closed in Step 5 won't appear here — they're already closed by the time the brief renders.
- "Auto-closed (delivered)" is sourced from the IDs Step 5 closed. Omit the entire section when Step 5 closed nothing.
- If the repo has no beads workspace, drop both Beads sections silently (the brief still shows git/CI/GH lines).
- Truncate any title to ~78 columns to keep rows on one line.

## Guardrails

- **Pre-flight gate is non-negotiable.** Never proceed when not in a git repo.
- **Never auto-rebase a feature branch** onto an advanced default branch. Surface the gap and stop. The user picks the strategy.
- **Never switch branches except when the upstream is gone and the tree is clean.** That single case (PR merged + branch auto-deleted on remote, no local uncommitted work) is auto-handled per Step 3. Otherwise, `/start-session` reports state on whatever branch the user is on.
- **`bd dolt pull` failures halt the phase.** Don't attempt auto-resolve, don't fall back to JSONL, don't rebuild the DB. Surface and stop.
- **Don't push anything except the auto-close result in Step 5.** Pushes generally belong to `/end-session` (for git/`main`) and `/bd-import-github-issues` (for beads after import). The single carve-out is Step 5's `bd dolt push` after auto-closing delivered in_progress beads — that push is what makes the auto-close cross-machine durable. `/start-session` is otherwise read-mostly.
- **Don't modify settings, config, or unrelated files.** Scope is git, beads, and GitHub-issue surface only.
