### 1.5. Fast-path when state is fully clean (Tier 1 — narration optimisation)

When the gather output shows nothing actionable, skip the per-step narration entirely and jump straight to step 14 (summary). This keeps a typical short-session `end-session` to ~12 lines of output instead of ~24 (one redundant "Step N — none" line per step).

Apply when **all** of the following hold (single-pass check over already-collected results — no extra calls):

- `local_state.status` is empty (clean working tree)
- `local_state.unpushed` is empty (no unpushed commits — covers steps 4 and 7)
- `merged_brs` is empty
- `stashes` is empty
- the step 1(b) issue query returned nothing assigned to you
- the step 1(b) PR query returned no open PRs
- `worktrees` has exactly one entry (just the primary)

`stale_claude_files` is not in the predicate: there is no chezmoi here, so it never has anything to say (step 11).

**The two MCP calls run before this predicate is evaluated, not instead of it.** They are step 1's work, not a recovery path, so "the query was skipped" is never a reason a line is empty. A line whose query genuinely failed reads `n/a (no GitHub route)` and **fails** the predicate — the fast-path is a narration optimisation, not permission to report an unchecked section as clean.

If the predicate holds:

1. Emit step 14's summary directly. Every actionable line says "none"; static lines (main rebased) reflect the already-clean state.
2. Do **not** narrate steps 2–13 individually. No "Step 4 — pass", no "Step 6 — nothing to prune", no per-step status lines. The summary IS the output.
3. Phase 2's retrospective prompt still fires as today.

If **any** predicate fails, run every step as before — a messy session's narration is unchanged.

**Caveats** (deliberately accepted to keep the predicate single-pass):

- The fast-path skips step 6 Batch B's squash-merged branch check (`~/.claude/bin/end-session-squash-merged`). Local branch tidiness is close to free here anyway — the container is disposable, so a lingering branch costs nothing beyond this session.
- Background processes (step 13) aren't in the predicate. Claude tracks them from session state, not gather; if any are running, surface them in the summary regardless of fast-path.
