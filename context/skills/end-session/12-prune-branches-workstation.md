### 6. Prune obsolete local branches (Tier 2 — two batches, each prompted once)

Two batches. Present each list, ask **one** y/n per batch, then act on the whole list. Never iterate per-branch.

**Batch A — Branches fully merged into `origin/main`** (safe, uses `-d`):

Take the list from gather section `merged_brs`.

**Batch B — Branches whose upstream is gone** — `[upstream: gone]` is the usual shape after a GitHub squash-merge with branch delete. Squash-merging rewrites history, so these never appear in Batch A and `-d` refuses them. The script lists the candidates and the evidence it could gather locally; it does **not** decide that any of them is safe to delete:

```sh
~/.claude/bin/end-session-squash-merged
```

One line per candidate:

```text
<branch> tip=<sha> diff=<empty|differs> pr=<sha-match|newer-commits|none|unchecked>
```

Neither evidence field is a containment proof on its own, which is why the script stopped claiming one ([#302](https://github.com/pmgledhill102/agentic-coding-config/issues/302)). `diff=` is a two-dot *tree* diff against `main`, so it reads `differs` the moment `main` advances past the squash — on an active repo, minutes after the merge. `pr=unchecked` means the question was never asked (no `gh`, or `gh` not authorised for repo data), never that no PR merged.

**The proof is one MCP call, made here, once for the whole batch** — not per branch:

```text
mcp__github__list_pull_requests(owner, repo, state: "closed", perPage: 100)
```

A candidate is provably delivered when the response holds a PR that

1. is **merged** — `merged_at` is set; a closed-unmerged PR proves the opposite,
2. carries the branch as `head.ref`, **and**
3. whose `head.sha` equals that candidate's `tip=`.

All three are required, and (3) is the one that is easy to drop. Matching on `head.ref` alone deletes a branch that took commits *after* its PR merged — those commits are on no other ref, so `-D` destroys them ([#435](https://github.com/pmgledhill102/agentic-coding-config/issues/435)). The script's own `pr=sha-match` is the same test run through `gh` where `gh` works; `pr=newer-commits` is exactly that failure caught, and such a branch is never a delete candidate.

If the MCP call cannot be made, Batch B is **unproven, not empty**: report it as `n/a (no GitHub route)` and delete nothing. An unchecked batch must never render as "none".

For each batch:

- If empty, say so and move on.
- Otherwise present the full list and ask once: "delete all of these? (y/n)".
- On `y`: `-d` for Batch A, `-D` for Batch B.

Surface by name, outside the batch, every candidate the proof did not cover, with the reason: "`feat/x` — upstream gone, merged PR #N found but its head SHA is not this branch's tip (commits pushed after the merge), left alone", or "`feat/y` — upstream gone and no merged PR found, left alone". The user decides those manually; don't roll them into Batch B, because the proof protects the auto-delete path and nothing else.

For remote-tracking refs, `git fetch --prune` in step 2 already handled stale `origin/*` refs. Don't delete anything on the remote itself — prefer deletion to happen server-side at merge time (`delete_branch: true` on the merge call), so no session ever pushes a ref deletion.
