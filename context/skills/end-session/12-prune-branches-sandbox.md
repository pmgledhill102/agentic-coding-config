### 6. Prune obsolete local branches (Tier 2 — two batches, each prompted once)

Local branch tidiness matters less here than on a durable machine — the
container is reclaimed with every branch in it — so this step is worth doing
quickly and is never worth a long investigation. Two batches. Present each
list, ask **one** y/n per batch, then act on the whole list. Never iterate
per-branch.

**Batch A — Branches fully merged into `origin/main`** (safe, uses `-d`):

Take the list from gather section `merged_brs`.

**Batch B — Squash-merged branches** — branches whose upstream was deleted (`[upstream: gone]`, typical after GitHub squash-merge + branch delete) AND whose work is provably on `main`. These won't show up in Batch A because squash-merging rewrites history; `-d` would refuse them. The script's safety net is an empty diff vs `main`:

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/end-session-squash-merged
```

The script's second safety-net signal — GitHub recording a merged PR for the branch — is a `gh` query, so it never fires here. That matters for one case only: a `[gone]` branch that diffs against `main` because of post-squash drift, which the script therefore leaves unresolved rather than putting in Batch B. Before presenting such a branch as unresolved, check the same signal directly:

```text
mcp__github__list_pull_requests(owner, repo, state: "closed", head: "<owner>:<branch>")
```

A returned PR with `merged_at` set is the merged-PR signal. On a hit, the branch joins Batch B under the usual single y/n; on a miss, surface it by name ("`feat/x` — upstream gone but diffs against `main` and no merged PR found, left alone") so the user can decide manually. Don't roll it into Batch B without that signal — the safety net protects the auto-delete path too.

For remote-tracking refs, `git fetch --prune` in step 2 already handled stale `origin/*` refs. **Never try to delete a branch on the remote from here:** the sandbox git proxy refuses ref deletion (§Surface, [#252](https://github.com/pmgledhill102/agentic-coding-config/issues/252)). If a remote branch genuinely needs deleting, put it in the step 14 summary as "could not prune: `<branch>` — ref deletion refused by sandbox git proxy (#252)" and leave it for the user. Never retry until it "works", and never report the prune as done.
