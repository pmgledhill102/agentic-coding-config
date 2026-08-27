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

If a `[gone]` branch has a non-empty diff vs `main` AND no merged PR is found, surface it by name ("`feat/x` — upstream gone but diffs against `main` and no merged PR found, left alone") so the user can decide manually. Don't roll it into Batch B — the safety net protects the auto-delete path too.

For remote-tracking refs, `git fetch --prune` in step 2 already handled stale `origin/*` refs. Don't delete anything on the remote itself — prefer deletion to happen server-side at merge time (`delete_branch: true` on the merge call), so no session ever pushes a ref deletion.
