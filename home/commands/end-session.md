End-of-session tidy-up: leave git, GitHub, and Claude Code state at a verifiable "clean walk-away" point, then optionally run the retrospective.

This command runs in two phases. Phase 1 is the tidy-up (mix of auto-actions and confirmations). Phase 2 is a prompt to kick off the retrospective. The retrospective itself is read-only — it only updates `~/.claude/retros.md` — so all repo-state changes must happen in Phase 1.

## Action tiers

Every step in Phase 1 falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase`, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: destructive but predictable, judgment is yes/no for the whole list. Examples: deleting merged branches, deleting squash-merged branches, pushing `main` if ahead. Per-repo opt-in to Tier 1 is available via `.agent-policy` (see below) for users who always say "yes" in a given repo.
- **Tier 3 — surface only, user drives**: needs per-item judgment, or affects shared state in ways one y/n can't capture. Examples: open PRs awaiting merge, open issues still assigned to you, stashes, user-started background processes. **Never** opt-in via `.agent-policy` — these require human judgment by design.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.

## Pre-flight

This command **requires a git-backed repository**. Run the bare command below and branch on its exit code — don't paste a compound `||` / `&&` form, which won't match any single allow rule and will trigger a permission prompt.

```sh
git rev-parse --is-inside-work-tree
```

If the exit code is non-zero (or stdout is not `true`), print a single-line warning (`` `/end-session` requires a git-backed repo — nothing to tidy, stopping. ``) and stop. Do not run any further checks, do not proceed to Phase 2.

## Repo-level policy (`.agent-policy`)

**Optional.** A POSIX shell `KEY=VALUE` file at the repo root that opts specific Tier 2 prompts into Tier 1 (auto-run, no prompt) on a per-repo basis. The file is shared with `/start-session` (which has its own keys); each command consults the keys it cares about. Defaults (file absent or key unset) preserve every prompt — adding the file never makes any repo behave more aggressively than before.

**Supported keys (this command):**

| Key | When `=true` | Affects |
| --- | --- | --- |
| `AUTO_DELETE_MERGED_BRANCHES` | Auto-delete Batch A (`-d`, fully merged into `origin/main`) — no prompt | Step 6 Batch A |
| `AUTO_DELETE_SQUASH_MERGED_BRANCHES` | Auto-delete Batch B (`-D`, squash-merged with the safety net check) — no prompt | Step 6 Batch B |
| `AUTO_PUSH_MAIN_IF_AHEAD` | Auto-push `main` when local is ahead of `origin/main` — no prompt | Step 7 |

Any value other than `true` is treated as unset. Unknown keys (including `/start-session`'s own keys when read by this command) are ignored silently.

**Trust model:** the file is sourced as POSIX shell, so a hostile commit could place arbitrary commands in it. Treat `.agent-policy` the same as `.envrc` / `.editorconfig` — only commit it on repos you control, and only opt into automation you actually want.

**Note on the two delete keys:** Batch A and Batch B are separate keys deliberately. Batch A uses `-d` and only succeeds for branches with reachable upstream history — fully safe. Batch B uses `-D` (force) and relies on a safety net (empty diff vs `main` OR a merged PR via `gh`) to identify squash-merged work. Some users will trust Batch A but want to keep Batch B prompted.

**Example `.agent-policy`:**

```sh
# .agent-policy — opt-in automation for /end-session in this repo
AUTO_DELETE_MERGED_BRANCHES=true
AUTO_PUSH_MAIN_IF_AHEAD=true
# Leave AUTO_DELETE_SQUASH_MERGED_BRANCHES unset to keep the Batch B prompt.
```

## Phase 1 — Tidy-up

If `.agent-policy` exists at the repo root, source it once before proceeding:

```sh
[ -f .agent-policy ] && . ./.agent-policy
```

This loads any opt-in keys consulted by Tier 2 steps. The file is optional; if absent, every Tier 2 step prompts as today.

### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, then fans out all read-only queries (status/branch/log, stashes, worktrees, merged branches, `main` CI, open PRs, assigned GitHub issues) in parallel.

```sh
~/.claude/bin/end-session-gather-state
```

Output is a sectioned stream. Each section starts with `===<name> (exit=<N>)===`. The sections are:

| Section | Drives step(s) | Notes on exit code |
| --- | --- | --- |
| `fetch` | 2 (folded in) | Non-zero = network/auth issue — surface before proceeding. |
| `local_state` | 1, 4 | Dirty tree + unpushed commits for step 4. |
| `stashes` | 9 | Exit 0 even when empty. |
| `worktrees` | 13 | Exit 0 even when empty. |
| `merged_brs` | 6 Batch A | Script appends `\|\| true` — exit 0 even if no matches. |
| `main_ci` | 3 | Content `gh-unavailable` = silent skip. Non-zero with other content = real error. |
| `open_prs` | 8 | Same skip convention as `main_ci`. |
| `gh_assigned` | 10 | Content `not-github` / `gh-unavailable` / `jq-unavailable` = silent skip. Empty content = nothing in flight. Otherwise one `#<n> <title>` line per open issue assigned to me. |
| `stale_claude_files` | 11 | Content `chezmoi-unavailable` = silent skip. Empty body (exit=0) = nothing stale. Otherwise: one path per line under `.claude/commands/` or `.claude/bin/` that's present locally but not tracked by chezmoi. |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no stashes, no merged branches, no in-progress issues, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content equal to `gh-unavailable`: silent skip (step 3 / step 8 degrade gracefully).
- `exit != 0` with other content: real error — surface it before continuing Phase 1.

### 1.5. Fast-path when state is fully clean (Tier 1 — narration optimisation)

When the gather output shows nothing actionable, skip the per-step narration entirely and jump straight to step 14 (summary). This keeps a typical short-session `/end-session` to ~12 lines of output instead of ~24 (one redundant "Step N — none" line per step).

Apply when **all** of the following hold (single-pass check over already-collected gather output — no extra calls):

- `local_state.status` is empty (clean working tree)
- `local_state.unpushed` is empty (no unpushed commits — covers steps 4 and 7)
- `merged_brs` is empty
- `stashes` is empty
- `gh_assigned` is empty (or content is `not-github` / `gh-unavailable`)
- `open_prs` is empty (or content is `gh-unavailable`)
- `main_ci` has no `failure` / `cancelled` / `timed_out` line (an `in_progress` workflow is allowed — summary still surfaces it)
- `stale_claude_files` is empty (or content is `chezmoi-unavailable`)
- `worktrees` has exactly one entry (just the primary)

If the predicate holds:

1. Emit step 14's summary directly. Every actionable line says "none"; static lines (main rebased) reflect the already-clean state.
2. Do **not** narrate steps 2–13 individually. No "Step 4 — pass", no "Step 6 — nothing to prune", no per-step status lines. The summary IS the output.
3. Phase 2's retrospective prompt still fires as today.

If **any** predicate fails, run every step as before — a messy session's narration is unchanged.

**Caveats** (deliberately accepted to keep the predicate single-pass):

- The fast-path skips step 6 Batch B's squash-merged branch check (`~/.claude/bin/end-session-squash-merged`). A `[upstream: gone]` branch with no upstream PR can linger one extra session before being detected — slow-decay, picked up next non-fast-path run.
- Background processes (step 13) aren't in the predicate. Claude tracks them from session state, not gather; if any are running, surface them in the summary regardless of fast-path.

### 2. Fetch and prune remote-tracking refs

Folded into step 1's gather. The `fetch` section contains the output. If its exit code is non-zero, stop and surface before proceeding.

### 3. Check `main` CI status (Tier 1 — surface)

From gather section `main_ci`. Parse the most recent run per workflow:

- **Failed**: flag loudly with `<workflow name>: <full run URL>` on its own line so the user can click straight through. The gather script already returns the URL in `main_ci` — print it inline; don't make the user chase it with a follow-up `gh run view`. A red `main` is the loudest "not clean" signal.
- **In progress**: list with elapsed time. Means a deploy / long check is mid-flight.
- **All green**: silent.

If the section content is `gh-unavailable` or the repo has no remote, skip silently. Carry the result forward — it gates the Phase 2 prompt.

### 4. Handle uncommitted or unpushed work (Tier 3)

Read from gather section `local_state`. Before any branch switching or deletion:

- **Dirty working tree** (non-empty `status` block): stop, show the user what's dirty, ask whether to (a) commit, (b) stash, or (c) abort the tidy-up. Do **not** silently stash.
- **Current branch has unpushed commits** and isn't `main` (non-empty `unpushed` block): surface this — ask whether to push (create PR if needed) or abort. Don't switch away from a branch with unpushed work without explicit permission.

### 5. Return to main and rebase (Tier 1)

If not already on `main` (or whatever the repo's default branch is):

```sh
git checkout main
git pull --rebase origin main
```

If the rebase fails (conflicts, divergent history), stop and surface the error — don't attempt `--abort` or destructive recovery without asking.

### 6. Prune obsolete local branches (Tier 2 — two batches, each prompted once; per-batch policy opt-in)

Two batches. Present each list, ask **one** y/n per batch, then act on the whole list. Never iterate per-branch.

**Batch A — Branches fully merged into `origin/main`** (safe, uses `-d`):

Take the list from gather section `merged_brs`.

**Batch B — Squash-merged branches** — branches whose upstream was deleted (`[upstream: gone]`, typical after GitHub squash-merge + branch delete) AND whose work is provably on `main`. These won't show up in Batch A because squash-merging rewrites history; `-d` would refuse them. The script accepts either of two "work is delivered" signals as the safety net — empty diff vs `main`, or GitHub records a merged PR with the branch as `headRefName` (fallback for cases where main has subtle post-squash drift that fails the diff but the PR clearly merged):

```sh
~/.claude/bin/end-session-squash-merged
```

For each batch:

- If empty, say so and move on.
- Otherwise present the full list. Then **either**:
  - **If the corresponding `.agent-policy` key is `true`** (`AUTO_DELETE_MERGED_BRANCHES` for Batch A, `AUTO_DELETE_SQUASH_MERGED_BRANCHES` for Batch B): skip the prompt and delete directly. Add a `Policy:` line to the Phase 1 summary noting the auto-delete fired with the deleted branch count.
  - **Otherwise (default)**: ask once: "delete all of these? (y/n)".
- On `y` (or policy fire): `-d` for Batch A, `-D` for Batch B.

If a `[gone]` branch has a non-empty diff vs `main` AND no merged PR is found via `gh`, surface it by name ("`feat/x` — upstream gone but diffs against `main` and no merged PR found, left alone") so the user can decide manually. Don't roll it into Batch B — the safety net protects the auto-delete path too.

For remote-tracking refs, `git fetch --prune` in step 2 already handled stale `origin/*` refs. Don't delete anything on the remote itself.

### 7. Push main if ahead (Tier 2 — prompt, or Tier 1 with policy opt-in)

```sh
git log origin/main..HEAD --oneline
```

If main is ahead of origin/main (shouldn't normally happen, but catches the case where commits landed locally):

- **If `AUTO_PUSH_MAIN_IF_AHEAD=true` (from `.agent-policy`)**: push directly without prompting. Add a `Policy:` line to the Phase 1 summary noting the push fired and the commit count.
- **Otherwise (default)**: ask before pushing.

### 8. Open PRs needing your action (Tier 3 — surface only)

From gather section `open_prs`. If the section content is `gh-unavailable`, either skip or fall back to `mcp__github__list_pull_requests` (state=open, head filter) — the MCP path doesn't need `gh` on PATH.

Categorise and present:

- **Mergeable, CI green, approved/no-review-needed** → "ready to merge in UI"
- **Mergeable, CI green, awaiting review** → "waiting on reviewer"
- **CI failed** → list with link to the failing run
- **Merge conflict** → list with PR URL
- **Draft** → list separately

Never auto-merge. List, link, move on.

### 9. Stashes (Tier 1 — surface)

From gather section `stashes`. If non-empty, surface count + entries. Don't drop or apply anything.

### 10. Open issues assigned to you (Tier 3 — surface)

From gather section `gh_assigned` (silently skipped when the repo has no github.com origin or `gh` / `jq` is unavailable). Each line is `#<n> <title>` — an open GitHub issue assigned to you. Surface count + numbers/titles. User decides which to close — common forgetfulness pattern.

Issues whose work merged this session via a `Closes #<n>` reference in the PR body are closed automatically by GitHub on merge, so they won't appear here. Anything listed is genuinely still outstanding — if a listed issue actually shipped without the `Closes #<n>` trailer, suggest `gh issue close <n> --comment "Shipped in #<pr>"`.

### 11. Stale Claude commands/bin files (Tier 1 — surface)

From gather section `stale_claude_files` (silently skipped when `chezmoi` isn't on PATH).

chezmoi only adds and updates target files; it never removes them when source files are renamed or deleted (unless the directory is configured `exact = true`, which has its own destructive risk for user-added files). Result: when a slash command is renamed or retired in the source repo, the OLD file lingers at `~/.claude/commands/` on every machine that ever applied a version where it was present. Claude Code still sees the stale file and lists it as a slash command, so the drift compounds across versions.

The gather computes `chezmoi managed` minus actual contents under `~/.claude/commands/` and `~/.claude/bin/`, and emits any extras (one path per line). Surface them with a one-line `rm` suggestion the user can paste:

```text
2 stale file(s) under ~/.claude/:
  ~/.claude/commands/old-thing.md
  ~/.claude/bin/legacy-script

Suggested: rm ~/.claude/commands/old-thing.md ~/.claude/bin/legacy-script
```

Don't `rm` automatically — the user might be testing an unstaged file, or these may belong to another tool. The check is "fast" (one `chezmoi managed` + two `find`s) so it runs unconditionally per session.

### 12. Other worktrees (Tier 3 — surface)

From gather section `worktrees`. If more than one entry, list non-primary worktrees with their branch. If any have uncommitted work, flag with `*`. Don't remove anything.

### 13. Background processes

Split by origin:

- **Spawned by Claude in this session** (via `run_in_background`): list. Reap any that have completed (Tier 1 — auto). If still running and the task seems incomplete, surface before reaping.
- **Started by the user / pre-existing**: surface only (Tier 3). Don't kill.

### 14. Phase 1 summary

Print a concise summary. Each line says "none" loudly when clean, so noise scales with actual mess. (Step 1.5's fast-path also lands here directly when the predicate holds — same format, all "none" lines.)

- Branches pruned (merged): `<list or "none">`
- Branches pruned (squash-merged): `<list or "none">`
- Stashed/committed work this run: `<describe or "none">`
- Main rebased: `<yes/no, behind/ahead counts>`
- `main` CI status: `<green / running: N (<workflow names>) / FAILED: <workflow name + run URL>>`
- Open PRs needing action: `<count by category, or "none">`
- Stashes outstanding: `<count, or "none">`
- Open issues assigned to you: `<count, or "none">`
- Stale `~/.claude/` files: `<count, or "none" / "n/a (no chezmoi)">`
- Other worktrees: `<count, or "none">`
- Background processes (reaped): `<count>`
- Background processes (user-owned, surfaced): `<count>`
- Policy: `<list of .agent-policy keys that fired this session, e.g. "AUTO_DELETE_MERGED_BRANCHES → 3 deleted">` — omit the line entirely when no keys fired or the file is absent. Don't list keys that were set but had nothing to do (e.g. `AUTO_DELETE_MERGED_BRANCHES=true` with no merged branches).
- Anything skipped/surfaced: `<list>`

## Phase 2 — Retrospective

If `main` CI is **failing** or **currently running** (per step 3), pre-prompt:

> `main` CI is `<failing|running>`. Defer the retrospective? (y/n)

On `y`: stop here. Re-run `/end-session` later or run `/retrospective` directly when ready.

Otherwise (or after the pre-prompt is dismissed with `n`), ask:

> Proceed to retrospective? (y/n)

On `y`: invoke the `retrospective` skill via the Skill tool. Do not perform the retrospective inline — let the skill own its contract.

On `n`: stop. The session is tidied; the user can run `/retrospective` later if they change their mind.

## Guardrails

- **`-D` (force delete) is allowed only for Batch B of step 6** — branches that are `[upstream: gone]` AND have an empty `git diff` against `main` (or a merged PR via `gh`). Everywhere else: always `-d`. If `-d` refuses, that's signal — surface it, don't override. The Batch B safety net protects the `AUTO_DELETE_SQUASH_MERGED_BRANCHES` opt-in path identically — auto-delete only acts on entries that already passed the safety check.
- **Never `git push --force` or `git reset --hard`.** Those aren't session-tidy operations; if they're needed, the user should drive them.
- **Never auto-merge PRs, auto-close issues, or auto-drop stashes.** Per-item judgment lives with the user (Tier 3).
- **Ask before every Tier 2 destructive action by default** (branch deletes, force-pushing). One y/n per batch is fine — don't ask per-branch if a single list is presented. The `.agent-policy` keys (`AUTO_DELETE_MERGED_BRANCHES`, `AUTO_DELETE_SQUASH_MERGED_BRANCHES`, `AUTO_PUSH_MAIN_IF_AHEAD`) are the only sanctioned way to skip the prompt, and they're per-repo opt-in.
- **Don't modify settings, config, or unrelated files.** This command's scope is git, GitHub, and process state only.
- **`.agent-policy` only promotes Tier 2 → Tier 1 for the keys it explicitly governs.** Tier 3 surfaces (user judgment) cannot be opted in. Unknown keys are ignored silently.
