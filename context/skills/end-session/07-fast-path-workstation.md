### 1.5. Fast-path when state is fully clean (Tier 1 — narration optimisation)

When the gather output shows nothing actionable, skip the per-step narration entirely and jump straight to step 14 (summary). This keeps a typical short-session `end-session` to ~12 lines of output instead of ~24 (one redundant "Step N — none" line per step).

Apply when **all** of the following hold (single-pass check over already-collected gather output — no extra calls):

- `local_state.status` is empty (clean working tree)
- `local_state.unpushed` is empty (no unpushed commits — covers steps 4 and 7)
- `merged_brs` is empty
- `stashes` is empty
- `gh_assigned` is empty (or content is `not-github` — the section is silent on a repo with no GitHub origin)
- `open_prs` is empty
- `stale_claude_files` is empty (or content is `chezmoi-unavailable`)
- `worktrees` has exactly one entry (just the primary)

If the predicate holds:

1. Emit step 14's summary directly. Every actionable line says "none"; static lines (main rebased) reflect the already-clean state. A line whose section could not be gathered says `n/a (gh absent)` instead — the fast-path is a narration optimisation, not permission to report an unchecked section as clean.
2. Do **not** narrate steps 2–13 individually. No "Step 4 — pass", no "Step 6 — nothing to prune", no per-step status lines. The summary IS the output.
3. Phase 2 still runs the retrospective — the fast-path shortens Phase 1 narration, not the session-closing work.

If **any** predicate fails, run every step as before — a messy session's narration is unchanged.

**Caveats** (deliberately accepted to keep the predicate single-pass):

- The fast-path skips step 6 Batch B's squash-merged branch check (`~/.claude/bin/end-session-squash-merged`). A `[upstream: gone]` branch with no upstream PR can linger one extra session before being detected — slow-decay, picked up next non-fast-path run.
- Background processes (step 13) aren't in the predicate. Claude tracks them from session state, not gather; if any are running, surface them in the summary regardless of fast-path.
