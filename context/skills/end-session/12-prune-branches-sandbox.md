### 6. Prune obsolete local branches (n/a here)

**Skipped on this surface.** Local branches live on a disk that is about to be
discarded — the container is reclaimed after a period of inactivity, usually
soon after this skill finishes — so deleting them achieves nothing and costs a
prompt. Report `n/a (sandbox — container discarded)` in the step 15 summary and
move on.

Do not run `end-session-squash-merged` here either. It exists to decide which
branches are safe to delete, and nothing is being deleted.

**This is a skip of *cleanup*, never of *push*.** The distinction matters more
here than anywhere else in this skill: a local branch left behind costs
nothing, and an unpushed commit is destroyed. Steps 4 and 7 run exactly as they
do on a durable machine, and if anything they matter more.

One thing that is not skipped, because it is not local cleanup: if a **remote**
branch genuinely needs deleting, say so in the summary rather than attempting
it. The sandbox git proxy refuses ref deletion (§Surface,
[#252](https://github.com/pmgledhill102/agentic-coding-config/issues/252)), so
the attempt fails in a way that reads like a network blip. Branch cleanup at
merge time (`delete_branch: true` on the merge call) is the route that works.
