### 3. Check CI on the PRs you touched — on demand (Tier 1 — surface)

**Repo-wide default-branch CI is deliberately not gathered (#273):** the only route without `gh` is `mcp__github__actions_list`, which dumps every run unreduced (~104K tokens, overflows context), to answer a question `end-session` rarely acts on. What matters at walk-away is whether the PR(s) you pushed this session are green — a scoped, cheap query.

For each PR you created or pushed to this run, check it with `mcp__github__pull_request_read` method `get_check_runs` (Actions report as check runs; `get_status` returns `total_count: 0` and is the wrong call). Summarise to pass/fail:

- **Failed**: flag loudly with `<workflow name>: <run URL>` on its own line, and carry it into the walk-away summary — a red PR you own is unfinished work, not a clean exit. It does not defer the retrospective: that runs either way (Phase 2), and a failure worth acting on is worth the retro noticing.
- **In progress**: note it as running; the PR isn't confirmed green yet.
- **All green**: say so.

If no PR was touched this session, skip. Never carry an unchecked CI state forward as clean — an unqueried PR reads as **unknown**, not green.
