End-of-session tidy-up: leave git, GitHub, beads, and Claude Code state at a verifiable "clean walk-away" point, then optionally run the retrospective.

This command runs in two phases. Phase 1 is the tidy-up (mix of auto-actions and confirmations). Phase 2 is a prompt to kick off the retrospective. The retrospective itself is read-only — it only updates `~/.claude/retros.md` — so all repo-state changes must happen in Phase 1.

## Action tiers

Every step in Phase 1 falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase`, `bd dolt push`, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: destructive but predictable, judgment is yes/no for the whole list. Examples: deleting merged branches, deleting squash-merged branches, pushing `main` if ahead.
- **Tier 3 — surface only, user drives**: needs per-item judgment, or affects shared state in ways one y/n can't capture. Examples: open PRs awaiting merge, `bd in_progress` issues, stashes, user-started background processes.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.

## Pre-flight

This command **requires a git-backed repository**. Run the bare command below and branch on its exit code — don't paste a compound `||` / `&&` form, which won't match any single allow rule and will trigger a permission prompt.

```sh
git rev-parse --is-inside-work-tree
```

If the exit code is non-zero (or stdout is not `true`), print a single-line warning (`` `/end-session` requires a git-backed repo — nothing to tidy, stopping. ``) and stop. Do not run any further checks, do not proceed to Phase 2.

## Phase 1 — Tidy-up

### 1. Gather state (Tier 1 — one tool call)

Run the parallel gather script. It does `git fetch --all --prune --tags` first, then fans out all read-only queries (status/branch/log, stashes, worktrees, merged branches, `main` CI, open PRs, beads in-progress) in parallel.

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
| `bd_progress` | 10 | Section absent if no beads workspace. All entries are `in_progress` by definition (that's the filter) — see step 10 for symbol-reading rules. |
| `bd_inprogress_delivered` | 9.5 | Section absent if no beads workspace. Empty content = nothing to auto-close. Each line is `<id>\|<short-sha>\|<subject>` for an in_progress bead whose ID was referenced by a merged commit on `main` (`Closes <id>` / `Fixes <id>`). Mirrors `/start-session`'s section of the same name. |
| `stale_claude_files` | 11 | Content `chezmoi-unavailable` = silent skip. Empty body (exit=0) = nothing stale. Otherwise: one path per line under `.claude/commands/` or `.claude/bin/` that's present locally but not tracked by chezmoi. |

Rules for interpreting exit codes:

- `exit=0` with empty content: clean result (no stashes, no merged branches, no in-progress issues, etc.). Treat as "none".
- `exit=0` with content: normal data — parse it for the relevant step.
- `exit != 0` with content equal to `gh-unavailable`: silent skip (step 3 / step 8 degrade gracefully).
- `exit != 0` with other content: real error — surface it before continuing Phase 1.

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

### 6. Prune obsolete local branches (Tier 2 — two batches, each prompted once)

Two batches. Present each list, ask **one** y/n per batch, then act on the whole list. Never iterate per-branch.

**Batch A — Branches fully merged into `origin/main`** (safe, uses `-d`):

Take the list from gather section `merged_brs`.

**Batch B — Squash-merged branches** — branches whose upstream was deleted (`[upstream: gone]`, typical after GitHub squash-merge + branch delete) AND whose work is provably on `main`. These won't show up in Batch A because squash-merging rewrites history; `-d` would refuse them. The script accepts either of two "work is delivered" signals as the safety net — empty diff vs `main`, or GitHub records a merged PR with the branch as `headRefName` (fallback for cases where main has subtle post-squash drift that fails the diff but the PR clearly merged):

```sh
~/.claude/bin/end-session-squash-merged
```

For each batch:

- If empty, say so and move on.
- Otherwise present the full list and ask once: "delete all of these? (y/n)".
- On `y`: `-d` for Batch A, `-D` for Batch B.

If a `[gone]` branch has a non-empty diff vs `main` AND no merged PR is found via `gh`, surface it by name ("`feat/x` — upstream gone but diffs against `main` and no merged PR found, left alone") so the user can decide manually. Don't roll it into Batch B.

For remote-tracking refs, `git fetch --prune` in step 2 already handled stale `origin/*` refs. Don't delete anything on the remote itself.

### 7. Push main if ahead (Tier 2)

```sh
git log origin/main..HEAD --oneline
```

If main is ahead of origin/main (shouldn't normally happen, but catches the case where commits landed locally), ask before pushing.

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

### 9.5. Auto-close delivered in_progress beads (Tier 1)

From gather section `bd_inprogress_delivered` (absent if no beads workspace; empty if nothing matched). Each line is `<id>|<short-sha>|<subject>` — an `in_progress` bead whose ID was referenced by a merged commit on `main` with `Closes <id>` or `Fixes <id>` in the message.

These are deliveries that landed in this session (or a recent prior one) but never had their bead closed. The PR was already reviewed and merged; closing the bead is bookkeeping, not a judgment call. Auto-close each one — no prompt:

```sh
bd close <id> --reason="Auto-closed by /end-session: shipped via <short-sha>"
```

Step 14 (`bd dolt push`) persists the closures. If the section is absent, empty, or nothing matched: skip silently. The Phase 1 summary shows a `Beads auto-closed (delivered)` line listing what was closed (omit when nothing was closed).

This step duplicates `/start-session`'s step 5 logic so deliveries close at end-of-session rather than waiting for the next session start. Defense in depth: if the user shuts down without running `/start-session` next morning, the closure already lands. False-positive risk is low (a stray `Closes <bead-id>` in non-closing context); recovery is `bd reopen <id>`.

### 10. Beads in-progress check (Tier 3 — surface)

From gather section `bd_progress` (absent if no beads workspace). The section is the output of `bd list --status=in_progress`, so **every entry is in_progress** — never report these as "blocked". Filter to issues claimed by the current user (assignee matches `git config user.email` or local username). Surface count + IDs/titles. User decides which to close — common forgetfulness pattern.

**Note**: any beads auto-closed in step 9.5 won't appear here — they're already closed by the time this step runs. So this list is genuinely "still outstanding work", not "delivered but not bookkept".

**Reading bd's symbols (don't conflate them):**

- The leading glyph on each line is the **status**: `○` open · `◐` in_progress · `●` blocked · `✓` closed · `❄` deferred. In this section it's always `◐`.
- A `●` appearing later in the line (e.g., inside `[● P2]`) is a **priority indicator**, not a blocked-status flag. The bd legend printed at the bottom of `bd list` uses `●` for "blocked" and reuses the same glyph for priority — that collision is the trap.
- If you want to know what's actually blocked, run `bd blocked` — don't infer from later-line glyphs.

### 11. Stale Claude commands/bin files (Tier 1 — surface)

From gather section `stale_claude_files` (silently skipped when `chezmoi` isn't on PATH).

chezmoi only adds and updates target files; it never removes them when source files are renamed or deleted (unless the directory is configured `exact = true`, which has its own destructive risk for user-added files). Result: when a slash command is renamed in the source repo (e.g. `bd-migrate-embedded.md` → `bd-modernize.md`), the OLD file lingers at `~/.claude/commands/` on every machine that ever applied a version where it was present. Claude Code still sees the stale file and lists it as a slash command, so the drift compounds across versions.

The gather computes `chezmoi managed` minus actual contents under `~/.claude/commands/` and `~/.claude/bin/`, and emits any extras (one path per line). Surface them with a one-line `rm` suggestion the user can paste:

```text
3 stale file(s) under ~/.claude/:
  ~/.claude/commands/bd-migrate-embedded.md
  ~/.claude/commands/old-thing.md
  ~/.claude/bin/legacy-script

Suggested: rm ~/.claude/commands/bd-migrate-embedded.md ~/.claude/commands/old-thing.md ~/.claude/bin/legacy-script
```

Don't `rm` automatically — the user might be testing an unstaged file, or these may belong to another tool. The check is "fast" (one `chezmoi managed` + two `find`s) so it runs unconditionally per session.

### 12. Other worktrees (Tier 3 — surface)

From gather section `worktrees`. If more than one entry, list non-primary worktrees with their branch. If any have uncommitted work, flag with `*`. Don't remove anything.

### 13. Background processes

Split by origin:

- **Spawned by Claude in this session** (via `run_in_background`): list. Reap any that have completed (Tier 1 — auto). If still running and the task seems incomplete, surface before reaping.
- **Started by the user / pre-existing**: surface only (Tier 3). Don't kill.

### 14. Beads sync (Tier 1)

If `.beads/metadata.json` exists:

```sh
bd dolt push
```

If this fails, surface the error but don't block the phase — the user can retry manually.

### 15. Phase 1 summary

Print a concise summary. Each line says "none" loudly when clean, so noise scales with actual mess:

- Branches pruned (merged): `<list or "none">`
- Branches pruned (squash-merged): `<list or "none">`
- Stashed/committed work this run: `<describe or "none">`
- Main rebased: `<yes/no, behind/ahead counts>`
- `main` CI status: `<green / running: N (<workflow names>) / FAILED: <workflow name + run URL>>`
- Open PRs needing action: `<count by category, or "none">`
- Stashes outstanding: `<count, or "none">`
- Beads auto-closed (delivered): `<list of ids, or "none">`
- Beads in_progress (yours): `<count, or "none">`
- Stale `~/.claude/` files: `<count, or "none" / "n/a (no chezmoi)">`
- Other worktrees: `<count, or "none">`
- Background processes (reaped): `<count>`
- Background processes (user-owned, surfaced): `<count>`
- Beads pushed: `<yes/no/n/a>`
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

- **`-D` (force delete) is allowed only for Batch B of step 6** — branches that are `[upstream: gone]` AND have an empty `git diff` against `main`. Everywhere else: always `-d`. If `-d` refuses, that's signal — surface it, don't override.
- **Never `git push --force` or `git reset --hard`.** Those aren't session-tidy operations; if they're needed, the user should drive them.
- **Never auto-merge PRs, auto-close issues, or auto-drop stashes.** Per-item judgment lives with the user (Tier 3).
- **Ask before every Tier 2 destructive action** (branch deletes, force-pushing). One y/n per batch is fine — don't ask per-branch if a single list is presented.
- **Don't modify settings, config, or unrelated files.** This command's scope is git, GitHub, beads, and process state only.
