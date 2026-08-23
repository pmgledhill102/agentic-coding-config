### 1.5. Fast-path when state is fully clean (Tier 1 — narration optimisation)

When the gather output shows nothing actionable, skip the per-step narration entirely and jump straight to step 14 (summary). This keeps a typical short-session `end-session` to ~12 lines of output instead of ~24 (one redundant "Step N — none" line per step).

Apply when **all** of the following hold (single-pass check over already-collected results — no extra calls):

- `local_state.status` is empty (clean working tree)
- `local_state.unpushed` is empty (no unpushed commits — covers steps 4 and 7)
- `stashes` is empty
- the step 1(b) issue query returned nothing assigned to you
- the step 1(b) PR query returned no open PRs

Three sections the workstation predicate checks are absent here, because the steps that consume them do no work on this surface: `merged_brs` (step 6), `worktrees` (step 12) and `stale_claude_files` (step 11). A predicate term whose step is skipped can only make the fast-path fire less often, never more correctly.

**The two MCP calls run before this predicate is evaluated, not instead of it.** They are step 1's work, not a recovery path, so "the query was skipped" is never a reason a line is empty. A line whose query genuinely failed reads `n/a (no GitHub route)` and **fails** the predicate — the fast-path is a narration optimisation, not permission to report an unchecked section as clean.

If the predicate holds:

1. Emit step 14's summary directly. Every actionable line says "none"; static lines (main rebased) reflect the already-clean state.
2. Do **not** narrate steps 2–13 individually. No "Step 4 — pass", no "Step 6 — nothing to prune", no per-step status lines. The summary IS the output.
3. Phase 2 still runs the retrospective — the fast-path shortens Phase 1 narration, not the session-closing work.

If **any** predicate fails, run every step as before — a messy session's narration is unchanged.

**Caveats** (deliberately accepted to keep the predicate single-pass):

- Steps 6 and 12 are not in the predicate because they do no work on this surface (see those steps). Their summary lines read `n/a (sandbox — container discarded)` whether the fast-path fires or not.
- Background processes (step 13) aren't in the predicate. Claude tracks them from session state, not gather; if any are running, surface them in the summary regardless of fast-path.
