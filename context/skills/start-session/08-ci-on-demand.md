### 4. CI status — on demand, not gathered (Tier 1)

**Default-branch CI is deliberately not fetched at session start (#273).** It was the least-actionable line in the brief — a gated default branch is rarely red, and a push surfaces a break within one cycle anyway — yet the most expensive to gather: the only route on a surface without `gh` is `mcp__github__actions_list`, which dumps every workflow run unreduced (~104K tokens, enough to overflow context) because it has no server-side field selection. Paying that every session to pre-answer a question nobody usually acts on is the opposite of what this gather is for.

So the brief carries no CI line. When CI status actually matters — you are about to build on the default branch and want to know it is green, or you are checking a PR you just pushed — query it **scoped, on demand**:

- **A specific PR** (the common case): `mcp__github__pull_request_read` with method `get_check_runs` (GitHub Actions report as check runs, not the legacy combined status, so `get_status` shows `total_count: 0` and is the wrong call here). One PR's check runs are a few KB — summarise to pass/fail counts and surface only failures.
- **The default branch with no PR**: the head commit's checks via the same tool against the relevant PR, or `mcp__github__actions_list` filtered to a single workflow if you genuinely need the repo-wide picture — but reach for that only when asked, given its cost.
